#!/usr/bin/env bash
# posta-api.sh — Bash helper for Posta API interactions
# Source this file: source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

set -euo pipefail

POSTA_BASE_URL="${POSTA_BASE_URL:-https://api.getposta.app/v1}"
POSTA_TOKEN_FILE="/tmp/.posta_token"

STATAPP_BASE_URL="${STATAPP_URL:-}"
STATAPP_TOKEN_FILE="/tmp/.statapp_token"
STATAPP_DEVICE_ID="${STATAPP_DEVICE_ID:-claude-plugin-$(whoami)}"

# ─── JSON Parsing Helper ─────────────────────────────────────────────────────

# Resolve script directory (works in both bash and zsh)
POSTA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd 2>/dev/null)" || \
POSTA_SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd 2>/dev/null)" || \
POSTA_SCRIPT_DIR="/Users/stefangimeson/.claude/plugins/cache/posta-plugins/posta-skill/1.0.0/skills/posta/scripts"

posta_sanitize_json() {
  # Sanitize a JSON API response so jq can parse it.
  # Reads from a file path (arg 1) to avoid bash argument length limits on large responses.
  # Python parses with strict=False to handle literal control chars in captions,
  # then re-serializes as clean JSON.
  local tmpfile="$1"
  python3 "${POSTA_SCRIPT_DIR}/sanitize_json.py" "$tmpfile" 2>/dev/null || cat "$tmpfile"
}

# ─── Credentials Discovery ───────────────────────────────────────────────────

posta_discover_credentials() {
  # Only run discovery once per session
  if [[ "${_POSTA_CREDS_DISCOVERED:-}" == "1" ]]; then
    return 0
  fi
  export _POSTA_CREDS_DISCOVERED=1

  # If API token already set, skip password discovery
  if [[ -n "${POSTA_API_TOKEN:-}" ]]; then
    return 0
  fi

  # Skip if already set
  if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
    return 0
  fi

  local source_found=""

  # Helper: extract a var value from a file (safe under pipefail)
  _posta_extract_var() {
    local varname="$1" file="$2"
    grep -E "^(export )?${varname}=" "$file" 2>/dev/null | tail -1 | sed "s/^export //" | sed "s/^${varname}=//" | tr -d '"' | tr -d "'" || true
  }

  # Discover POSTA_API_TOKEN from common locations (check before email/password)
  if [[ -z "${POSTA_API_TOKEN:-}" ]]; then
    for src in "$HOME/.posta/credentials" "$HOME/.zshrc" "$HOME/.bashrc" .env .env.local .env.production; do
      if [[ -f "$src" ]]; then
        local val
        val=$(_posta_extract_var POSTA_API_TOKEN "$src")
        if [[ -n "$val" ]]; then
          export POSTA_API_TOKEN="$val"
          echo "INFO: Posta API token loaded from ${src}" >&2
          return 0
        fi
      fi
    done
  fi

  # 1. Check shell profiles (~/.zshrc, ~/.bashrc)
  for profile in "$HOME/.zshrc" "$HOME/.bashrc"; do
    if [[ -f "$profile" ]]; then
      local val
      val=$(_posta_extract_var POSTA_EMAIL "$profile")
      if [[ -n "$val" && -z "${POSTA_EMAIL:-}" ]]; then
        export POSTA_EMAIL="$val"
      fi
      val=$(_posta_extract_var POSTA_PASSWORD "$profile")
      if [[ -n "$val" && -z "${POSTA_PASSWORD:-}" ]]; then
        export POSTA_PASSWORD="$val"
      fi
      if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
        source_found="$profile"
        break
      fi
    fi
  done

  # 2. Check .env files in CWD
  if [[ -z "${POSTA_EMAIL:-}" || -z "${POSTA_PASSWORD:-}" ]]; then
    for envfile in .env .env.local .env.production; do
      if [[ -f "$envfile" ]]; then
        local val
        val=$(_posta_extract_var POSTA_EMAIL "$envfile")
        if [[ -n "$val" && -z "${POSTA_EMAIL:-}" ]]; then
          export POSTA_EMAIL="$val"
        fi
        val=$(_posta_extract_var POSTA_PASSWORD "$envfile")
        if [[ -n "$val" && -z "${POSTA_PASSWORD:-}" ]]; then
          export POSTA_PASSWORD="$val"
        fi
        if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
          source_found="$envfile"
          break
        fi
      fi
    done
  fi

  # 3. Check dedicated credentials file
  if [[ -z "${POSTA_EMAIL:-}" || -z "${POSTA_PASSWORD:-}" ]]; then
    local creds_file="$HOME/.posta/credentials"
    if [[ -f "$creds_file" ]]; then
      local val
      val=$(_posta_extract_var POSTA_EMAIL "$creds_file")
      if [[ -n "$val" && -z "${POSTA_EMAIL:-}" ]]; then
        export POSTA_EMAIL="$val"
      fi
      val=$(_posta_extract_var POSTA_PASSWORD "$creds_file")
      if [[ -n "$val" && -z "${POSTA_PASSWORD:-}" ]]; then
        export POSTA_PASSWORD="$val"
      fi
      if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
        source_found="$creds_file"
      fi
    fi
  fi

  # Also discover FIREWORKS_API_KEY if missing
  if [[ -z "${FIREWORKS_API_KEY:-}" ]]; then
    for src in "$HOME/.zshrc" "$HOME/.bashrc" .env .env.local .env.development .env.production "$HOME/.posta/credentials"; do
      if [[ -f "$src" ]]; then
        local val
        val=$(_posta_extract_var FIREWORKS_API_KEY "$src")
        if [[ -n "$val" ]]; then
          export FIREWORKS_API_KEY="$val"
          break
        fi
      fi
    done
  fi

  if [[ -n "$source_found" ]]; then
    echo "INFO: Posta credentials loaded from ${source_found}" >&2
  fi
}

# ─── Authentication ───────────────────────────────────────────────────────────

posta_login() {
  if [[ -z "${POSTA_EMAIL:-}" || -z "${POSTA_PASSWORD:-}" ]]; then
    echo "ERROR: POSTA_EMAIL and POSTA_PASSWORD must be set" >&2
    echo "Searched: env vars, ~/.zshrc, ~/.bashrc, .env files, ~/.posta/credentials" >&2
    return 1
  fi

  local response
  response=$(curl -sf -X POST "${POSTA_BASE_URL}/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"${POSTA_EMAIL}\", \"password\": \"${POSTA_PASSWORD}\"}")

  local token
  token=$(echo "$response" | jq -r '.access_token // .accessToken // empty')

  if [[ -z "$token" ]]; then
    echo "ERROR: Login failed — no token in response" >&2
    echo "$response" >&2
    return 1
  fi

  echo "$token" > "$POSTA_TOKEN_FILE"
  echo "$token"
}

posta_get_token() {
  # If POSTA_API_TOKEN is set, use it directly (no login needed)
  if [[ -n "${POSTA_API_TOKEN:-}" ]]; then
    printf '%s' "$POSTA_API_TOKEN"
    return 0
  fi

  # Return cached token if it exists and is non-empty
  if [[ -f "$POSTA_TOKEN_FILE" ]]; then
    local token
    token=$(cat "$POSTA_TOKEN_FILE")
    if [[ -n "$token" ]]; then
      printf '%s' "$token"
      return 0
    fi
  fi

  # Otherwise login
  posta_login
}

# ─── Generic API call ─────────────────────────────────────────────────────────

posta_api() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"
  local token
  local tmpfile="/tmp/.posta_response_$$"

  token=$(posta_get_token)

  local args=(
    -s
    -X "$method"
    -H "Authorization: Bearer ${token}"
    -H "Content-Type: application/json"
    -o "$tmpfile"
    -w "%{http_code}"
  )

  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi

  local http_code
  http_code=$(curl "${args[@]}" "${POSTA_BASE_URL}${endpoint}")

  # If 401, handle based on token type
  if [[ "$http_code" == "401" ]]; then
    if [[ -n "${POSTA_API_TOKEN:-}" ]]; then
      echo "ERROR: API token is invalid or revoked. Generate a new one at your Posta dashboard." >&2
      rm -f "$tmpfile"
      return 1
    fi
    # JWT flow: re-login and retry once
    rm -f "$POSTA_TOKEN_FILE"
    token=$(posta_login)
    args[6]="Authorization: Bearer ${token}"

    http_code=$(curl "${args[@]}" "${POSTA_BASE_URL}${endpoint}")
  fi

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: API returned HTTP ${http_code}" >&2
    cat "$tmpfile" >&2
    rm -f "$tmpfile"
    return 1
  fi

  # Sanitize control characters that break jq, output to stdout.
  # Also saved to /tmp/.posta_last_response for safe access when callers
  # need to avoid bash echo corrupting \n in JSON strings.
  # Use: posta_api ... | jq    (pipe, always safe)
  # Or:  posta_api ... > /dev/null; jq ... /tmp/.posta_last_response
  posta_sanitize_json "$tmpfile" > /tmp/.posta_last_response
  cat /tmp/.posta_last_response
  rm -f "$tmpfile"
}

# ─── Media Upload (3-step signed URL flow) ────────────────────────────────────

posta_upload_media() {
  local filepath="$1"
  local mime_type="$2"
  local filename
  filename=$(basename "$filepath")
  local size_bytes
  size_bytes=$(stat -f%z "$filepath" 2>/dev/null || stat -c%s "$filepath" 2>/dev/null)

  # Step 1: Create upload URL
  local create_response
  create_response=$(posta_api POST "/media/create-upload-url" \
    "{\"name\": \"${filename}\", \"mime_type\": \"${mime_type}\", \"size_bytes\": ${size_bytes}}")

  local media_id upload_url
  media_id=$(echo "$create_response" | jq -r '.media_id')
  upload_url=$(echo "$create_response" | jq -r '.upload_url')

  if [[ -z "$media_id" || "$media_id" == "null" ]]; then
    echo "ERROR: Failed to create upload URL" >&2
    echo "$create_response" >&2
    return 1
  fi

  # Step 2: PUT binary to signed GCS URL
  local upload_status
  upload_status=$(curl -sf -o /dev/null -w "%{http_code}" \
    -X PUT \
    -H "Content-Type: ${mime_type}" \
    --data-binary "@${filepath}" \
    "$upload_url")

  if [[ "$upload_status" -ge 400 ]]; then
    echo "ERROR: Upload to storage failed with HTTP ${upload_status}" >&2
    return 1
  fi

  # Step 3: Confirm upload
  local confirm_response
  confirm_response=$(posta_api POST "/media/${media_id}/confirm-upload")

  echo "$confirm_response" | jq -r '.media.id // .media_id // empty'
  return 0
}

posta_upload_from_url() {
  local url="$1"
  local mime_type="$2"
  local filename="${3:-downloaded_media}"

  # Determine extension from mime type
  local ext=""
  case "$mime_type" in
    image/png)  ext=".png" ;;
    image/jpeg) ext=".jpg" ;;
    image/webp) ext=".webp" ;;
    video/mp4)  ext=".mp4" ;;
    *)          ext="" ;;
  esac

  local tmpfile="/tmp/posta_upload_${RANDOM}${ext}"

  # Download file
  curl -sf -o "$tmpfile" "$url"

  if [[ ! -f "$tmpfile" || ! -s "$tmpfile" ]]; then
    echo "ERROR: Failed to download from ${url}" >&2
    rm -f "$tmpfile"
    return 1
  fi

  # Upload via standard flow
  local result
  result=$(posta_upload_media "$tmpfile" "$mime_type")

  rm -f "$tmpfile"
  echo "$result"
}

# ─── Convenience wrappers ─────────────────────────────────────────────────────

posta_list_accounts() {
  # API wraps accounts in { accounts: [...] } — unwrap to plain array
  posta_api GET "/social-accounts" | jq '.accounts // .'
}

posta_list_posts() {
  # Usage: posta_list_posts [post_status] [limit] [offset]
  # post_status: scheduled, posted, draft, failed, cancelled (optional — omit or pass "" for all)
  local post_status="${1:-}"
  local limit="${2:-20}"
  local offset="${3:-0}"
  local query="limit=${limit}&offset=${offset}"
  if [[ -n "$post_status" ]]; then
    query="${query}&status=${post_status}"
  fi
  posta_api GET "/posts?${query}"
}

posta_create_post() {
  local body="$1"
  posta_api POST "/posts" "$body"
}

posta_schedule_post() {
  local post_id="$1"
  local scheduled_at="$2"
  posta_api POST "/posts/${post_id}/schedule" "{\"scheduledAt\": \"${scheduled_at}\"}"
}

posta_publish_post() {
  local post_id="$1"
  posta_api POST "/posts/${post_id}/publish"
}

posta_get_analytics_overview() {
  local period="${1:-30d}"
  posta_api GET "/analytics/overview?period=${period}"
}

posta_get_best_times() {
  posta_api GET "/analytics/best-times"
}

posta_get_plan() {
  posta_api GET "/users/plan"
}

posta_get_post() {
  local post_id="$1"
  posta_api GET "/posts/${post_id}"
}

posta_update_post() {
  local post_id="$1"
  local body="$2"
  posta_api PATCH "/posts/${post_id}" "$body"
}

posta_delete_post() {
  local post_id="$1"
  posta_api DELETE "/posts/${post_id}"
}

posta_cancel_post() {
  local post_id="$1"
  posta_api POST "/posts/${post_id}/cancel"
}

posta_get_media() {
  local media_id="$1"
  posta_api GET "/media/${media_id}"
}

# ─── Multiline Caption Helper ────────────────────────────────────────────────

posta_create_post_from_file() {
  # Creates a post using a caption from a file — handles multiline text safely
  local caption_file="$1"
  local media_ids_json="${2:-[]}"
  local account_ids_json="$3"
  local is_draft="${4:-true}"
  local hashtags_json="${5:-[]}"

  local payload
  payload=$(jq -n \
    --arg caption "$(cat "$caption_file")" \
    --argjson mediaIds "$media_ids_json" \
    --argjson accountIds "$account_ids_json" \
    --argjson isDraft "$is_draft" \
    --argjson hashtags "$hashtags_json" \
    '{caption: $caption, mediaIds: $mediaIds, socialAccountIds: $accountIds, isDraft: $isDraft, hashtags: $hashtags}')

  posta_api POST "/posts" "$payload"
}

# ─── Fireworks API Key Validation ────────────────────────────────────────────

fireworks_validate_key() {
  # Discover key if not set
  posta_discover_credentials

  if [[ -z "${FIREWORKS_API_KEY:-}" ]]; then
    echo "ERROR: FIREWORKS_API_KEY is not set." >&2
    echo "Set it as an env var, in .env.development, ~/.zshrc, or ~/.posta/credentials" >&2
    return 1
  fi

  # Lightweight test: list models (small request)
  local http_code
  http_code=$(curl -sf -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
    "https://api.fireworks.ai/inference/v1/models" 2>/dev/null)

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Fireworks API key is invalid (HTTP ${http_code}). Keys start with 'fw_'." >&2
    echo "Get a key at https://fireworks.ai/account/api-keys" >&2
    return 1
  fi

  echo "OK: Fireworks API key is valid" >&2
  return 0
}

# ─── Statapp (Stupid Correlations) ────────────────────────────────────────────

statapp_login() {
  if [[ -z "${STATAPP_BASE_URL:-}" ]]; then
    echo "ERROR: STATAPP_URL must be set" >&2
    return 1
  fi
  if [[ -z "${STATAPP_EMAIL:-}" || -z "${STATAPP_PASSWORD:-}" ]]; then
    echo "ERROR: STATAPP_EMAIL and STATAPP_PASSWORD must be set" >&2
    return 1
  fi

  local response
  response=$(curl -sf -X POST "${STATAPP_BASE_URL}/api/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"email\": \"${STATAPP_EMAIL}\", \"password\": \"${STATAPP_PASSWORD}\"}")

  local token
  token=$(echo "$response" | jq -r '.token // .access_token // .idToken // empty')

  if [[ -z "$token" ]]; then
    echo "ERROR: Statapp login failed — no token in response" >&2
    echo "$response" >&2
    return 1
  fi

  echo "$token" > "$STATAPP_TOKEN_FILE"
  echo "$token"
}

statapp_get_token() {
  if [[ -f "$STATAPP_TOKEN_FILE" ]]; then
    local token
    token=$(cat "$STATAPP_TOKEN_FILE")
    if [[ -n "$token" ]]; then
      echo "$token"
      return 0
    fi
  fi

  statapp_login
}

statapp_api() {
  local method="$1"
  local endpoint="$2"
  local body="${3:-}"

  if [[ -z "${STATAPP_BASE_URL:-}" ]]; then
    echo "ERROR: STATAPP_URL must be set" >&2
    return 1
  fi

  local token
  token=$(statapp_get_token)

  local args=(
    -sf
    -X "$method"
    -H "Authorization: Bearer ${token}"
    -H "X-Device-Id: ${STATAPP_DEVICE_ID}"
    -H "Content-Type: application/json"
  )

  if [[ -n "$body" ]]; then
    args+=(-d "$body")
  fi

  local response http_code
  response=$(curl -w "\n%{http_code}" "${args[@]}" "${STATAPP_BASE_URL}${endpoint}")
  http_code=$(echo "$response" | tail -1)
  response=$(echo "$response" | sed '$d')

  # If 401, re-login and retry once
  if [[ "$http_code" == "401" ]]; then
    rm -f "$STATAPP_TOKEN_FILE"
    token=$(statapp_login)
    args[4]="Authorization: Bearer ${token}"

    response=$(curl -w "\n%{http_code}" "${args[@]}" "${STATAPP_BASE_URL}${endpoint}")
    http_code=$(echo "$response" | tail -1)
    response=$(echo "$response" | sed '$d')
  fi

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: Statapp API returned HTTP ${http_code}" >&2
    echo "$response" >&2
    return 1
  fi

  echo "$response"
}

statapp_generate_random() {
  local aspect_ratio="${1:-square}"
  local chart_style="${2:-classic}"
  local include_video="${3:-false}"
  statapp_api POST "/api/generate/random" \
    "{\"aspectRatio\": \"${aspect_ratio}\", \"chartStyle\": \"${chart_style}\", \"includeVideo\": ${include_video}}"
}

statapp_animate() {
  local body="$1"
  statapp_api POST "/api/generate/animate" "$body"
}

statapp_animate_status() {
  local job_id="$1"
  local wait="${2:-true}"
  statapp_api GET "/api/generate/animate/status/${job_id}?wait=${wait}"
}

statapp_get_styles() {
  statapp_api GET "/api/generate/styles"
}

# ─── Auto-discover credentials on source ────────────────────────────────────
posta_discover_credentials
