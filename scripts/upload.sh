#!/bin/bash
set -eo pipefail

[[ -z "${DTRACK_URL}" ]] && { echo "[-] DTRACK_URL not set"; exit 1; }
[[ -z "${DTRACK_KEY}" ]] && { echo "[-] DTRACK_KEY not set"; exit 1; }

# register in Github runner the API KEY as a secret -> it will not be echoed in the logs
echo "::add-mask::$DTRACK_KEY" 

# prepare basic auth args and protects them from leakage in the logs
BASIC_AUTH_ARGS=()
if [[ -n "${BASIC_USER}" ]]; then
    [[ -n "${BASIC_PASSWORD}" ]] || { echo "[-] BASIC_PASSWORD not set"; exit 1; }
    # mask both the secret and its base64
    echo "::add-mask::$BASIC_PASSWORD"
    echo "::add-mask::$(printf '%s:%s' "$BASIC_USER" "$BASIC_PASSWORD" | base64 -w0)"
    BASIC_AUTH_ARGS=(--user "${BASIC_USER}:${BASIC_PASSWORD}")
fi

DEPTRACK_RETRIES_TIMEOUT=25
VERBOSE="--verbose"
# INSECURE="--insecure"

# for monorepos : change project name with sub-directory
DIRECTORY_NAME_CLEAN=$(echo "$DIRECTORY" | sed -e 's#^\(\./\)*##' -e 's#/*$##')
if [ -z "$DIRECTORY_NAME_CLEAN" ] || [ "$DIRECTORY_NAME_CLEAN" = "." ]; then
    PROJECT_NAME="$GITHUB_REPOSITORY"
else
    PROJECT_NAME="$GITHUB_REPOSITORY-$DIRECTORY_NAME_CLEAN"
    echo "[*] Using Dependency Track project : $PROJECT_NAME"
fi

if [ -n "$VERBOSE" ]; then
    echo "[*] DEBUG : show SBOM content :"
    echo "------ BEGIN SBOM ----"
    cat "$SBOM_FILENAME"
    echo "------ END SBOM ----"
fi

# UPLOAD BoM to Dependency track server
echo "[*] Uploading BoM file to Dependency Track server"
upload_bom_response=$(curl $INSECURE $VERBOSE -s --location --fail --request POST ${DTRACK_URL%/}/api/v1/bom \
"${BASIC_AUTH_ARGS[@]}" \
--header "X-Api-Key: $DTRACK_KEY" \
--header "Content-Type: multipart/form-data" \
--form "autoCreate=true" \
--form "projectName=$PROJECT_NAME" \
--form "projectVersion=$GITHUB_REF" \
--form "bom=@$SBOM_FILENAME")

token=$(echo $upload_bom_response | jq ".token // empty" | tr -d "\"")
echo "[*] BoM file succesfully uploaded with token $token"


if [ -z $token ]; then
    echo "[-]  The BoM file has not been successfully processed by OWASP Dependency Track"
    exit 1
fi

echo "[*] Checking BoM processing status"
processing=$(curl $INSECURE $VERBOSE -s --location --fail --request GET ${DTRACK_URL%/}/api/v1/bom/token/$token \
"${BASIC_AUTH_ARGS[@]}" --header "X-Api-Key: $DTRACK_KEY" | jq '.processing')


while [ "$processing" != "false" ]; do
    sleep 10
    processing=$(curl $INSECURE $VERBOSE -s --location --fail --request GET ${DTRACK_URL%/}/api/v1/bom/token/$token \
"${BASIC_AUTH_ARGS[@]}" --header "X-Api-Key: $DTRACK_KEY" | jq '.processing')
    c=$((c + 1))
    if [ "$c" -eq $DEPTRACK_RETRIES_TIMEOUT ]; then
        echo "[-]  Timeout while waiting for processing result. Please check the OWASP Dependency Track status."
        exit 1
    fi
done

echo "[*] OWASP Dependency Track processing completed"

# wait to make sure the score is available, some errors found during tests w/o this wait
sleep 10

echo "[*] Retrieving project information"
project=$(curl  $INSECURE $VERBOSE -s --location --fail --get "${DTRACK_URL%/}/api/v1/project/lookup" \
"${BASIC_AUTH_ARGS[@]}" \
--data-urlencode "name=$PROJECT_NAME" \
--data-urlencode "version=$GITHUB_REF" \
--header "X-Api-Key: $DTRACK_KEY")

echo "$project"

project_uuid=$(echo $project | jq ".uuid" | tr -d "\"")
risk_score=$(echo $project | jq ".lastInheritedRiskScore")
echo "Project risk score: $risk_score"

echo "riskscore=$risk_score" >> "$GITHUB_OUTPUT"
