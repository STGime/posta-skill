# Example Workflows

## 1. Upload Image and Post to Multiple Platforms

**User:** "Post this image to Instagram and Twitter"

**Claude's steps:**
1. Authenticate with Posta
2. List connected accounts to find Instagram and X/Twitter account IDs
3. Upload the image via the 3-step signed URL flow
4. Wait for processing to complete (poll media status)
5. Create the post with both account IDs
6. Show preview to user (caption, platforms, media)
7. On approval, publish immediately or schedule

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Get accounts
ACCOUNTS=$(posta_list_accounts)
# → Find Instagram account ID and X account ID

# Upload image
MEDIA_ID=$(posta_upload_media "/path/to/image.jpg" "image/jpeg")

# Create post as draft first
POST=$(posta_create_post '{
  "caption": "Check this out!",
  "hashtags": ["photo", "vibes"],
  "mediaIds": ["'"${MEDIA_ID}"'"],
  "socialAccountIds": ["instagram-id", "x-id"],
  "isDraft": true
}')

POST_ID=$(echo "$POST" | jq -r '.id')

# After user confirms, publish
posta_publish_post "$POST_ID"
```

---

## 2. View Best Performing Posts

**User:** "Show me my best performing posts this month"

**Claude's steps:**
1. Authenticate with Posta
2. Fetch analytics overview for the period
3. Fetch top posts sorted by engagements
4. Format into a readable table
5. Suggest insights (best day, best platform, best content type)

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Get overview stats
OVERVIEW=$(posta_get_analytics_overview "30d")

# Get top posts
TOP_POSTS=$(posta_api GET "/analytics/posts?limit=10&sortBy=engagements&sortOrder=desc")

# Get best times
BEST_TIMES=$(posta_get_best_times)

# Display to user as formatted tables
echo "$OVERVIEW" | jq '.'
echo "$TOP_POSTS" | jq '.items[] | {caption: .caption[:50], platform: .platform, engagements: .engagements, impressions: .impressions}'
```

---

## 3. Generate AI Image and Caption from Scratch

**User:** "Generate a social media post about spring flowers"

**Claude's steps:**
1. Generate an image using Fireworks SDXL with a spring flowers prompt
2. Generate a caption using Gemini or OpenAI
3. Generate relevant hashtags
4. Upload the image to Posta
5. Ask user which accounts to post to
6. Create the post

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Generate image
curl -s -X POST \
  "https://api.fireworks.ai/inference/v1/image_generation/accounts/fireworks/models/stable-diffusion-xl-1024-v1-0" \
  -H "Authorization: Bearer ${FIREWORKS_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "Accept: image/png" \
  -d '{
    "prompt": "vibrant spring flowers in a garden, cherry blossoms, tulips, daffodils, photorealistic, natural colors, proper white balance, high quality, detailed",
    "negative_prompt": "text, watermark, blurry, low quality, distorted",
    "width": 1024, "height": 1024, "steps": 30, "guidance_scale": 7.5
  }' --output /tmp/spring_flowers.png

# Upload to Posta
MEDIA_ID=$(posta_upload_media /tmp/spring_flowers.png "image/png")

# Generate caption with Gemini
CAPTION=$(curl -s -X POST \
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "contents": [{"parts": [{"text": "Write a cheerful Instagram caption about spring flowers arriving. Include 2-3 emojis and a call to action. Max 150 words."}]}],
    "generationConfig": {"temperature": 0.8}
  }' | jq -r '.candidates[0].content.parts[0].text')

# Show user for approval before posting
echo "Caption: ${CAPTION}"
echo "Image uploaded. Ready to create post."
```
