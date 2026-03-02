#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------
# MCPhound CI Scanner
# Posts an MCP config to the MCPhound API and saves the SARIF result.
# ------------------------------------------------------------------

# ── Fork detection ────────────────────────────────────────────────
if [[ "${GITHUB_EVENT_NAME:-}" == "pull_request" ]]; then
  head_repo=$(jq -r '.pull_request.head.repo.full_name // empty' "$GITHUB_EVENT_PATH")
  base_repo=$(jq -r '.pull_request.base.repo.full_name // empty' "$GITHUB_EVENT_PATH")
  if [[ -n "$head_repo" && -n "$base_repo" && "$head_repo" != "$base_repo" ]]; then
    echo "::notice::Skipping MCPhound scan: fork PR (${head_repo} → ${base_repo}). Secrets are not available in fork PRs."
    exit 0
  fi
fi

# ── Token check ───────────────────────────────────────────────────
if [[ -z "${INPUT_API_TOKEN:-}" ]]; then
  echo "::error::MCPHOUND_API_TOKEN required. Add as a repository secret and pass via api_token input."
  exit 1
fi

# ── Locate config file ───────────────────────────────────────────
config_path="${INPUT_CONFIG_PATH:-.cursor/mcp.json}"

if [[ ! -f "$config_path" ]]; then
  # Try common fallback locations
  for fallback in ".vscode/mcp.json" ".cursor/mcp.json"; do
    if [[ -f "$fallback" ]]; then
      echo "::notice::Config not found at ${config_path}, using fallback: ${fallback}"
      config_path="$fallback"
      break
    fi
  done
fi

if [[ ! -f "$config_path" ]]; then
  echo "::error::MCP config file not found at ${config_path} (also checked .vscode/mcp.json, .cursor/mcp.json)"
  exit 1
fi

echo "Using MCP config: ${config_path}"
config_content=$(cat "$config_path")

# ── Validate JSON ────────────────────────────────────────────────
if ! echo "$config_content" | jq empty 2>/dev/null; then
  echo "::error::MCP config file is not valid JSON: ${config_path}"
  exit 1
fi

# ── API call with retry ──────────────────────────────────────────
api_url="${INPUT_API_URL:-https://mcphound-api.fly.dev}"
endpoint="${api_url}/api/v1/ci/analyze"
timeout="${INPUT_TIMEOUT_SECONDS:-120}"
sarif_output="${RUNNER_TEMP:-/tmp}/mcphound.sarif"

max_attempts=3
attempt=0
backoff=2

while (( attempt < max_attempts )); do
  attempt=$((attempt + 1))
  http_code=""
  response=""

  echo "Attempt ${attempt}/${max_attempts}: POST ${endpoint}"

  # Use a temp file for the response body so we can capture the HTTP code
  response_file=$(mktemp)
  http_code=$(curl -s -o "$response_file" -w "%{http_code}" \
    --max-time "$timeout" \
    -X POST "$endpoint" \
    -H "Authorization: Bearer ${INPUT_API_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$config_content" \
  ) || {
    echo "::warning::Network error on attempt ${attempt}"
    rm -f "$response_file"
    if (( attempt < max_attempts )); then
      echo "Retrying in ${backoff}s..."
      sleep "$backoff"
      backoff=$((backoff * 2))
      continue
    fi
    echo "::error::MCPhound API unreachable after ${max_attempts} attempts"
    exit 1
  }

  response=$(cat "$response_file")
  rm -f "$response_file"

  # Success
  if [[ "$http_code" =~ ^2 ]]; then
    break
  fi

  # Client error — do not retry
  if [[ "$http_code" =~ ^4 ]]; then
    echo "::error::MCPhound API returned HTTP ${http_code}"
    echo "$response" | head -c 500
    exit 1
  fi

  # Server error — retry
  echo "::warning::MCPhound API returned HTTP ${http_code} on attempt ${attempt}"
  if (( attempt < max_attempts )); then
    echo "Retrying in ${backoff}s..."
    sleep "$backoff"
    backoff=$((backoff * 2))
  else
    echo "::error::MCPhound API returned HTTP ${http_code} after ${max_attempts} attempts"
    echo "$response" | head -c 500
    exit 1
  fi
done

# ── Extract SARIF from JSend wrapper ─────────────────────────────
# API returns {"status": "success", "data": <sarif>}
sarif=$(echo "$response" | jq '.data // empty')
if [[ -z "$sarif" || "$sarif" == "null" ]]; then
  echo "::error::MCPhound API response missing SARIF data"
  echo "$response" | head -c 500
  exit 1
fi

echo "$sarif" > "$sarif_output"
echo "SARIF saved to ${sarif_output}"

# ── Parse results ────────────────────────────────────────────────
findings_count=$(echo "$sarif" | jq '[.runs[]?.results[]?] | length')
max_severity="none"

# SARIF uses "error", "warning", "note" levels
sarif_max=$(echo "$sarif" | jq -r '
  [.runs[]?.results[]?.level // empty] |
  if any(. == "error") then "error"
  elif any(. == "warning") then "warning"
  elif any(. == "note") then "note"
  else "none"
  end
')

# Map SARIF levels to MCPhound severity names
case "${sarif_max}" in
  error)   max_severity="critical" ;;
  warning) max_severity="medium" ;;
  note)    max_severity="low" ;;
  *)       max_severity="none" ;;
esac

echo "Findings: ${findings_count}, Max severity: ${max_severity}"

# ── Write outputs ────────────────────────────────────────────────
{
  echo "sarif_file=${sarif_output}"
  echo "findings_count=${findings_count}"
  echo "max_severity=${max_severity}"
} >> "$GITHUB_OUTPUT"
