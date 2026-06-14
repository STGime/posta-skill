# Posta Skill for Claude Code

A Claude Code plugin that enables social media content generation, scheduling, and analytics through [Posta](https://getposta.app).

## Features

- **Post Management** — Create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky
- **Media Upload** — Upload images and videos via signed URL flow
- **AI Image Generation** — Generate images with [fal.ai](https://fal.ai) (FLUX). Captions and hashtags are written by Claude directly — no text-generation API needed
- **Analytics** — View post performance, best posting times, trends, and engagement metrics
- **Account Management** — List connected social accounts and their status

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and working
- A [Posta](https://getposta.app) account with an active plan
- At least one connected social media account in Posta
- `curl` and `jq` available in your shell (`brew install jq` on macOS)

---

## Installation

### Option A: Install from GitHub (Recommended)

Run these two commands inside a Claude Code session:

```bash
# Step 1: Add the marketplace
/plugin marketplace add STGime/posta-skill

# Step 2: Install the plugin
/plugin install posta-skill@posta-plugins
```

The plugin will be downloaded and available across all your projects.

### Option B: Install from a local directory

Clone the repo, then point Claude Code to it:

```bash
# Clone the repo
git clone https://github.com/STGime/posta-skill.git ~/posta-skill

# Start Claude Code with the plugin loaded
claude --plugin-dir ~/posta-skill
```

### Option C: Project-level skill (no plugin install)

If you only want the skill available in a single project, copy the skill folder into your project:

```bash
# From your project root
mkdir -p .claude/skills
cp -r ~/posta-skill/skills/posta .claude/skills/posta
```

The skill will auto-activate when you ask Claude about social media posting, scheduling, or content generation.

### Verify installation

Start a new Claude Code session and say:

```
Show me my connected social accounts
```

If the skill activates and attempts to authenticate, the installation is working.

---

## Configuration

The plugin needs credentials to connect to Posta and (optionally) to the fal.ai image generator.

### Option 1: API Token (recommended)

API tokens are the simplest and most secure way to authenticate. Generate one from your Posta dashboard or via the API, then set a single environment variable:

**Shell profile (persistent across all sessions):**
```bash
# ~/.zshrc or ~/.bash_profile
export POSTA_API_TOKEN="posta_your_token_here"
```

**Claude Code settings** — `~/.claude/settings.json`:
```json
{
  "env": {
    "POSTA_API_TOKEN": "posta_your_token_here"
  }
}
```

**Dedicated credentials file** — `~/.posta/credentials`:
```bash
POSTA_API_TOKEN="posta_your_token_here"
```

To generate a token via the API (requires a one-time login):
```bash
# Get a JWT first
TOKEN=$(curl -sf -X POST https://api.getposta.app/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"your-password"}' | jq -r '.access_token')

# Create an API token
curl -sf -X POST https://api.getposta.app/v1/auth/tokens \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Claude Code CLI"}' | jq '.token'
```

Save the returned `posta_...` token — it is shown only once.

### Option 2: Email & Password (legacy)

You can still use email/password. The plugin will log in and cache a JWT automatically.

**Shell profile:**
```bash
export POSTA_EMAIL="your@email.com"
export POSTA_PASSWORD="your-posta-password"
```

**Claude Code settings** — `~/.claude/settings.json`:
```json
{
  "env": {
    "POSTA_EMAIL": "your@email.com",
    "POSTA_PASSWORD": "your-posta-password"
  }
}
```

> **Note:** Shell environment variables take precedence over settings files. Changes require restarting Claude Code.

---

## Environment Variables Reference

### Authentication (one of the following)

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTA_API_TOKEN` | **Recommended.** Personal API token (starts with `posta_`) | `posta_a1b2c3d4...` |
| `POSTA_EMAIL` | Your Posta account email (legacy) | `user@example.com` |
| `POSTA_PASSWORD` | Your Posta account password (legacy) | `my-secure-password` |

Set `POSTA_API_TOKEN` for the simplest setup. If set, email/password are not needed.

### Posta API

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTA_BASE_URL` | Override the Posta API base URL | `https://api.getposta.app/v1` |

You only need to set this if you're running a self-hosted Posta instance or connecting to a staging environment.

### AI Image Generation

Optional — only needed if you want Claude to generate images from text prompts:

| Variable | Service | What it enables | Where to get a key |
|----------|---------|----------------|-------------------|
| `FAL_KEY` | [fal.ai](https://fal.ai) | AI image generation (FLUX) | [fal.ai/dashboard/keys](https://fal.ai/dashboard/keys) |

- Captions, hashtags, and post copy are written by **Claude itself** — no text-generation API key is required.
- Without `FAL_KEY` you can still upload your own media and create posts; you just can't generate images on the fly.

### Full configuration example

```bash
# ~/.zshrc

# Posta auth (recommended: API token)
export POSTA_API_TOKEN="posta_a1b2c3d4e5f6..."

# Optional — AI image generation (fal.ai)
export FAL_KEY="key_id:key_secret"
```

After saving, reload your shell and restart Claude Code:

```bash
source ~/.zshrc
```

---

## Security Notes

- **Never commit credentials to git.** Use `.claude/settings.local.json` (gitignored by default) or shell profile for secrets.
- **API tokens are the recommended auth method.** They don't expose your account password, are long-lived, and can be revoked individually without changing your password.
- The plugin caches your Posta JWT token at `/tmp/.posta_token`. This is a temporary file that expires with the token and is cleared on reboot. API tokens skip this cache entirely.
- Your `FAL_KEY` is sent only to fal.ai — never to Posta.
- The plugin always creates posts as **drafts first** and asks for your confirmation before publishing or scheduling.
- To revoke an API token, use `DELETE /v1/auth/tokens/:id` or manage tokens in your Posta dashboard.

---

## Usage Examples

Once configured, just ask Claude naturally:

```
> Show me my connected social accounts

> Upload this image and post it to Instagram with the caption "Hello world!"

> Show me my best performing posts this month

> What are the best times to post based on my analytics?

> Generate a social media post about spring flowers with an AI-generated image

> Build a LinkedIn carousel from these 5 images
```

## What the plugin does behind the scenes

When you ask Claude to perform social media tasks, it:

1. **Authenticates** with your Posta account using `POSTA_API_TOKEN` (or `POSTA_EMAIL` / `POSTA_PASSWORD`)
2. **Calls the Posta API** via the included bash helper script (handles token caching, retries, media upload)
3. **Shows you a preview** before publishing — caption, platforms, media, and scheduled time
4. **Suggests optimal posting times** from your analytics data when scheduling
5. **Generates images** with fal.ai when asked (with your confirmation before spending API credits), and writes captions and hashtags itself

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "POSTA_EMAIL and POSTA_PASSWORD must be set" | Set `POSTA_API_TOKEN` (recommended) or both `POSTA_EMAIL` and `POSTA_PASSWORD`, then restart Claude Code |
| "API token is invalid or revoked" | Generate a new API token — the current one was revoked or is malformed |
| "Login failed — no token in response" | Check your email/password. Try logging in at [getposta.app](https://getposta.app) to verify |
| API returns 403 | Your Posta plan may have expired. Run: "Check my plan status" |
| Image generation fails silently | Verify `FAL_KEY` is set correctly (format `key_id:key_secret`). Check your fal.ai billing |
| Changes to env vars not taking effect | Restart Claude Code — environment variables are read at startup |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |

## License

MIT
