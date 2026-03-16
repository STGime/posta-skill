#!/usr/bin/env bash
# posta-api.sh — Bash helper for Posta API interactions
# Source this file from your AI assistant skill:
#   source "${POSTA_SKILL_ROOT:-${OPENCLAW_SKILL_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}/skills/posta/scripts/posta-api.sh"
#
# The three root variables above are set by different AI assistant platforms
# to point to the skill's install directory. This is standard path resolution,
# not environment/sandbox detection. See SECURITY.md for details.

set -euo pipefail

POSTA_BASE_URL="${POSTA_BASE_URL:-https://api.getposta.app/v1}"
POSTA_TOKEN_FILE="/tmp/.posta_token"

# ─── JSON Parsing Helper ─────────────────────────────────────────────────────

# Resolve script directory (works in both bash and zsh)
POSTA_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" && pwd 2>/dev/null)" || \
POSTA_SCRIPT_DIR="$(cd "$(dirname "${0}")" && pwd 2>/dev/null)" || \
POSTA_SCRIPT_DIR="$(pwd)/skills/posta/scripts"

posta_sanitize_json() {
  # Sanitize a JSON API response so jq can parse it.
  # Reads from a file path (arg 1) to avoid bash argument length limits on large responses.
  # Python parses with strict=False to handle literal control chars in captions,
  # then re-serializes as clean JSON.
  local tmpfile="$1"
  python3 "${POSTA_SCRIPT_DIR}/sanitize_json.py" "$tmpfile" 2>/dev/null || cat "$tmpfile"
}

# ─── Credentials Discovery ───────────────────────────────────────────────────
# Reads POSTA_API_TOKEN (or legacy email/password) from a fixed list of files
# where users are instructed to store their credentials. See SECURITY.md for
# a full explanation of why each location is checked and what data is read.

# Fixed, auditable list of files the skill will ever read for credentials.
# Only dedicated config files are checked — shell profiles are NOT read.
_POSTA_CREDENTIAL_SOURCES=(
  "$HOME/.posta/credentials"   # dedicated Posta config (preferred)
  ".env"                       # project dotenv
  ".env.local"                 # project dotenv (local override)
  ".env.production"            # project dotenv (production)
)

# Exact variable names the skill will search for — nothing else is read.
# POSTA_API_TOKEN, POSTA_EMAIL, POSTA_PASSWORD, FIREWORKS_API_KEY

posta_discover_credentials() {
  # Only run discovery once per session
  if [[ "${_POSTA_CREDS_DISCOVERED:-}" == "1" ]]; then
    return 0
  fi
  export _POSTA_CREDS_DISCOVERED=1

  # If API token already set, skip all file reads
  if [[ -n "${POSTA_API_TOKEN:-}" ]]; then
    return 0
  fi

  # Skip if legacy creds already set
  if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
    return 0
  fi

  local source_found=""

  # Helper: extract a single named variable from a file.
  # Uses exact-match grep for the variable name — never reads arbitrary content.
  _posta_extract_var() {
    local varname="$1" file="$2"
    grep -E "^(export )?${varname}=" "$file" 2>/dev/null | tail -1 | sed "s/^export //" | sed "s/^${varname}=//" | tr -d '"' | tr -d "'" || true
  }

  # 1. Look for POSTA_API_TOKEN (preferred auth method)
  for src in "${_POSTA_CREDENTIAL_SOURCES[@]}"; do
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

  # 2. Fall back to legacy email/password
  for src in "${_POSTA_CREDENTIAL_SOURCES[@]}"; do
    if [[ -f "$src" ]]; then
      local val
      val=$(_posta_extract_var POSTA_EMAIL "$src")
      if [[ -n "$val" && -z "${POSTA_EMAIL:-}" ]]; then
        export POSTA_EMAIL="$val"
      fi
      val=$(_posta_extract_var POSTA_PASSWORD "$src")
      if [[ -n "$val" && -z "${POSTA_PASSWORD:-}" ]]; then
        export POSTA_PASSWORD="$val"
      fi
      if [[ -n "${POSTA_EMAIL:-}" && -n "${POSTA_PASSWORD:-}" ]]; then
        source_found="$src"
        break
      fi
    fi
  done

  # 3. Discover FIREWORKS_API_KEY for AI image generation (optional)
  if [[ -z "${FIREWORKS_API_KEY:-}" ]]; then
    for src in "${_POSTA_CREDENTIAL_SOURCES[@]}"; do
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

# ─── MIME Type Detection ─────────────────────────────────────────────────────

posta_detect_mime() {
  # Auto-detect MIME type from a file path using the `file` command.
  # Falls back to extension-based detection if `file` is unavailable.
  local filepath="$1"
  local detected=""

  # Try system `file` command first (available on macOS and Linux)
  if command -v file &>/dev/null; then
    detected=$(file --mime-type -b "$filepath" 2>/dev/null)
  fi

  # Validate detected type is in the allowed list, otherwise fall back to extension
  case "$detected" in
    image/jpeg|image/png|image/webp|image/gif|video/mp4|video/quicktime|video/webm)
      echo "$detected"
      return 0
      ;;
  esac

  # Extension-based fallback
  local ext="${filepath##*.}"
  ext=$(echo "$ext" | tr '[:upper:]' '[:lower:]')
  case "$ext" in
    jpg|jpeg) echo "image/jpeg" ;;
    png)      echo "image/png" ;;
    webp)     echo "image/webp" ;;
    gif)      echo "image/gif" ;;
    mp4)      echo "video/mp4" ;;
    mov)      echo "video/quicktime" ;;
    webm)     echo "video/webm" ;;
    *)
      echo "ERROR: Cannot detect MIME type for '${filepath}'. Specify it manually." >&2
      return 1
      ;;
  esac
}

# ─── Media Upload (3-step signed URL flow) ────────────────────────────────────

posta_upload_media() {
  local filepath="$1"
  local mime_type="${2:-}"

  # Auto-detect MIME type if not provided
  if [[ -z "$mime_type" ]]; then
    mime_type=$(posta_detect_mime "$filepath")
  fi

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
  local mime_type="${2:-}"
  local filename="${3:-downloaded_media}"

  # Validate URL: must be HTTPS to prevent SSRF and local file access
  if [[ ! "$url" =~ ^https:// ]]; then
    echo "ERROR: Only HTTPS URLs are allowed for security. Got: ${url}" >&2
    return 1
  fi

  # Block private/internal IPs
  local host
  host=$(echo "$url" | sed -E 's|^https://([^/:]+).*|\1|')
  if [[ "$host" =~ ^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.|127\.|0\.|localhost|metadata\.google) ]]; then
    echo "ERROR: URLs pointing to private/internal networks are not allowed." >&2
    return 1
  fi

  # Determine extension from mime type (or URL)
  local ext=""
  if [[ -n "$mime_type" ]]; then
    case "$mime_type" in
      image/png)       ext=".png" ;;
      image/jpeg)      ext=".jpg" ;;
      image/webp)      ext=".webp" ;;
      image/gif)       ext=".gif" ;;
      video/mp4)       ext=".mp4" ;;
      video/quicktime) ext=".mov" ;;
      video/webm)      ext=".webm" ;;
      *)               ext="" ;;
    esac
  else
    # Try to infer from URL path
    local url_ext="${url##*.}"
    url_ext=$(echo "$url_ext" | tr '[:upper:]' '[:lower:]' | sed 's/[?#].*//')
    case "$url_ext" in
      jpg|jpeg|png|webp|gif|mp4|mov|webm)
        ext=".${url_ext}"
        ;;
    esac
  fi

  local tmpfile="/tmp/posta_upload_${RANDOM}${ext}"

  # Download file
  curl -sf -o "$tmpfile" "$url"

  if [[ ! -f "$tmpfile" || ! -s "$tmpfile" ]]; then
    echo "ERROR: Failed to download from ${url}" >&2
    rm -f "$tmpfile"
    return 1
  fi

  # Auto-detect MIME type if not provided
  if [[ -z "$mime_type" ]]; then
    mime_type=$(posta_detect_mime "$tmpfile")
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

# ─── Media Library Management ────────────────────────────────────────────────

posta_list_media() {
  # Usage: posta_list_media [type] [status] [limit] [offset]
  # type: image | video (optional)
  # status: pending | processing | completed | failed (optional)
  local type="${1:-}"
  local status="${2:-}"
  local limit="${3:-20}"
  local offset="${4:-0}"
  local query="limit=${limit}&offset=${offset}"
  if [[ -n "$type" ]]; then
    query="${query}&type=${type}"
  fi
  if [[ -n "$status" ]]; then
    query="${query}&status=${status}"
  fi
  posta_api GET "/media?${query}"
}

posta_delete_media() {
  local media_id="$1"
  posta_api DELETE "/media/${media_id}"
}

posta_generate_carousel_pdf() {
  # Generate a PDF carousel from multiple images
  # Usage: posta_generate_carousel_pdf media_ids_json [title]
  local media_ids_json="$1"
  local title="${2:-}"
  local body
  if [[ -n "$title" ]]; then
    body=$(jq -n --argjson ids "$media_ids_json" --arg t "$title" '{media_ids: $ids, title: $t}')
  else
    body=$(jq -n --argjson ids "$media_ids_json" '{media_ids: $ids}')
  fi
  posta_api POST "/media/generate-carousel-pdf" "$body"
}

# ─── Posts Calendar ──────────────────────────────────────────────────────────

posta_get_calendar() {
  # Get calendar view of posts for a date range
  # Usage: posta_get_calendar start_date end_date
  # Dates in YYYY-MM-DD format
  local start="$1"
  local end="$2"
  posta_api GET "/posts/calendar?start=${start}&end=${end}"
}

# ─── Platform Discovery ─────────────────────────────────────────────────────

posta_list_platforms() {
  posta_api GET "/platforms"
}

posta_get_platform_specs() {
  # Get full specs for all platforms (char limits, media requirements, features)
  posta_api GET "/platforms/specifications"
}

posta_get_aspect_ratios() {
  posta_api GET "/platforms/aspect-ratios"
}

posta_get_platform() {
  # Get detailed specs for a specific platform
  local platform_id="$1"
  posta_api GET "/platforms/${platform_id}"
}

posta_get_pinterest_boards() {
  # Get Pinterest boards for a connected account
  local account_id="$1"
  posta_api GET "/social-accounts/${account_id}/boards"
}

# ─── Extended Analytics ──────────────────────────────────────────────────────

posta_get_analytics_capabilities() {
  posta_api GET "/analytics/capabilities"
}

posta_get_analytics_posts() {
  # Usage: posta_get_analytics_posts [limit] [offset] [sort_by] [sort_order] [account_ids]
  local limit="${1:-20}"
  local offset="${2:-0}"
  local sort_by="${3:-engagements}"
  local sort_order="${4:-desc}"
  local account_ids="${5:-}"
  local query="limit=${limit}&offset=${offset}&sortBy=${sort_by}&sortOrder=${sort_order}"
  if [[ -n "$account_ids" ]]; then
    query="${query}&socialAccountIds=${account_ids}"
  fi
  posta_api GET "/analytics/posts?${query}"
}

posta_get_post_analytics() {
  local post_id="$1"
  posta_api GET "/analytics/posts/${post_id}"
}

posta_get_analytics_trends() {
  # Usage: posta_get_analytics_trends [period] [metric] [account_ids]
  # metric: impressions | engagements | engagement_rate
  local period="${1:-30d}"
  local metric="${2:-engagements}"
  local account_ids="${3:-}"
  local query="period=${period}&metric=${metric}"
  if [[ -n "$account_ids" ]]; then
    query="${query}&socialAccountIds=${account_ids}"
  fi
  posta_api GET "/analytics/trends?${query}"
}

posta_get_content_types() {
  posta_api GET "/analytics/content-types"
}

posta_get_hashtag_analytics() {
  posta_api GET "/analytics/hashtags"
}

posta_compare_posts() {
  # Compare 2-4 posts side by side
  # Usage: posta_compare_posts "id1,id2,id3"
  local post_ids="$1"
  posta_api GET "/analytics/compare?postIds=${post_ids}"
}

posta_export_analytics_csv() {
  # Export analytics as CSV. Returns binary data.
  local period="${1:-30d}"
  posta_api GET "/analytics/export/csv?period=${period}"
}

posta_export_analytics_pdf() {
  # Export analytics as PDF. Returns binary data.
  local period="${1:-30d}"
  posta_api GET "/analytics/export/pdf?period=${period}"
}

posta_get_benchmarks() {
  posta_api GET "/analytics/benchmarks"
}

posta_refresh_post_analytics() {
  local post_result_id="$1"
  posta_api POST "/analytics/refresh/${post_result_id}"
}

posta_refresh_all_analytics() {
  posta_api POST "/analytics/refresh-all"
}

# ─── User Profile ────────────────────────────────────────────────────────────

posta_get_profile() {
  posta_api GET "/users/profile"
}

posta_update_profile() {
  local body="$1"
  posta_api PATCH "/users/profile" "$body"
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
    echo "Set it in ~/.posta/credentials, .env, or as an env var" >&2
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

# ─── Auto-discover credentials on source ────────────────────────────────────
posta_discover_credentials
