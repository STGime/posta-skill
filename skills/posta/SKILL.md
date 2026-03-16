---
name: posta
description: Use this skill when the user wants to create social media content, generate images/videos/text with AI, upload media, create posts, schedule or publish posts, view analytics, compare post performance, export analytics, discover platform specs and capabilities, manage media library, view content calendar, or manage social accounts through Posta.
license: MIT
homepage: https://github.com/STGime/posta-skill
metadata:
  author: Posta
  version: 1.1.0
  tags:
    - social-media
    - scheduling
    - analytics
    - content-generation
    - instagram
    - tiktok
    - twitter
    - linkedin
  clawdbot:
    requires:
      env:
        - POSTA_API_TOKEN
      bins:
        - curl
        - jq
    primaryEnv: POSTA_API_TOKEN
---

# Posta — Social Media Content & Scheduling

Posta is a social media management platform that lets you create, schedule, and publish posts across Instagram, TikTok, Facebook, X/Twitter, LinkedIn, YouTube, Pinterest, Threads, and Bluesky.

This skill enables you to interact with the Posta API to manage social media content end-to-end: authenticate, list accounts, upload media, create/schedule/publish posts, generate AI content, and view analytics.

## Setup

### Authentication (one of the following)

- `POSTA_API_TOKEN` — **Recommended.** Personal API token (starts with `posta_`). Long-lived, revocable, no password exposure.
- `POSTA_EMAIL` + `POSTA_PASSWORD` — Legacy login. The skill logs in and caches a JWT automatically.

If `POSTA_API_TOKEN` is set, email/password are not needed and the login flow is skipped entirely.

### Optional Environment Variables

- `POSTA_BASE_URL` — API base URL (default: `https://api.getposta.app/v1`)
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
source "${POSTA_SKILL_ROOT:-${OPENCLAW_SKILL_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}/skills/posta/scripts/posta-api.sh"
```

This provides:
- **Auth & Core:** `posta_login`, `posta_get_token`, `posta_api`, `posta_discover_credentials`
- **Media:** `posta_detect_mime`, `posta_upload_media`, `posta_upload_from_url`, `posta_list_media`, `posta_get_media`, `posta_delete_media`, `posta_generate_carousel_pdf`
- **Posts:** `posta_list_posts`, `posta_create_post`, `posta_create_post_from_file`, `posta_get_post`, `posta_update_post`, `posta_delete_post`, `posta_schedule_post`, `posta_publish_post`, `posta_cancel_post`, `posta_get_calendar`
- **Platform Discovery:** `posta_list_platforms`, `posta_get_platform_specs`, `posta_get_aspect_ratios`, `posta_get_platform`, `posta_get_pinterest_boards`
- **Analytics:** `posta_get_analytics_overview`, `posta_get_analytics_capabilities`, `posta_get_analytics_posts`, `posta_get_post_analytics`, `posta_get_analytics_trends`, `posta_get_best_times`, `posta_get_content_types`, `posta_get_hashtag_analytics`, `posta_compare_posts`, `posta_get_benchmarks`, `posta_export_analytics_csv`, `posta_export_analytics_pdf`, `posta_refresh_post_analytics`, `posta_refresh_all_analytics`
- **User:** `posta_get_plan`, `posta_get_profile`, `posta_update_profile`
- **Fireworks:** `fireworks_validate_key`

### Reference Docs

- [Posta API Reference](references/posta-api-reference.md) — Full REST API documentation
- [Content Generation Patterns](references/content-generation.md) — Fireworks/Gemini/OpenAI usage
- [Workflow Examples](examples/workflows.md) — Full example conversations

---

## Core Workflows

### 1. Authenticate

Authentication is automatic. If `POSTA_API_TOKEN` is set, the skill uses it directly — no login step needed. Otherwise it falls back to email/password login with JWT caching. If a request returns 401:
- **API token**: reports the token is invalid/revoked (no retry)
- **JWT**: re-authenticates and retries once

```bash
source "${POSTA_SKILL_ROOT:-${OPENCLAW_SKILL_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}}/skills/posta/scripts/posta-api.sh"
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

The upload flow has 3 steps: create signed URL → PUT binary → confirm upload. MIME type is auto-detected from the file — no need to specify it manually.

**From a local file (auto-detect MIME):**
```bash
MEDIA_ID=$(posta_upload_media "/path/to/file.jpg")
```

**From a local file (explicit MIME):**
```bash
MEDIA_ID=$(posta_upload_media "/path/to/file.jpg" "image/jpeg")
```

**From a URL (auto-detect from extension):**
```bash
MEDIA_ID=$(posta_upload_from_url "https://example.com/image.png")
```

**Detect MIME type separately:**
```bash
MIME=$(posta_detect_mime "/path/to/file.mp4")
# Returns: video/mp4
```

**Supported formats:**
- Images: `image/jpeg`, `image/png`, `image/webp`, `image/gif` (max 20MB)
- Videos: `video/mp4`, `video/quicktime`, `video/webm` (max 500MB)

After upload, the media enters `processing` status. For images this is fast (thumbnails/variants). For videos it takes longer. Check status with:
```bash
posta_get_media "$MEDIA_ID"
```

**List media library:**
```bash
ALL_MEDIA=$(posta_list_media)
IMAGES_ONLY=$(posta_list_media "image")
COMPLETED=$(posta_list_media "" "completed" 50)
```

**Delete media:**
```bash
posta_delete_media "$MEDIA_ID"
```

**Generate carousel PDF from images:**
```bash
RESULT=$(posta_generate_carousel_pdf '["media-id-1", "media-id-2", "media-id-3"]' "My Carousel Title")
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
POST=$(posta_create_post_from_file /tmp/caption.txt '["media-uuid"]' '["35", "42"]' true '["tag1", "tag2"]')
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

### 6. View Analytics

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

### 7. Platform Discovery

Query platform capabilities, character limits, media requirements, and supported features before creating posts.

**List all supported platforms:**
```bash
posta_list_platforms
```

**Get full specs (char limits, media requirements, features):**
```bash
SPECS=$(posta_get_platform_specs)
```

**Get specs for a specific platform:**
```bash
posta_get_platform "instagram"
```

**Get aspect ratio reference:**
```bash
posta_get_aspect_ratios
```

**Get Pinterest boards for a connected account:**
```bash
BOARDS=$(posta_get_pinterest_boards "$ACCOUNT_ID")
```

Use platform discovery to validate content before posting — check character limits, required media dimensions, and supported post types.

### 8. Calendar View

View scheduled and posted content on a calendar:
```bash
CALENDAR=$(posta_get_calendar "2026-03-01" "2026-03-31")
echo "$CALENDAR" | jq '.items[] | {id, caption: .caption[:50], status, scheduledAt}'
```

### 9. Extended Analytics

**Analytics capabilities (what your plan supports):**
```bash
posta_get_analytics_capabilities
```

**Top performing posts (sorted, paginated):**
```bash
TOP=$(posta_get_analytics_posts 10 0 "engagements" "desc")
```

**Single post analytics:**
```bash
posta_get_post_analytics "$POST_ID"
```

**Trends over time with custom period:**
```bash
TRENDS=$(posta_get_analytics_trends "90d" "engagement_rate")
```

**Content type performance breakdown:**
```bash
posta_get_content_types
```

**Hashtag performance (pro plan):**
```bash
posta_get_hashtag_analytics
```

**Compare posts side by side (2-4 posts, pro plan):**
```bash
posta_compare_posts "post-id-1,post-id-2,post-id-3"
```

**Engagement benchmarks (pro plan):**
```bash
posta_get_benchmarks
```

**Export analytics:**
```bash
posta_export_analytics_csv "30d"
posta_export_analytics_pdf "90d"
```

**Refresh analytics:**
```bash
posta_refresh_post_analytics "$POST_RESULT_ID"
posta_refresh_all_analytics  # Rate limited: 1 per hour
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

13. **Use platform discovery for validation.** Before creating posts for unfamiliar platforms, call `posta_get_platform_specs` or `posta_get_platform "<platform>"` to check character limits, required media dimensions, and supported features. This prevents failed posts due to platform constraints.

14. **Auto MIME detection for uploads.** When uploading media, you can omit the MIME type parameter — `posta_upload_media` and `posta_upload_from_url` auto-detect it from the file content or extension. Only specify MIME type manually when the auto-detection might be wrong (e.g., `.bin` files).

15. **Always set TikTok privacy level.** When creating posts that include TikTok, you MUST include `platformConfigurations.tiktok.privacyLevel` — TikTok requires it and publishing will fail without it. Use `"PUBLIC_TO_EVERYONE"` unless the user specifies otherwise. Valid values: `PUBLIC_TO_EVERYONE`, `MUTUAL_FOLLOW_FRIENDS`, `SELF_ONLY`, `FOLLOWER_OF_CREATOR`.
