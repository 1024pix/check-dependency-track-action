# shellcheck shell=bash

DEPTRACK_RETRIES_TIMEOUT=25
# VERBOSE="--verbose"
# INSECURE="--insecure"

deptrack_init() {
	# register in Github runner the API KEY as a secret -> it will not be echoed in the logs
	echo "::add-mask::$DTRACK_KEY" 

	# checks
	[[ -z "${DTRACK_URL:-}" ]] && { echo "[-] DTRACK_URL not set"; exit 1; }
	[[ -z "${DTRACK_KEY:-}" ]] && { echo "[-] DTRACK_KEY not set"; exit 1; }

	# prepare basic auth args and protects them from leakage in the logs
	BASIC_AUTH_ARGS=()
	if [[ -n "${BASIC_USER:-}" ]]; then
		[[ -n "${BASIC_PASSWORD:-}" ]] || { echo "[-] BASIC_PASSWORD not set"; exit 1; }
		# mask both the secret and its base64
		echo "::add-mask::$BASIC_PASSWORD"
		echo "::add-mask::$(printf '%s:%s' "$BASIC_USER" "$BASIC_PASSWORD" | base64 -w0)"
		BASIC_AUTH_ARGS=(--user "${BASIC_USER}:${BASIC_PASSWORD}")
	fi
}


check_uuid() {
	if [[ ${1//-/} =~ ^[[:xdigit:]]{32}$ ]]; then
		echo "[+] token format validated"
	else
		echo "[-] token is not a UUID"
		exit 1
	fi
}

# Wrapper for all curl calls with Basic Auth, API Key, Deptrack URL and options
deptrack_curl() {
	# takes out path as the first argument
	local path="$1"; shift
	# wrapper to exit script and show error in failure
	curl ${INSECURE:+--insecure} ${VERBOSE:+--verbose} --silent --fail --show-error \
		"${BASIC_AUTH_ARGS[@]}" \
		--header "X-Api-Key: $DTRACK_KEY" \
		"$@" \
		"${DTRACK_URL%/}${path}"
}

# Polls Deptrack until 
deptrack_wait_tokens() {
	echo "[*] Checking BoM processing status"
	local token="$1"
	local c=0
	local processing=$(deptrack_curl "/api/v1/bom/token/$token" --request GET | jq '.processing')

	while [ "$processing" != "false" ]; do
		sleep 10
		processing=$(deptrack_curl "/api/v1/bom/token/$token" --request GET | jq '.processing')
		c=$((c + 1))
		if [ "$c" -eq "$DEPTRACK_RETRIES_TIMEOUT" ]; then
			echo "[-]  Timeout while waiting for processing result. Please check the OWASP Dependency Track status."
			exit 1
		fi
	done
}


# deptrack_lookup() {

# }
# deptrack_markdown_row() {

# }
