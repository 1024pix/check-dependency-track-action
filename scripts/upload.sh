#!/bin/bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

deptrack_init


# for monorepos : change project name with sub-directory
PROJECT_NAME=$(compute_project_name)
echo "[*] Using Dependency Track project : $PROJECT_NAME"

if [ -n "${VERBOSE:-}" ]; then
    echo "[*] DEBUG : show SBOM content :"
    echo "------ BEGIN SBOM ----"
    cat "$SBOM_FILENAME"
    echo "------ END SBOM ----"
fi

# UPLOAD BoM to Dependency track server
echo "[*] Uploading BoM file to Dependency Track server"
upload_bom_response=$(deptrack_curl /api/v1/bom --request POST  \
    --header "Content-Type: multipart/form-data" \
    --form "autoCreate=true" \
    --form "projectName=$PROJECT_NAME" \
    --form "projectVersion=$GITHUB_REF" \
    --form "bom=@$SBOM_FILENAME")

token=$(echo "$upload_bom_response" | jq ".token // empty" | tr -d "\"")
echo "[*] BoM file succesfully uploaded with token $token"


if [ -z "$token" ]; then
    echo "[-]  The BoM file has not been successfully processed by OWASP Dependency Track"
    exit 1
fi
check_uuid "$token"

case "${WAIT_FOR_STATUS:-true}" in
  true) ;;
  false)
    # compute token JSON
    UPLOAD_JSON=$(jq -nc --arg name "$PROJECT_NAME" --arg version "$GITHUB_REF" --arg token "$token" \
        '{name:$name, version:$version, token:$token}')
    echo "upload=$UPLOAD_JSON" >> "$GITHUB_OUTPUT"
    echo "[*] BoM uploaded, not waiting for processing"
    exit 0 ;;
  *) 
    echo "[-] wait_for_status must be true or false"
    exit 1 ;;
esac

#### Fetch status and results
deptrack_wait_tokens "$token"

echo "[*] OWASP Dependency Track processing completed"

# wait to make sure the score is available, some errors found during tests w/o this wait
sleep 10

echo "[*] Retrieving project information"
project=$(deptrack_curl "/api/v1/project/lookup" --get \
    --data-urlencode "name=$PROJECT_NAME" \
    --data-urlencode "version=$GITHUB_REF")

echo "$project"

project_uuid=$(echo "$project" | jq ".uuid" | tr -d "\"") # unused
risk_score=$(echo "$project" | jq ".lastInheritedRiskScore")
echo "Project risk score: $risk_score"

echo "riskscore=$risk_score" >> "$GITHUB_OUTPUT"

# returns a status value based on policies (pass/warn/fail)
fail=$(jq -r '.metrics.policyViolationsFail // 0' <<<"$project")
warn=$(jq -r '.metrics.policyViolationsWarn // 0' <<<"$project")
if   (( fail > 0 )); then status=fail
elif (( warn > 0 )); then status=warn
else status=pass; fi
echo "status=$status" >> "$GITHUB_OUTPUT"

{
  echo "### Dependency-Track: ${status}"
  echo "| Critical | High | Medium | Low | Risk score |"
  echo "|---|---|---|---|---|"
  jq -r '.metrics | "| \(.critical // 0) | \(.high // 0) | \(.medium // 0) | \(.low // 0) | \(.inheritedRiskScore // 0) |"' <<<"$project"
} >> "$GITHUB_STEP_SUMMARY"