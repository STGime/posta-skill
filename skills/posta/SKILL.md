---
name: posta
description: Use this skill when the user wants to create social media content, generate images/videos/text with AI, upload media, create posts, schedule or publish posts, view analytics, or manage social accounts through Posta.
---

# Posta — Social Media Content & Scheduling

Posta is a social media management platform that lets you create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky.

This skill enables you to interact with the Posta API to manage social media content end-to-end: authenticate, list accounts, upload media, create/schedule/publish posts, generate AI content, build LinkedIn carousels, and view analytics.

## Setup

### Authentication (one of the following)

- `POSTA_API_TOKEN` — **Recommended.** Personal API token (starts with `posta_`). Long-lived, revocable, no password exposure.
- `POSTA_EMAIL` + `POSTA_PASSWORD` — Legacy login. The skill logs in and caches a JWT automatically.

If `POSTA_API_TOKEN` is set, email/password are not needed and the login flow is skipped entirely.

### Optional Environment Variables

- `POSTA_BASE_URL` — API base URL (default: `https://api.getposta.app/v1`)
- `FAL_KEY` — fal.ai API key (for image generation). Format is `<key_id>:<key_secret>`. Get one at https://fal.ai/dashboard/keys. The skill auto-discovers this from env vars, `.env.development`, `~/.zshrc`, `~/.bashrc`, or `~/.posta/credentials`.

> Captions and hashtags are written by Claude directly — no text-generation API key is needed. The only external content service is the image generator (fal.ai).

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
- **Posta:** `posta_login`, `posta_api`, `posta_upload_media`, `posta_upload_from_url`, `posta_list_accounts`, `posta_list_posts`, `posta_create_post`, `posta_create_post_from_file`, `posta_get_post`, `posta_update_post`, `posta_delete_post`, `posta_cancel_post`, `posta_schedule_post`, `posta_publish_post`, `posta_get_media`, `posta_generate_carousel_pdf`, `posta_generate_text_carousel_pdf`, `posta_get_analytics_overview`, `posta_get_best_times`, `posta_get_plan`, `posta_discover_credentials`, `fal_validate_key`

### Reference Docs

- [Posta API Reference](references/posta-api-reference.md) — Full REST API documentation
- [Content Generation Patterns](references/content-generation.md) — fal.ai image generation usage
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

**Reschedule an already-scheduled post:**
The API only allows scheduling posts in draft status. To reschedule, cancel first, then schedule again:
```bash
posta_cancel_post "$POST_ID"
posta_schedule_post "$POST_ID" "2026-03-16T09:00:00Z"
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

### 5. Generate Images (fal.ai)

Write captions and hashtags yourself — you are Claude, no text-generation API is involved. The only external generation service is the image generator below.

**Generate an image with fal.ai (FLUX):**
```bash
# fal returns a hosted image URL (JSON), not raw bytes
RESULT=$(curl -s -X POST "https://fal.run/fal-ai/flux/schnell" \
  -H "Authorization: Key ${FAL_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "your descriptive prompt, photorealistic, natural colors, high quality, detailed",
    "image_size": "square_hd",
    "num_images": 1
  }')

IMAGE_URL=$(echo "$RESULT" | jq -r '.images[0].url')
CONTENT_TYPE=$(echo "$RESULT" | jq -r '.images[0].content_type // "image/jpeg"')

# Upload the hosted image straight to Posta
MEDIA_ID=$(posta_upload_from_url "$IMAGE_URL" "$CONTENT_TYPE")
```

> `image_size`: `square_hd` (1024², feed), `portrait_16_9` (Stories/Reels/TikTok), `landscape_16_9` (LinkedIn/X). Use `fal-ai/flux/dev` for higher quality, `fal-ai/flux/schnell` for speed.

See [content-generation.md](references/content-generation.md) for image-generation details and prompt tips.

### 6. Build LinkedIn Carousels

LinkedIn carousels are multi-page PDF "documents". Posta generates the PDF for you and returns a normal media id — attach that id to a LinkedIn post and Posta publishes it via LinkedIn's Documents API automatically (no special post flag needed).

**From existing images** — each uploaded image becomes one page, in array order:
```bash
# media_ids: a JSON array of already-uploaded image media ids, in page order
CAROUSEL=$(posta_generate_carousel_pdf '["media-uuid-1","media-uuid-2","media-uuid-3"]' "My Carousel Title")

CAROUSEL_MEDIA_ID=$(echo "$CAROUSEL" | jq -r '.media_id')
PAGE_COUNT=$(echo "$CAROUSEL" | jq -r '.page_count')
```

**Text carousel** — each slide is a title + body composited over a background image (Professional plan). `logo_media_id` is optional (watermark on every page):
```bash
CAROUSEL=$(posta_generate_text_carousel_pdf '{
  "slides": [
    {"media_id": "bg-uuid-1", "title": "Hook",    "body": "Why this matters"},
    {"media_id": "bg-uuid-2", "title": "Point 1", "body": "Detail here"},
    {"media_id": "bg-uuid-3", "title": "CTA",     "body": "Follow for more"}
  ],
  "title": "5 lessons from launching Posta",
  "logo_media_id": "logo-uuid"
}')

CAROUSEL_MEDIA_ID=$(echo "$CAROUSEL" | jq -r '.media_id')
```

**Then post it** — attach the carousel media id like any other media:
```bash
POST=$(posta_create_post '{
  "caption": "Swipe through 👉",
  "hashtags": ["leadership", "startups"],
  "mediaIds": ["'"$CAROUSEL_MEDIA_ID"'"],
  "socialAccountIds": ["<linkedin-account-id>"],
  "isDraft": true
}')
```

Notes:
- The carousel is returned as a regular media id; Posta detects the PDF and routes it through LinkedIn's Documents API on publish.
- Best for LinkedIn (also works on Facebook). Image-only platforms like Instagram can't take a PDF — use a normal multi-image post there instead.
- 2–20 slides works best; keep text short and high-contrast for mobile.
- For text carousels, generate background images first (fal.ai, section 5), upload them, then pass their media ids as slide backgrounds.

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

3. **Ask before spending API credits.** Image generation (fal.ai) costs money. Confirm with the user before making image-generation calls. (Captions and hashtags are written by you, Claude — no cost, no external text API.)

4. **Handle errors gracefully.** If an API call fails, show the error message and suggest next steps (check credentials, verify account connection, check plan limits).

5. **Respect plan limits.** Check the user's plan with `posta_get_plan` before attempting operations that may exceed limits (posts, accounts, storage).

6. **Use appropriate aspect ratios.** Match the content format to the target platform — portrait for TikTok/Reels, square for Instagram feed, landscape for LinkedIn/X.

7. **Create posts as drafts first.** Always set `isDraft: true` when creating posts, then schedule or publish after user confirmation.

8. **Combine media types strategically.** For maximum reach, generate both an image (for Instagram/LinkedIn) and a video (for TikTok/Reels) from the same content.

9. **Preview generated images before uploading.** fal.ai returns a hosted image URL — download it to a temp file (`curl -s "$IMAGE_URL" -o /tmp/preview.jpg`) and use the Read tool to preview it visually before uploading to Posta. This prevents wasted uploads and media quota.

10. **Use `posta_create_post_from_file` for multiline captions.** Write the caption to a temp file and use the file-based helper instead of trying to embed multiline text in JSON strings. This avoids escaping issues.

11. **Always generate hashtags for posts.** When creating a post, always include relevant hashtags in the `hashtags` array. Generate 5–10 hashtags based on the caption content, target platform, and topic. Mix broad reach tags (e.g. #AI, #Marketing) with niche tags (e.g. #LaborMarket, #FutureOfWork). Do not wait for the user to ask — hashtags should be included by default on every post.

12. **Use `/tmp/.posta_last_response` for captured output.** When capturing `posta_api` output in a variable with `$()`, avoid using `echo` to re-output it — macOS echo corrupts `\n` in JSON strings. Instead pipe directly (`posta_api ... | jq`) or read from the file (`jq ... /tmp/.posta_last_response`).

13. **Check post status before scheduling.** The `posta_schedule_post` API only accepts posts in `draft` status. When rescheduling or scheduling an existing post, always fetch the post first with `posta_get_post` to check its status. If the post is already `scheduled`, cancel it first with `posta_cancel_post` to return it to draft, then schedule it to the new time. Never blindly call `posta_schedule_post` without confirming the post is in draft status.
