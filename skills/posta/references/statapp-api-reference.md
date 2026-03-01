# Stupid Correlations (statapp) API Reference

Base URL: `${STATAPP_URL}` (set via environment variable)

---

## Authentication

Statapp uses Firebase-based authentication. The plugin handles login and token caching automatically.

### Required Environment Variables

- `STATAPP_URL` — Base URL of your statapp instance
- `STATAPP_EMAIL` — Your statapp account email
- `STATAPP_PASSWORD` — Your statapp account password

### Required Headers

All requests must include:
- `Authorization: Bearer <firebase_token>` — Authentication token (obtained via login)
- `X-Device-Id: <device_id>` — Device identifier for rate limiting and premium tracking

The helper script manages both automatically:
```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"
statapp_api GET "/api/generate/styles"
```

### Rate Limits

- Free tier: limited daily generations (counter resets daily)
- Premium: higher daily limits
- Rate limiting is tracked per device ID

---

## Generate Random Correlation

### POST `/api/generate/random`

Generate a random correlation with composite image and optional video.

**Body:**
```json
{
  "aspectRatio": "portrait|square|landscape",
  "chartStyle": "classic|neon|minimal",
  "includeVideo": false
}
```

**Defaults:** `aspectRatio: "square"`, `chartStyle: "classic"`, `includeVideo: false`

**Aspect Ratio Dimensions:**
| Ratio | Width | Height | Best For |
|-----------|-------|--------|----------------------|
| portrait | 768 | 1344 | TikTok, Reels, Stories |
| square | 1024 | 1024 | Instagram Feed |
| landscape | 1344 | 768 | LinkedIn, X/Twitter |

**Response 200:**
```json
{
  "success": true,
  "galleryId": "uuid",
  "correlation": {
    "datasetA": { "id": "string", "name": "string", "source": "string" },
    "datasetB": { "id": "string", "name": "string", "source": "string" },
    "coefficient": 0.95,
    "percentage": "95%",
    "strength": "very strong",
    "direction": "positive"
  },
  "caption": {
    "headline": "string — catchy one-liner",
    "caption": "string — social media caption",
    "expertQuote": "string — funny fake expert quote",
    "expertName": "string — fake expert name and title"
  },
  "image": {
    "url": "https://storage.../composite.png",
    "fileId": "string",
    "aspectRatio": "square"
  },
  "background": {
    "url": "https://storage.../background.png",
    "fileId": "string"
  },
  "video": null,
  "remaining": 5
}
```

When `includeVideo: true`, the `video` field contains `{ "url": "https://...", "fileId": "string" }`.

---

## Generate Custom Correlation (Premium)

### POST `/api/generate/custom`

Generate a correlation with user-selected datasets.

**Body:**
```json
{
  "datasetA": "dataset-id-1",
  "datasetB": "dataset-id-2",
  "aspectRatio": "square",
  "chartStyle": "classic"
}
```

**Response:** Same shape as `/random`.

---

## Regenerate Caption

### POST `/api/generate/regenerate-joke`

Get a new caption for an existing correlation.

**Body:** `{ "datasetAId": "string", "datasetBId": "string" }`

**Response 200:**
```json
{
  "success": true,
  "caption": {
    "headline": "string",
    "caption": "string",
    "expertQuote": "string",
    "expertName": "string"
  },
  "remaining": 4
}
```

---

## Regenerate Background

### POST `/api/generate/regenerate-background`

Generate a new AI background image for an existing correlation.

**Body:** `{ "datasetAId": "string", "datasetBId": "string", "aspectRatio": "square" }`

**Response 200:**
```json
{
  "success": true,
  "background": {
    "url": "https://...",
    "fileId": "string",
    "prompt": "string — the image generation prompt used"
  },
  "remaining": 4
}
```

---

## Create Animation Video (Async)

### POST `/api/generate/animate`

Queue a video animation job. Returns immediately with a job ID.

**Headers:** `X-Device-Id: <device-id>` (required)

**Body:**
```json
{
  "galleryId": "uuid (optional — link video to existing gallery item)",
  "datasetAId": "string",
  "datasetBId": "string",
  "backgroundUrl": "https://... (required — URL of background image)",
  "caption": {
    "headline": "string (required)",
    "caption": "string (required)",
    "expertQuote": "string",
    "expertName": "string"
  },
  "aspectRatio": "portrait|square|landscape",
  "chartStyle": "classic|neon|minimal"
}
```

**Response 200:**
```json
{
  "success": true,
  "jobId": "uuid",
  "status": "pending",
  "message": "Video generation queued. Call /api/generate/animate/status/:jobId?wait=true to process."
}
```

### GET `/api/generate/animate/status/:jobId`

Check video job status. Use `?wait=true` for long-polling (triggers processing and waits up to 3 minutes).

**Headers:** `X-Device-Id: <device-id>` (required)

**Query:** `wait=true` to trigger processing and wait for completion.

**Response 200 (pending/processing):**
```json
{
  "jobId": "uuid",
  "status": "pending|processing",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601"
}
```

**Response 200 (completed):**
```json
{
  "jobId": "uuid",
  "status": "completed",
  "video": { "url": "https://..." },
  "galleryId": "uuid|null",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601"
}
```

**Response 200 (failed):**
```json
{
  "jobId": "uuid",
  "status": "failed",
  "error": "error message",
  "createdAt": "ISO8601",
  "updatedAt": "ISO8601"
}
```

---

## Available Styles

### GET `/api/generate/styles`

Get available chart styles and aspect ratio options.

**Response 200:**
```json
{
  "chartStyles": ["classic", "neon", "minimal"],
  "aspectRatios": {
    "square": { "width": 1024, "height": 1024, "name": "Instagram Square" },
    "portrait": { "width": 768, "height": 1344, "name": "TikTok/Stories" },
    "landscape": { "width": 1344, "height": 768, "name": "LinkedIn/Twitter" }
  }
}
```

---

---

## Batch Marketing Video Generation (Server-Side Scripts)

Statapp includes Node.js scripts for generating marketing videos in bulk. These run directly on the server (not via API) and produce 9:16 portrait videos optimized for TikTok, Reels, and Shorts.

**Location:** `statapp_backend/scripts/`

### Available Scripts

| Script | Description | Output |
|--------|-------------|--------|
| `generate-marketing-videos.js` | 10 curated correlations, no outro | `marketing-videos/` |
| `generate-marketing-videos-batch2.js` | 10 more correlations, with outro | `marketing-videos/` |
| `generate-marketing-videos-batch3.js` | 10 more correlations, with outro | `marketing-videos/` |
| `create-promo-videos.js [count]` | N random correlations, with outro | `promo-videos/` |
| `add-outro-to-videos.js` | Adds branded outro to existing videos | in-place |

### Usage

```bash
cd statapp_backend

# Generate 10 curated marketing videos
node scripts/generate-marketing-videos.js

# Generate N random promo videos
node scripts/create-promo-videos.js 5

# Add branded outro to all existing marketing videos
node scripts/add-outro-to-videos.js
```

### Video Pipeline (what the scripts do internally)

1. Load correlation data (curated pairs or random)
2. Generate captions via LLM (headline, caption, expert quote)
3. Synthesize narration audio via TTS
4. Generate AI background image (Fireworks SDXL, 768x1344 portrait)
5. Render animated chart video with text overlays (FFmpeg + Canvas)
6. Optionally concatenate 8-second branded outro with:
   - Animated particles/sparkles
   - CTA: "Create your own!"
   - URL: "stupidcorrelations.app"
   - Uptempo beat (128 BPM)
   - Brand colors: `#FF6B6B` (red) + `#4ECDC4` (teal)

### Output Format

- Resolution: 768x1344 (9:16 portrait)
- Codec: H.264 + AAC audio
- FPS: 10
- Duration: ~5s content + 8s outro
- Files: `marketing_N_datasetA_vs_datasetB.mp4`

---

## Typical Workflow: Generate + Post to Posta

1. `POST /api/generate/random` with `{ aspectRatio: "portrait", includeVideo: true }` → get image URL and video URL
2. Upload image to Posta: `posta_upload_from_url <image_url> "image/png"`
3. Upload video to Posta: `posta_upload_from_url <video_url> "video/mp4"`
4. Create post in Posta with the uploaded media IDs and generated caption
5. Schedule or publish

For async video (faster initial response):
1. `POST /api/generate/random` with `{ includeVideo: false }` → get image + correlation data
2. `POST /api/generate/animate` with correlation data → get `jobId`
3. `GET /api/generate/animate/status/:jobId?wait=true` → wait for video
4. Upload both to Posta and create post
