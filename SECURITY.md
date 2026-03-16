# Security

This document explains the security model of the Posta skill and addresses patterns that automated scanners may flag.

## Credential discovery

The script reads credentials **only** from dedicated config files — never from shell profiles or arbitrary user files.

**Files accessed (exhaustive list):**
1. `~/.posta/credentials` — dedicated, skill-specific config file (preferred)
2. `.env`, `.env.local`, `.env.production` — standard project dotenv files in the working directory

**Shell profiles (`~/.zshrc`, `~/.bashrc`) are never read.**

**Variable names searched (exact match only):**
- `POSTA_API_TOKEN`
- `POSTA_EMAIL` (legacy)
- `POSTA_PASSWORD` (legacy)
- `FIREWORKS_API_KEY`

The script uses `grep -E "^(export )?VARNAME="` for exact variable name matching — it does not dump, scan, or exfiltrate file contents. Discovered values are used locally for API authentication and are never logged, transmitted to third parties, or persisted to disk (except the JWT cache at `/tmp/.posta_token`, cleared on reboot).

**What is NOT accessed:** SSH keys, browser cookies, cloud provider credentials, keychains, password managers, or any file outside the list above.

## URL handling

The `posta_upload_from_url` function downloads media from user-provided URLs for upload to Posta. It enforces:
- **HTTPS only** — `http://`, `file://`, and other schemes are rejected
- **No private/internal networks** — blocks `10.x`, `172.16-31.x`, `192.168.x`, `127.x`, `localhost`, and cloud metadata endpoints

## Environment variable path resolution

```bash
source "${POSTA_SKILL_ROOT:-${OPENCLAW_SKILL_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}/skills/posta/scripts/posta-api.sh"
```

The skill runs on multiple AI assistant platforms (Claude Code, OpenClaw). Each sets a different root directory variable. The script checks these to locate its own files — standard portable shell path resolution. This does **not** detect sandboxes, debuggers, or analysis tools.

## User consent model

All destructive or costly actions require explicit user confirmation:
- **Publishing/scheduling** — posts are created as drafts; the agent must show a preview and get approval before publishing
- **AI content generation** — Fireworks/Gemini/OpenAI calls cost money; the agent confirms before making generation requests
- **Hashtag suggestions** — generated hashtags are shown to the user for approval before being included in posts

## Data flow

```
~/.posta/credentials or .env files
        │
        ▼
  posta-api.sh (reads POSTA_API_TOKEN)
        │
        ▼
  Posta API (https://api.getposta.app) — authenticated REST calls
        │
        ▼
  JSON responses displayed to the user via their AI assistant
```

No data is sent anywhere other than `api.getposta.app` (and optionally `api.fireworks.ai`, `generativelanguage.googleapis.com`, or `api.openai.com` for AI content generation when explicitly requested by the user).

The script never phones home, collects telemetry, or contacts any endpoint not explicitly requested by the user.

## Reporting security issues

If you find a security vulnerability, please email security@getposta.app or open a private advisory on GitHub.
