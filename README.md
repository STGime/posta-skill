# Posta Skill for Claude Code

A Claude Code plugin that enables social media content generation, scheduling, and analytics through [Posta](https://getposta.app).

## Features

- **Post Management** — Create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky
- **Media Upload** — Upload images and videos via signed URL flow
- **AI Content Generation** — Generate images (Fireworks.ai SDXL), captions, and hashtags (Gemini/OpenAI)
- **Stupid Correlations** — Generate viral correlation content with charts, images, and animated videos via statapp
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

```bash
/plugin install getposta/posta-skill
```

Run this command inside a Claude Code session. The plugin will be downloaded and available across all your projects.

### Option B: Install from a local directory

Clone the repo, then point Claude Code to it:

```bash
# Clone the repo
git clone https://github.com/getposta/posta-skill.git ~/posta-skill

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

The plugin needs credentials to connect to Posta and (optionally) to AI generation services. There are two ways to configure them.

### Option 1: Shell profile (recommended — persistent across all sessions)

Add the variables to your shell profile so they're always available:

**For zsh (macOS default):**
```bash
# Open your profile
nano ~/.zshrc

# Add these lines at the bottom:
export POSTA_EMAIL="your@email.com"
export POSTA_PASSWORD="your-posta-password"

# Save and reload
source ~/.zshrc
```

**For bash:**
```bash
nano ~/.bash_profile

# Add the same export lines, then:
source ~/.bash_profile
```

### Option 2: Claude Code settings file (project-specific or global)

You can set environment variables in Claude Code's settings files. These are read at startup.

**Global** (all projects) — `~/.claude/settings.json`:
```json
{
  "env": {
    "POSTA_EMAIL": "your@email.com",
    "POSTA_PASSWORD": "your-posta-password"
  }
}
```

**Project-specific** (not committed to git) — `.claude/settings.local.json`:
```json
{
  "env": {
    "POSTA_EMAIL": "your@email.com",
    "POSTA_PASSWORD": "your-posta-password",
    "STATAPP_URL": "https://your-statapp.com"
  }
}
```

> **Note:** Shell environment variables take precedence over settings.json. Changes to either require restarting Claude Code.

---

## Environment Variables Reference

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTA_EMAIL` | Your Posta account email | `user@example.com` |
| `POSTA_PASSWORD` | Your Posta account password | `my-secure-password` |

Without these, the plugin cannot authenticate and no API calls will work.

### Posta API

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTA_BASE_URL` | Override the Posta API base URL | `https://api.getposta.app/v1` |

You only need to set this if you're running a self-hosted Posta instance or connecting to a staging environment.

### Stupid Correlations (statapp)

| Variable | Description | Example |
|----------|-------------|---------|
| `STATAPP_URL` | Base URL of your statapp instance | `https://statapp.example.com` |
| `STATAPP_EMAIL` | Your statapp account email | `user@example.com` |
| `STATAPP_PASSWORD` | Your statapp account password | `my-secure-password` |

All three are required if you want to generate "Stupid Correlations" content (viral data correlation images and videos). Without these, correlation-related commands won't work, but all other Posta features function normally.

### AI Content Generation

These are optional. Each unlocks a different generation capability:

| Variable | Service | What it enables | Where to get a key |
|----------|---------|----------------|-------------------|
| `FIREWORKS_API_KEY` | [Fireworks.ai](https://fireworks.ai) | AI image generation (SDXL) | [fireworks.ai/account/api-keys](https://fireworks.ai/account/api-keys) |
| `GEMINI_API_KEY` | [Google Gemini](https://ai.google.dev) | Caption and hashtag generation | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| `OPENAI_API_KEY` | [OpenAI](https://openai.com) | Alternative caption generation | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |

You don't need all three — each is independent:
- **Fireworks** is for generating images from text prompts
- **Gemini** or **OpenAI** are for generating captions, hashtags, and post copy (pick one or both)
- Without any generation keys, you can still upload your own media and create posts manually

### Full configuration example

```bash
# ~/.zshrc

# Required — Posta credentials
export POSTA_EMAIL="your@email.com"
export POSTA_PASSWORD="your-posta-password"

# Optional — Stupid Correlations
export STATAPP_URL="https://statapp.example.com"
export STATAPP_EMAIL="your@email.com"
export STATAPP_PASSWORD="your-statapp-password"

# Optional — AI image generation
export FIREWORKS_API_KEY="fw_1234567890abcdef"

# Optional — AI text generation (pick one or both)
export GEMINI_API_KEY="AIzaSy..."
export OPENAI_API_KEY="sk-proj-..."
```

After saving, reload your shell and restart Claude Code:

```bash
source ~/.zshrc
```

---

## Security Notes

- **Never commit credentials to git.** Use `.claude/settings.local.json` (gitignored by default) or shell profile for secrets.
- The plugin caches your Posta JWT token at `/tmp/.posta_token`. This is a temporary file that expires with the token and is cleared on reboot.
- API keys for Fireworks, Gemini, and OpenAI are sent only to their respective services — never to Posta.
- The plugin always creates posts as **drafts first** and asks for your confirmation before publishing or scheduling.

---

## Usage Examples

Once configured, just ask Claude naturally:

```
> Show me my connected social accounts

> Upload this image and post it to Instagram with the caption "Hello world!"

> Generate a stupid correlation and schedule it for tomorrow at 9am on all accounts

> Show me my best performing posts this month

> Create a portrait video correlation for TikTok and schedule it for Friday at 6pm

> What are the best times to post based on my analytics?

> Generate a social media post about spring flowers with AI image and caption
```

## What the plugin does behind the scenes

When you ask Claude to perform social media tasks, it:

1. **Authenticates** with your Posta account using `POSTA_EMAIL` / `POSTA_PASSWORD`
2. **Calls the Posta API** via the included bash helper script (handles token caching, retries, media upload)
3. **Shows you a preview** before publishing — caption, platforms, media, and scheduled time
4. **Suggests optimal posting times** from your analytics data when scheduling
5. **Generates content** using Fireworks/Gemini/OpenAI when asked (with your confirmation before spending API credits)

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "POSTA_EMAIL and POSTA_PASSWORD must be set" | Set the required environment variables and restart Claude Code |
| "Login failed — no token in response" | Check your email/password. Try logging in at [getposta.app](https://getposta.app) to verify |
| API returns 403 | Your Posta plan may have expired. Run: "Check my plan status" |
| Image generation fails silently | Verify `FIREWORKS_API_KEY` is set correctly. Check your Fireworks billing |
| Statapp commands do nothing | Set `STATAPP_URL`, `STATAPP_EMAIL`, and `STATAPP_PASSWORD` |
| "Statapp login failed" | Check your statapp email/password credentials |
| Changes to env vars not taking effect | Restart Claude Code — environment variables are read at startup |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |

## License

MIT
