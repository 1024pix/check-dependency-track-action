#!/bin/bash
set -euo pipefail

# shellcheck source=scripts/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

deptrack_init

# Parse $PROJECTS_JSON
jq -e . >/dev/null <<<"$PROJECTS_JSON" || { echo "[-] projects: invalid JSON"; exit 1; }
mapfile -t tokens < <(printf '%s\n' "$PROJECTS_JSON" | jq -r 'select(. != null) | .token')
(( ${#tokens[@]} > 0 )) || { echo "[-] No project to fetch"; exit 1; }

# Poll for projects
deptrack_wait_tokens "${tokens[@]}"

# from previous versions : wait to make sure the score is available, 
# some errors found during tests w/o this wait
sleep 10

# Fetch results
mapfile -t lines_json <<<"$PROJECTS_JSON"
RESULTS=()
RESULTS_TABLE=()
GLOBAL_STATUS=pass

for line in "${lines_json[@]}"; do
	[[ "$line" =~ [^[:space:]] ]] || continue
	name=$(jq -r '.name' <<<"$line")
	version=$(jq -r '.version' <<<"$line")
	project_result=$(deptrack_curl "/api/v1/project/lookup" --get \
		--data-urlencode "name=$name" \
		--data-urlencode "version=$version")

	project_status=$(compile_project_status "$project_result")

	# computes global status as max of the status
	if   [[ "$project_status" == "fail" || "$GLOBAL_STATUS" == "fail" ]]; then 
		GLOBAL_STATUS=fail
	elif [[ "$project_status" == "warn" ]]; then 
		GLOBAL_STATUS=warn
	fi

	project_risk_score=$(jq '.lastInheritedRiskScore // null' <<<"$project_result")

	RESULTS+=("$(jq -nc --arg name "$name" --arg version "$version" \
		--argjson risk_score "$project_risk_score" --arg status "$project_status" \
		'{name:$name, version:$version, risk_score:$risk_score, status:$status}')")
	RESULTS_TABLE+=("$(jq --arg name "$name" --arg risk_score "$project_risk_score" --arg status "$project_status" -r '.metrics | "| \($name) | \($status) | \(.critical // 0) | \(.high // 0) | \(.medium // 0) | \(.low // 0) | \($risk_score) |"' <<<"$project_result")")
done

# Global output
RESULTS_MARKDOWN=$(
	echo "### Dependency-Track: ${GLOBAL_STATUS} (last run : $(date +"%Y-%m-%d %H:%M:%S"))"
	echo "| Project | Status | Critical | High | Medium | Low | Risk score |"
	echo "|---|---|---|---|---|---|---|"
	printf '%s\n' "${RESULTS_TABLE[@]}"
	echo "> Le statut (pass/warn/fail) dépend des policies actives sur la plateforme pour chaque repo"
)

delim="EOF_$(openssl rand -hex 16)"
{
	echo "status=$GLOBAL_STATUS"
	echo "results=$(printf '%s\n' "${RESULTS[@]}" | jq -sc .)"
	echo "markdown<<$delim"
	printf '%s\n' "$RESULTS_MARKDOWN"
	echo "$delim"
} >> "$GITHUB_OUTPUT"

printf '%s\n' "$RESULTS_MARKDOWN" >> "$GITHUB_STEP_SUMMARY"
