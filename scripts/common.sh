# shellcheck shell=bash

DEPTRACK_RETRIES_TIMEOUT=30
# VERBOSE="--verbose"
# INSECURE="--insecure"

deptrack_init() {
	# checks
	[[ -z "${DTRACK_URL:-}" ]] && { echo "[-] DTRACK_URL not set"; exit 1; }
	[[ -z "${DTRACK_KEY:-}" ]] && { echo "[-] DTRACK_KEY not set"; exit 1; }

	# register in Github runner the API KEY as a secret -> it will not be echoed in the logs
	echo "::add-mask::$DTRACK_KEY" 

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

compute_project_name() {
	local directory_name_clean
	local project_name
	directory_name_clean=$(echo "${DIRECTORY:-.}" | sed -e 's#^\(\./\)*##' -e 's#/*$##')
	if [ -z "$directory_name_clean" ] || [ "$directory_name_clean" = "." ]; then
		project_name="$GITHUB_REPOSITORY"
	else
		project_name="$GITHUB_REPOSITORY/$directory_name_clean"
	fi
	echo "$project_name"
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

# Polls Deptrack for a list of UUIDs during $DEPTRACK_RETRIES_TIMEOUT x 10s
deptrack_wait_tokens() {
	(( $# > 0 )) || { echo "[-] deptrack_wait_tokens: no token"; exit 1; }
	local pending=("$@") 
	local remaining_tokens token processing

	# loop over the tokens to validate their format
	for token in "${pending[@]}"; do check_uuid "$token"; done

	echo "[*] Waiting for ${#pending[@]} BoM(s) to be processed"
	local count=0

	while true; do
		sleep 10
		remaining_tokens=()
		# loop over all tokens
		for token in  "${pending[@]}"; do
			processing=$(deptrack_curl "/api/v1/bom/token/$token" --request GET \
				| jq '.processing')
			[[ "$processing" == "false" ]] || remaining_tokens+=("$token")
		done
		# if remaining_tokens is not null, continue to loop
		(( ${#remaining_tokens[@]} == 0 )) && break
		pending=("${remaining_tokens[@]}")
		
		count=$((count + 1))
		if [ "$count" -eq "$DEPTRACK_RETRIES_TIMEOUT" ]; then
			echo "[-]  Timeout while waiting for processing result. ${#pending[@]} BoM(s) still processing Please check the OWASP Dependency Track status."
			exit 1
		fi
	done
}

# returns a status value based on policies (pass/warn/fail)
compile_project_status() {
	local PROJECT_ANALYSIS=$1
	local fail warn
	fail=$(jq -r '.metrics.policyViolationsFail // 0' <<<"$PROJECT_ANALYSIS")
	warn=$(jq -r '.metrics.policyViolationsWarn // 0' <<<"$PROJECT_ANALYSIS")
	if   (( fail > 0 )); then echo "fail"
	elif (( warn > 0 )); then echo "warn"
	else echo "pass"; fi
}

# deptrack_markdown_row() {

# }
