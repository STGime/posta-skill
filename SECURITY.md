# Security

This document explains patterns in the Posta skill that automated security scanners may flag. Each is benign and exists for a specific functional reason.

## Flagged patterns

### 1. Environment variable path resolution (`detect-debug-environment`)

**What the scanner sees:**
```bash
source "${POSTA_SKILL_ROOT:-${OPENCLAW_SKILL_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}/skills/posta/scripts/posta-api.sh"
```

**Why it exists:** The skill runs on multiple AI assistant platforms (Claude Code, OpenClaw). Each platform sets a different root directory variable (`CLAUDE_PLUGIN_ROOT`, `OPENCLAW_SKILL_ROOT`, or `POSTA_SKILL_ROOT`). The script checks these variables to locate its own files on disk — the same way any portable shell script resolves its install path.

**What it does NOT do:** This code does not detect sandboxes, debuggers, analysis tools, or virtual machines. It never changes behavior based on whether it is being observed.

### 2. Credential auto-discovery

**What the scanner sees:** The script reads from `~/.posta/credentials`, `~/.zshrc`, `~/.bashrc`, and `.env` files.

**Why it exists:** The skill needs a Posta API token to authenticate API calls. Rather than requiring users to manually export the token in every terminal session, the script searches a fixed list of standard locations where developers commonly store environment variables. The search order is:

1. Already-set environment variables (no file access)
2. `~/.posta/credentials` — a dedicated, skill-specific config file
3. Shell profiles (`~/.zshrc`, `~/.bashrc`) — standard locations for `export VAR=value`
4. `.env` files in the working directory

The script only reads variables prefixed with `POSTA_`, `FIREWORKS_API_KEY`, `GEMINI_API_KEY`, or `OPENAI_API_KEY`. It uses targeted `grep` for exact variable names — it does not dump or exfiltrate file contents.

**What it does NOT do:** The script never reads SSH keys, browser cookies, cloud provider credentials, password managers, keychains, or any file outside the specific list above. Discovered values are only used locally for API authentication — they are never logged, transmitted to third parties, or written to disk (except the JWT cache at `/tmp/.posta_token`, which is cleared on reboot).

### 3. Process name or script identification (`sets-process-name`)

**Context:** The script does not use `exec -a`, `prctl`, or any process-renaming syscall. If this flag was triggered, it is likely due to the `BASH_SOURCE` / `$0` resolution on line 13 of `posta-api.sh`, which determines the script's own directory to locate sibling files (`sanitize_json.py`). This is standard POSIX shell practice.

## Data flow summary

```
User's env/config files
        │
        ▼
  posta-api.sh (reads POSTA_API_TOKEN or POSTA_EMAIL/PASSWORD)
        │
        ▼
  Posta API (https://api.getposta.app) — authenticated REST calls
        │
        ▼
  JSON responses displayed to the user via their AI assistant
```

- No data is sent anywhere other than `api.getposta.app` (and optionally `api.fireworks.ai`, `generativelanguage.googleapis.com`, or `api.openai.com` for AI content generation).
- The script never phones home, collects telemetry, or contacts any endpoint not explicitly requested by the user.

## Reporting security issues

If you find an actual security vulnerability, please email security@getposta.app or open a private advisory on GitHub.
