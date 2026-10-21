#!/usr/bin/env bash
set -euo pipefail

: "${CODACY_API_TOKEN:?CODACY_API_TOKEN is required}"
: "${ORGANIZATION:?ORGANIZATION is required}"
: "${REPOSITORY:?REPOSITORY is required}"
: "${MIN_COVERAGE:?MIN_COVERAGE is required}"

PROVIDER="${PROVIDER:-gh}"
FAIL_IF_NO_REPORT="${FAIL_IF_NO_REPORT:-true}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
RETRY_DELAY_SECONDS="${RETRY_DELAY_SECONDS:-15}"

commit_sha="${COMMIT_SHA:-}"

if [[ -z "$commit_sha" && -n "${GITHUB_EVENT_PATH:-}" && -f "${GITHUB_EVENT_PATH:-}" ]]; then
  commit_sha=$(jq -r '.pull_request.head.sha // empty' "$GITHUB_EVENT_PATH")
fi

if [[ -z "$commit_sha" ]]; then
  commit_sha="${GITHUB_SHA:-}"
fi

if [[ -z "$commit_sha" ]]; then
  echo "::error::Could not determine a commit SHA to check (no commit-sha input, no pull_request.head.sha, no GITHUB_SHA)." >&2
  exit 1
fi

echo "Checking overall Codacy coverage for ${PROVIDER}/${ORGANIZATION}/${REPOSITORY}@${commit_sha}"

url="https://api.codacy.com/api/v3/analysis/organizations/${PROVIDER}/${ORGANIZATION}/repositories/${REPOSITORY}/commits/${commit_sha}"

coverage=""
attempt=1

while (( attempt <= MAX_ATTEMPTS )); do
  response=$(curl -sS -w '\n%{http_code}' -H "api-token: ${CODACY_API_TOKEN}" "$url")
  http_code=$(tail -n1 <<< "$response")
  body=$(sed '$d' <<< "$response")

  if [[ "$http_code" == "404" ]]; then
    coverage=""
  elif [[ "$http_code" != "200" ]]; then
    echo "::error::Codacy API returned HTTP ${http_code}: ${body}" >&2
    exit 1
  else
    coverage=$(echo "$body" | jq -r '.coverage.totalCoveragePercentage // empty')
  fi

  if [[ -n "$coverage" ]]; then
    break
  fi

  echo "No coverage report processed yet by Codacy for ${commit_sha} (attempt ${attempt}/${MAX_ATTEMPTS})."
  if (( attempt < MAX_ATTEMPTS )); then
    sleep "$RETRY_DELAY_SECONDS"
  fi
  attempt=$((attempt + 1))
done

if [[ -z "$coverage" ]]; then
  if [[ "$FAIL_IF_NO_REPORT" == "true" ]]; then
    echo "::error::No coverage report has been processed by Codacy for commit ${commit_sha} after ${MAX_ATTEMPTS} attempts." >&2
    exit 1
  fi
  echo "No coverage report available; skipping the overall coverage gate (fail-if-no-report=false)."
  exit 0
fi

echo "coverage=${coverage}" >> "$GITHUB_OUTPUT"
echo "Overall repository coverage: ${coverage}% (minimum required: ${MIN_COVERAGE}%)"

passed=$(awk -v c="$coverage" -v m="$MIN_COVERAGE" 'BEGIN { print (c + 0 >= m + 0) ? "1" : "0" }')

if [[ "$passed" != "1" ]]; then
  echo "::error::Overall coverage ${coverage}% is below the required minimum of ${MIN_COVERAGE}%." >&2
  exit 1
fi

echo "Overall coverage check passed."
