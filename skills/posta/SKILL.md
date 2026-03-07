---
name: posta
description: Use this skill when the user wants to create social media content, generate images/videos/text with AI, upload media, create posts, schedule or publish posts, view analytics, or manage social accounts through Posta. Also activates for "Stupid Correlations" content generation via statapp.
---

# Posta — Social Media Content & Scheduling

Posta is a social media management platform that lets you create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky.

This skill enables you to interact with the Posta API to manage social media content end-to-end: authenticate, list accounts, upload media, create/schedule/publish posts, generate AI content, create Stupid Correlations videos, and view analytics.

## Setup

### Authentication (one of the following)

- `POSTA_API_TOKEN` — **Recommended.** Personal API token (starts with `posta_`). Long-lived, revocable, no password exposure.
- `POSTA_EMAIL` + `POSTA_PASSWORD` — Legacy login. The skill logs in and caches a JWT automatically.

If `POSTA_API_TOKEN` is set, email/password are not needed and the login flow is skipped entirely.

### Optional Environment Variables

- `POSTA_BASE_URL` — API base URL (default: `https://api.getposta.app/v1`)
- `STATAPP_URL` — Stupid Correlations API base URL (for correlation content)
- `STATAPP_EMAIL` — Statapp account email (required for statapp access)
- `STATAPP_PASSWORD` — Statapp account password (required for statapp access)
- `FIREWORKS_API_KEY` — Fireworks.ai API key (for image generation). Keys start with `fw_`. Get one at https://fireworks.ai/account/api-keys. The skill auto-discovers this from env vars, `.env.development`, `~/.zshrc`, `~/.bashrc`, or `~/.posta/credentials`.
- `GEMINI_API_KEY` — Google Gemini API key (for caption/text generation)
- `OPENAI_API_KEY` — OpenAI API key (alternative text generation)

### Credentials Auto-Discovery

The skill automatically discovers credentials from multiple locations (in order):
1. Already-set environment variables
2. `~/.posta/credentials` (dedicated config file — checked first for `POSTA_API_TOKEN`)
3. `~/.zshrc` and `~/.bashrc` (grep for exports)
4. `.env`, `.env.local`, `.env.production` in the current working directory

If a `POSTA_API_TOKEN` is found during discovery, the skill uses it immediately and skips email/password lookup.

### Helper Script

Source the bash helper for all API interactions:

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"
```

This provides:
- **Posta:** `posta_login`, `posta_api`, `posta_upload_media`, `posta_upload_from_url`, `posta_list_accounts`, `posta_list_posts`, `posta_create_post`, `posta_create_post_from_file`, `posta_get_post`, `posta_update_post`, `posta_delete_post`, `posta_cancel_post`, `posta_schedule_post`, `posta_publish_post`, `posta_get_media`, `posta_get_analytics_overview`, `posta_get_best_times`, `posta_get_plan`, `posta_discover_credentials`, `fireworks_validate_key`
- **Statapp:** `statapp_login`, `statapp_api`, `statapp_generate_random`, `statapp_animate`, `statapp_animate_status`, `statapp_get_styles`

### Reference Docs

- [Posta API Reference](references/posta-api-reference.md) — Full REST API documentation
- [Statapp API Reference](references/statapp-api-reference.md) — Stupid Correlations endpoints
- [Content Generation Patterns](references/content-generation.md) — Fireworks/Gemini/OpenAI usage
- [Workflow Examples](examples/workflows.md) — Full example conversations

---

## Core Workflows

### 1. Authenticate

Authentication is automatic. If `POSTA_API_TOKEN` is set, the skill uses it directly — no login step needed. Otherwise it falls back to email/password login with JWT caching. If a request returns 401:
- **API token**: reports the token is invalid/revoked (no retry)
- **JWT**: re-authenticates and retries once

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"
# Token is fetched/cached automatically on first API call
```

To verify credentials are working:
```bash
posta_api GET "/auth/me"
```

### 2. List Connected Social Accounts

```bash
ACCOUNTS=$(posta_list_accounts)
# Returns a plain array (wrapper is auto-unwrapped)
echo "$ACCOUNTS" | jq -r '.[] | "\(.platform)\t\(.username)\t\(.isActive)"'
```

Display as a table showing: Platform, Username, Active status, Last used.

> **Note:** Account IDs from `posta_list_accounts` are integers (e.g. `35`). Wrap them in quotes when passing to `socialAccountIds`: `"socialAccountIds": ["35"]`

### 3. Upload Media

The upload flow has 3 steps: create signed URL → PUT binary → confirm upload.

**From a local file:**
```bash
MEDIA_ID=$(posta_upload_media "/path/to/file.jpg" "image/jpeg")
```

**From a URL (e.g., generated image):**
```bash
MEDIA_ID=$(posta_upload_from_url "https://example.com/image.png" "image/png")
```

**Supported formats:**
- Images: `image/jpeg`, `image/png`, `image/webp`, `image/gif` (max 20MB)
- Videos: `video/mp4`, `video/quicktime`, `video/webm` (max 500MB)

After upload, the media enters `processing` status. For images this is fast (thumbnails/variants). For videos it takes longer. Check status with:
```bash
posta_api GET "/media/${MEDIA_ID}"
```

### 4. Create, Schedule & Publish Posts

**Create a draft post:**
```bash
POST=$(posta_create_post '{
  "caption": "Your caption here",
  "hashtags": ["tag1", "tag2"],
  "mediaIds": ["media-uuid"],
  "socialAccountIds": ["35", "42"],
  "isDraft": true
}')
POST_ID=$(echo "$POST" | jq -r '.id')
```

**Create a post with multiline caption (from file):**
```bash
cat > /tmp/caption.txt << 'EOF'
Line one of the caption.

Line two with details.

Call to action here.
EOF
POST=$(posta_create_post_from_file /tmp/caption.txt '["media-uuid"]' '["35", "42"]' true)
POST_ID=$(echo "$POST" | jq -r '.id')
```

**Schedule for a specific time:**
```bash
posta_schedule_post "$POST_ID" "2026-03-15T09:00:00Z"
```

**Publish immediately:**
```bash
posta_publish_post "$POST_ID"
```

**Platform-specific configuration** (optional):
```json
{
  "platformConfigurations": {
    "tiktok": {
      "privacyLevel": "PUBLIC_TO_EVERYONE",
      "allowComment": true,
      "allowDuet": false,
      "allowStitch": false
    },
    "pinterest": {
      "boardId": "board-id",
      "link": "https://your-link.com",
      "altText": "Image description"
    }
  }
}
```

Note: Either `caption` or at least one `mediaIds` entry is required. Text-only posts work for X/Twitter.

### 5. Generate AI Content

**Generate an image with Fireworks SDXL:**
```bash
curl -s -X POST \
  "https://api.fireworks.ai/inference/v1/image_generation/accounts/fireworks/models/stable-diffusion-xl-1024-v1-0" \
  -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: image/png" \
  -d '{
    "prompt": "your descriptive prompt, photorealistic, natural colors, high quality, detailed",
    "negative_prompt": "text, watermark, blurry, low quality, distorted",
    "width": 1024, "height": 1024, "steps": 30, "guidance_scale": 7.5
  }' --output /tmp/generated.png

MEDIA_ID=$(posta_upload_media /tmp/generated.png "image/png")
```

**Generate a caption with Gemini:**
```bash
CAPTION=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{"parts": [{"text": "Write an engaging Instagram caption about [topic]. Max 150 words."}]}],
    "generationConfig": {"temperature": 0.8, "maxOutputTokens": 300}
  }' | jq -r '.candidates[0].content.parts[0].text')
```

See [content-generation.md](references/content-generation.md) for full patterns including OpenAI and hashtag generation.

### 6. Generate Stupid Correlations

Generate viral correlation content (chart + AI image + optional video):

**Image only (fast):**
```bash
RESULT=$(statapp_generate_random "square" "classic" false)

IMAGE_URL=$(echo "$RESULT" | jq -r '.image.url')
HEADLINE=$(echo "$RESULT" | jq -r '.caption.headline')
CAPTION=$(echo "$RESULT" | jq -r '.caption.caption')
```

**With video (slower but great for TikTok/Reels):**
```bash
RESULT=$(statapp_generate_random "portrait" "neon" true)

VIDEO_URL=$(echo "$RESULT" | jq -r '.video.url')
```

**Async video (for separate video generation):**
```bash
# 1. Generate image first
RESULT=$(statapp_generate_random "portrait" "classic" false)

# 2. Queue video job
JOB=$(statapp_animate '{
  "datasetAId": "'"$(echo "$RESULT" | jq -r '.correlation.datasetA.id')"'",
  "datasetBId": "'"$(echo "$RESULT" | jq -r '.correlation.datasetB.id')"'",
  "backgroundUrl": "'"$(echo "$RESULT" | jq -r '.background.url')"'",
  "caption": '"$(echo "$RESULT" | jq '.caption')"',
  "aspectRatio": "portrait",
  "chartStyle": "neon"
}')

JOB_ID=$(echo "$JOB" | jq -r '.jobId')

# 3. Wait for completion (long-poll)
VIDEO_RESULT=$(statapp_animate_status "$JOB_ID" true)

VIDEO_URL=$(echo "$VIDEO_RESULT" | jq -r '.video.url')
```

Aspect ratios: `square` (1024x1024, Instagram), `portrait` (768x1344, TikTok/Reels), `landscape` (1344x768, LinkedIn/X).

Chart styles: `classic`, `neon`, `minimal`.

See [statapp-api-reference.md](references/statapp-api-reference.md) for full API docs.

### 7. View Analytics

**Overview stats:**
```bash
OVERVIEW=$(posta_get_analytics_overview "30d")
echo "$OVERVIEW" | jq '{totalPosts, totalImpressions, totalEngagements, avgEngagementRate}'
```

**Best posting times:**
```bash
BEST_TIMES=$(posta_get_best_times)
```

**Top performing posts:**
```bash
TOP=$(posta_api GET "/analytics/posts?limit=10&sortBy=engagements&sortOrder=desc")
```

**Trends over time:**
```bash
TRENDS=$(posta_api GET "/analytics/trends?period=30d&metric=engagements")
```

**Check plan and usage:**
```bash
PLAN=$(posta_get_plan)
echo "$PLAN" | jq '{plan, usage, limits}'
```

---

## Guidelines

1. **Always show a preview before publishing.** Display the caption, target platforms, media description, and scheduled time. Ask for confirmation before calling publish or schedule.

2. **Suggest optimal posting times.** When the user wants to schedule, fetch best-times analytics and recommend the highest-engagement time slot.

3. **Ask before spending API credits.** Image generation (Fireworks) and text generation (Gemini/OpenAI) cost money. Confirm with the user before making generation API calls.

4. **Handle errors gracefully.** If an API call fails, show the error message and suggest next steps (check credentials, verify account connection, check plan limits).

5. **Respect plan limits.** Check the user's plan with `posta_get_plan` before attempting operations that may exceed limits (posts, accounts, storage).

6. **Use appropriate aspect ratios.** Match the content format to the target platform — portrait for TikTok/Reels, square for Instagram feed, landscape for LinkedIn/X.

7. **Create posts as drafts first.** Always set `isDraft: true` when creating posts, then schedule or publish after user confirmation.

8. **Combine media types strategically.** For maximum reach, generate both an image (for Instagram/LinkedIn) and a video (for TikTok/Reels) from the same content.

9. **Preview generated images before uploading.** After generating an image with Fireworks, use the Read tool to preview it visually before uploading to Posta. This prevents wasted uploads and media quota.

10. **Use `posta_create_post_from_file` for multiline captions.** Write the caption to a temp file and use the file-based helper instead of trying to embed multiline text in JSON strings. This avoids escaping issues.

11. **Always generate hashtags for posts.** When creating a post, always include relevant hashtags in the `hashtags` array. Generate 5–10 hashtags based on the caption content, target platform, and topic. Mix broad reach tags (e.g. #AI, #Marketing) with niche tags (e.g. #LaborMarket, #FutureOfWork). Do not wait for the user to ask — hashtags should be included by default on every post.

12. **Use `/tmp/.posta_last_response` for captured output.** When capturing `posta_api` output in a variable with `$()`, avoid using `echo` to re-output it — macOS echo corrupts `\n` in JSON strings. Instead pipe directly (`posta_api ... | jq`) or read from the file (`jq ... /tmp/.posta_last_response`).
