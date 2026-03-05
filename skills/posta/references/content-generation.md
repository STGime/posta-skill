# AI Content Generation Patterns

## Image Generation — Fireworks.ai SDXL

Generate images using Stable Diffusion XL via Fireworks.ai.

**Endpoint:** `https://api.fireworks.ai/inference/v1/image_generation/accounts/fireworks/models/stable-diffusion-xl-1024-v1-0`

**Required:** `FIREWORKS_API_KEY` environment variable.

- **Get a key:** Sign up at https://fireworks.ai and create an API key at https://fireworks.ai/account/api-keys
- **Key format:** Keys start with `fw_` (e.g. `fw_abc123...`)
- **Auto-discovery:** The skill searches env vars, `.env.development`, `~/.zshrc`, `~/.bashrc`, and `~/.posta/credentials`
- **Validation:** Run `fireworks_validate_key` to test your key before generating images

**Error handling:**
```bash
# Validate before spending credits
fireworks_validate_key || { echo "Fix your Fireworks key first"; exit 1; }
```

### Request

```bash
curl -s -X POST \
  "https://api.fireworks.ai/inference/v1/image_generation/accounts/fireworks/models/stable-diffusion-xl-1024-v1-0" \
  -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: image/png" \
  -d '{
    "prompt": "your prompt here, photorealistic, natural colors, proper white balance, vivid but not oversaturated, clean lighting, high quality, detailed, subtle background",
    "negative_prompt": "text, words, letters, numbers, watermark, logo, blurry, low quality, distorted, ugly, deformed, sepia, brown tint, yellow tint, monochromatic, desaturated, faded colors, vintage filter",
    "width": 1024,
    "height": 1024,
    "steps": 30,
    "guidance_scale": 7.5,
    "seed": 12345
  }' \
  --output generated_image.png
```

**Response:** Raw PNG binary (set `Accept: image/png`).

### Dimensions by Aspect Ratio

| Aspect Ratio | Width | Height | Use Case |
|-------------|-------|--------|---------------------|
| square | 1024 | 1024 | Instagram feed |
| portrait | 768 | 1344 | TikTok, Reels, Stories |
| landscape | 1344 | 768 | LinkedIn, X/Twitter |

### Prompt Tips
- Append quality modifiers: "photorealistic, natural colors, proper white balance, high quality, detailed"
- Use negative prompts to avoid text, watermarks, and color distortion
- `guidance_scale` of 7.0-8.0 works well for most prompts
- Vary `seed` for different results from the same prompt

---

## Text Generation — Gemini

Generate captions, hashtags, and post copy using Google Gemini.

**Required:** `GEMINI_API_KEY` environment variable.

### Caption Generation

```bash
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{
        "text": "Write a social media caption for an Instagram post about [topic]. Keep it engaging, use a conversational tone, and include a call to action. Max 200 words."
      }]
    }],
    "generationConfig": {
      "temperature": 0.8,
      "maxOutputTokens": 500
    }
  }'
```

**Response:**
```json
{
  "candidates": [{
    "content": {
      "parts": [{ "text": "Generated caption text..." }]
    }
  }]
}
```

### Hashtag Generation

```bash
curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{
      "parts": [{
        "text": "Generate 15-20 relevant hashtags for a social media post about [topic]. Mix popular and niche hashtags. Return as a JSON array of strings without the # symbol."
      }]
    }],
    "generationConfig": {
      "temperature": 0.6,
      "maxOutputTokens": 300
    }
  }'
```

---

## Text Generation — OpenAI

Alternative text generation using OpenAI.

**Required:** `OPENAI_API_KEY` environment variable.

### Caption Generation

```bash
curl -s -X POST "https://api.openai.com/v1/chat/completions" \
  -H "Authorization: Bearer ${OPENAI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-4o-mini",
    "messages": [
      {
        "role": "system",
        "content": "You are a social media content expert. Generate engaging captions optimized for the specified platform."
      },
      {
        "role": "user",
        "content": "Write an Instagram caption about [topic]. Include emojis, a hook in the first line, and a call to action."
      }
    ],
    "temperature": 0.8,
    "max_tokens": 500
  }'
```

**Response:**
```json
{
  "choices": [{
    "message": {
      "content": "Generated caption text..."
    }
  }]
}
```

---

## Combined Workflow: Generate Image + Caption + Post

Full workflow using bash helper functions:

```bash
# Source the helper
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# 1. Generate image with Fireworks
curl -s -X POST \
  "https://api.fireworks.ai/inference/v1/image_generation/accounts/fireworks/models/stable-diffusion-xl-1024-v1-0" \
  -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: image/png" \
  -d '{
    "prompt": "a beautiful sunset over mountains, photorealistic, vivid colors, high quality",
    "negative_prompt": "text, watermark, blurry, low quality",
    "width": 1024,
    "height": 1024,
    "steps": 30,
    "guidance_scale": 7.5
  }' \
  --output /tmp/generated_image.png

# 2. Upload to Posta
MEDIA_ID=$(posta_upload_media /tmp/generated_image.png "image/png")

# 3. Generate caption with Gemini
CAPTION=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{"parts": [{"text": "Write a short Instagram caption about a beautiful mountain sunset. Include emojis."}]}],
    "generationConfig": {"temperature": 0.8, "maxOutputTokens": 300}
  }' | jq -r '.candidates[0].content.parts[0].text')

# 4. Get connected accounts
ACCOUNTS=$(posta_list_accounts)
# Parse account IDs for target platforms

# 5. Create and schedule post
posta_create_post "{
  \"caption\": \"${CAPTION}\",
  \"hashtags\": [\"sunset\", \"mountains\", \"nature\", \"photography\"],
  \"mediaIds\": [\"${MEDIA_ID}\"],
  \"socialAccountIds\": [\"account-id-1\", \"account-id-2\"],
  \"isDraft\": false,
  \"scheduledAt\": \"2026-03-02T09:00:00Z\"
}"
```

---

## Platform-Specific Tips

| Platform | Best Image Size | Caption Length | Hashtag Limit |
|-----------|----------------|---------------|---------------|
| Instagram | 1080x1080 (feed), 1080x1920 (stories/reels) | 2200 chars | 30 |
| TikTok | 1080x1920 | 2200 chars | varies |
| X/Twitter | 1200x675 | 280 chars | 3-5 recommended |
| LinkedIn | 1200x627 | 3000 chars | 3-5 recommended |
| Facebook | 1200x630 | 63,206 chars | minimal |
| Pinterest | 1000x1500 | 500 chars | 20 |
| YouTube | 1280x720 (thumbnail) | 5000 chars | 500 chars total |
| Threads | 1080x1080 | 500 chars | minimal |
