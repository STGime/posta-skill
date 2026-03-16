# Posta Skill

A social media management skill for AI coding assistants. Works with **Claude Code** and **OpenClaw**.

Create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky — with AI content generation and analytics.

## Features

- **Post Management** — Create, schedule, publish, update, and cancel posts across 9 platforms
- **Media Upload** — Upload images and videos with auto MIME detection, manage media library, generate carousel PDFs
- **AI Content Generation** — Generate images (Fireworks SDXL), captions and hashtags (Gemini/OpenAI)
- **Analytics** — Performance overview, best posting times, trends, post comparison, hashtag analysis, benchmarks, CSV/PDF export
- **Platform Discovery** — Query character limits, media requirements, and supported features per platform
- **Content Calendar** — View scheduled and posted content across date ranges
- **Account Management** — List connected social accounts, check status and token expiration

## Prerequisites

- A [Posta](https://getposta.app) account with an active plan
- At least one connected social media account in Posta
- `curl` and `jq` available in your shell (`brew install jq` on macOS)

---

## Installation

### Claude Code

**Option A: From GitHub (recommended)**

```bash
# In a Claude Code session:
/plugin marketplace add STGime/posta-skill
/plugin install posta-skill
```

**Option B: Local directory**

```bash
git clone https://github.com/STGime/posta-skill.git ~/posta-skill
claude --plugin-dir ~/posta-skill
```

**Option C: Project-level skill**

```bash
mkdir -p .claude/skills
cp -r ~/posta-skill/skills/posta .claude/skills/posta
```

### OpenClaw

**Option A: Managed skill (persistent across sessions)**

```bash
git clone https://github.com/STGime/posta-skill.git ~/posta-skill
ln -s ~/posta-skill/skills/posta ~/.openclaw/skills/posta
```

**Option B: Workspace-level skill (single workspace)**

```bash
git clone https://github.com/STGime/posta-skill.git ~/posta-skill
mkdir -p skills
cp -r ~/posta-skill/skills/posta skills/posta
```

To update later, `git pull` in `~/posta-skill` — symlinks (Option A) pick up changes automatically.

### Verify Installation

Start a new session and say:

```
Show me my connected social accounts
```

If the skill activates and attempts to authenticate, the installation is working.

---

## Configuration

### Authentication (pick one)

**API Token (recommended):**

```bash
# ~/.zshrc, ~/.bashrc, or ~/.posta/credentials
export POSTA_API_TOKEN="posta_your_token_here"
```

Generate a token via the API:

```bash
# Get a JWT first
TOKEN=$(curl -sf -X POST https://api.getposta.app/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"your@email.com","password":"your-password"}' | jq -r '.access_token')

# Create an API token
curl -sf -X POST https://api.getposta.app/v1/auth/tokens \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Posta Skill"}' | jq '.token'
```

Save the returned `posta_...` token — it is shown only once.

**Email & Password (legacy):**

```bash
export POSTA_EMAIL="your@email.com"
export POSTA_PASSWORD="your-posta-password"
```

### Platform-specific configuration

<details>
<summary>Claude Code settings — <code>~/.claude/settings.json</code></summary>

```json
{
  "env": {
    "POSTA_API_TOKEN": "posta_your_token_here"
  }
}
```
</details>

<details>
<summary>OpenClaw settings — <code>~/.openclaw/config.json</code></summary>

```json
{
  "env": {
    "POSTA_API_TOKEN": "posta_your_token_here"
  }
}
```
</details>

### Credentials Auto-Discovery

The skill discovers credentials from dedicated config files only (shell profiles are **never** read):
1. Already-set environment variables
2. `~/.posta/credentials` (preferred)
3. `.env`, `.env.local`, `.env.production` in the current directory

---

## Environment Variables

### Authentication

| Variable | Description | Example |
|----------|-------------|---------|
| `POSTA_API_TOKEN` | **Recommended.** Personal API token (starts with `posta_`) | `posta_a1b2c3d4...` |
| `POSTA_EMAIL` | Account email (legacy) | `user@example.com` |
| `POSTA_PASSWORD` | Account password (legacy) | `my-secure-password` |

### API

| Variable | Description | Default |
|----------|-------------|---------|
| `POSTA_BASE_URL` | Override API base URL | `https://api.getposta.app/v1` |

### AI Content Generation (optional)

| Variable | Service | What it enables | Get a key |
|----------|---------|----------------|-----------|
| `FIREWORKS_API_KEY` | [Fireworks.ai](https://fireworks.ai) | AI image generation (SDXL) | [fireworks.ai/account/api-keys](https://fireworks.ai/account/api-keys) |
| `GEMINI_API_KEY` | [Google Gemini](https://ai.google.dev) | Caption and hashtag generation | [aistudio.google.com/apikey](https://aistudio.google.com/apikey) |
| `OPENAI_API_KEY` | [OpenAI](https://openai.com) | Alternative caption generation | [platform.openai.com/api-keys](https://platform.openai.com/api-keys) |

Each key is independent. Without any generation keys, you can still upload your own media and create posts.

### Full example

```bash
# ~/.zshrc
export POSTA_API_TOKEN="posta_a1b2c3d4e5f6..."
export FIREWORKS_API_KEY="fw_1234567890abcdef"       # optional
export GEMINI_API_KEY="AIzaSy..."                     # optional
export OPENAI_API_KEY="sk-proj-..."                   # optional
```

---

## Usage Examples

### Create and publish a post

```
Upload this image to Instagram and Twitter with the caption "Hello world!"
```

The skill will:
1. List your connected accounts to find Instagram and X/Twitter
2. Auto-detect the image MIME type and upload it
3. Create a draft post with generated hashtags
4. Show you a preview for confirmation
5. Publish or schedule on your approval

### Generate AI content from scratch

```
Generate a social media post about spring flowers with an AI image and caption
```

The skill will:
1. Generate an image using Fireworks SDXL
2. Generate a caption using Gemini or OpenAI
3. Generate relevant hashtags
4. Upload the image and create a draft post
5. Ask which accounts to post to

### View analytics and best posting times

```
Show me my best performing posts this month and suggest when to post next
```

The skill will:
1. Fetch analytics overview for the last 30 days
2. Get top posts sorted by engagements
3. Fetch best posting times heatmap
4. Display everything in a formatted table with insights

### Check platform specs before posting

```
What are the character limits and media requirements for TikTok?
```

The skill will:
1. Query the platform specifications API
2. Return character limits, supported media formats, aspect ratios, and features

### Manage your content calendar

```
Show me what's scheduled for next week
```

The skill will:
1. Fetch the calendar view for the date range
2. Display posts organized by day with status and platforms

### Compare post performance

```
Compare my last 3 posts and export a report
```

The skill will:
1. Get recent posts with analytics
2. Compare them side by side (engagements, impressions, reach)
3. Export analytics as CSV or PDF

### Media library management

```
Show me my uploaded media and clean up unused files
```

The skill will:
1. List media with type/status filters
2. Show processing status for each item
3. Delete items you identify as unused

### Generate a carousel

```
Create a carousel from these 5 images for Instagram
```

The skill will:
1. Upload the images
2. Generate a PDF carousel
3. Create a draft post with the carousel attached

### Schedule with optimal timing

```
Schedule this post for the best time to reach my audience
```

The skill will:
1. Fetch best-times analytics for your accounts
2. Recommend the highest-engagement time slot
3. Schedule the post after your confirmation

---

## How It Works

When you ask the AI to perform social media tasks, it:

1. **Authenticates** with your Posta account using `POSTA_API_TOKEN` (or email/password)
2. **Calls the Posta API** via the included bash helper script (handles token caching, retries, media upload)
3. **Shows you a preview** before publishing — caption, platforms, media, and scheduled time
4. **Suggests optimal posting times** from your analytics data when scheduling
5. **Generates content** using Fireworks/Gemini/OpenAI when asked (with your confirmation before spending API credits)

## Supported Platforms

| Platform | Post | Image | Video | Analytics |
|----------|------|-------|-------|-----------|
| Instagram | Yes | Yes | Yes | Yes |
| TikTok | Yes | Yes | Yes | Yes |
| Facebook | Yes | Yes | Yes | Yes |
| X/Twitter | Yes | Yes | Yes | Yes |
| LinkedIn | Yes | Yes | Yes | No |
| YouTube | Yes | Yes | Yes | Yes |
| Pinterest | Yes | Yes | Yes | Yes |
| Threads | Yes | Yes | Yes | Yes |
| Bluesky | Yes | Yes | Yes | Yes |

## Security Notes

- **Never commit credentials to git.** Use environment variables or `~/.posta/credentials` for secrets.
- **API tokens are recommended.** They don't expose your password, are long-lived, and can be revoked individually.
- JWT token cache at `/tmp/.posta_token` is temporary and cleared on reboot. API tokens skip this entirely.
- AI generation keys (Fireworks, Gemini, OpenAI) are sent only to their respective services — never to Posta.
- The skill always creates posts as **drafts first** and asks for confirmation before publishing.
- **Credential discovery** reads only specific `POSTA_*` and `FIREWORKS_API_KEY` variable names from a fixed list of files. See [SECURITY.md](SECURITY.md) for a detailed explanation of every file accessed and why.

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "POSTA_EMAIL and POSTA_PASSWORD must be set" | Set `POSTA_API_TOKEN` (recommended) or both email and password, then restart |
| "API token is invalid or revoked" | Generate a new API token from your Posta dashboard |
| "Login failed — no token in response" | Check your email/password at [getposta.app](https://getposta.app) |
| API returns 403 | Your plan may have expired — ask "Check my plan status" |
| Image generation fails silently | Verify `FIREWORKS_API_KEY` is set correctly |
| Changes to env vars not taking effect | Restart your session — env vars are read at startup |
| `jq: command not found` | Install jq: `brew install jq` (macOS) or `apt install jq` (Linux) |

## Compatibility

| Platform | Version | Status |
|----------|---------|--------|
| Claude Code | 1.0+ | Fully supported |
| OpenClaw | 1.0+ | Fully supported |

Both platforms use the AgentSkills `SKILL.md` format. The skill resolves its install path from the platform's root directory variable (`POSTA_SKILL_ROOT`, `OPENCLAW_SKILL_ROOT`, or `CLAUDE_PLUGIN_ROOT`) — a standard portable shell pattern for locating sibling files.

## License

MIT
