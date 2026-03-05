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

# Get account IDs (integers) and convert to strings for socialAccountIds
INSTA_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "instagram") | .id | tostring')
X_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "x") | .id | tostring')

# Create post as draft first
POST=$(posta_create_post '{
  "caption": "Check this out!",
  "hashtags": ["photo", "vibes"],
  "mediaIds": ["'"${MEDIA_ID}"'"],
  "socialAccountIds": ["'"${INSTA_ID}"'", "'"${X_ID}"'"],
  "isDraft": true
}')

POST_ID=$(echo "$POST" | jq -r '.id')

# After user confirms, publish
posta_publish_post "$POST_ID"
```

---

## 2. Generate Stupid Correlation and Schedule

**User:** "Generate a stupid correlation and schedule it for tomorrow at 9am on all accounts"

**Claude's steps:**
1. Authenticate with Posta
2. List accounts to get all active account IDs
3. Call statapp `/api/generate/random` with appropriate aspect ratio
4. Display the generated correlation (headline, caption, image) to user
5. Upload the generated image to Posta
6. Create post with the generated caption and hashtags
7. Schedule for tomorrow at 9:00 AM in the user's timezone

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Get all accounts
ACCOUNTS=$(posta_list_accounts)
# Account IDs are integers — convert to string array for socialAccountIds
ACCOUNT_IDS_JSON=$(echo "$ACCOUNTS" | jq '[.[].id | tostring]')

# Generate correlation (square for multi-platform)
CORRELATION=$(statapp_generate_random "square" "classic" false)

IMAGE_URL=$(echo "$CORRELATION" | jq -r '.image.url')
HEADLINE=$(echo "$CORRELATION" | jq -r '.caption.headline')
CAPTION_TEXT=$(echo "$CORRELATION" | jq -r '.caption.caption')

# Show user the result for confirmation
echo "Generated: ${HEADLINE}"
echo "Caption: ${CAPTION_TEXT}"
echo "Image: ${IMAGE_URL}"

# Upload to Posta
MEDIA_ID=$(posta_upload_from_url "$IMAGE_URL" "image/png")

# Create and schedule — use file helper for multiline captions
echo "${CAPTION_TEXT}" > /tmp/posta_caption.txt
POST=$(posta_create_post_from_file /tmp/posta_caption.txt "[\"${MEDIA_ID}\"]" "$ACCOUNT_IDS_JSON" true)

POST_ID=$(echo "$POST" | jq -r '.id')
posta_schedule_post "$POST_ID" "2026-03-02T09:00:00Z"
```

---

## 3. View Best Performing Posts

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

## 4. Create Portrait Video for TikTok

**User:** "Create a video correlation for TikTok and schedule it for Friday at 6pm"

**Claude's steps:**
1. Authenticate with Posta
2. Find the TikTok account
3. Generate correlation with portrait aspect ratio and video
4. Show preview (headline, caption, image thumbnail)
5. Upload video to Posta
6. Create post with TikTok platform configuration
7. Schedule for Friday at 6pm

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Find TikTok account
ACCOUNTS=$(posta_list_accounts)
# Account IDs are integers — convert to string
TIKTOK_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "tiktok") | .id | tostring')

# Generate with video (portrait for TikTok)
RESULT=$(statapp_generate_random "portrait" "neon" true)

VIDEO_URL=$(echo "$RESULT" | jq -r '.video.url')
CAPTION_TEXT=$(echo "$RESULT" | jq -r '.caption.caption')

# Upload video to Posta
MEDIA_ID=$(posta_upload_from_url "$VIDEO_URL" "video/mp4")

# Create post with TikTok config
POST=$(posta_create_post '{
  "caption": "'"${CAPTION_TEXT}"'",
  "hashtags": ["stupidcorrelations", "data", "funfacts", "statistics", "correlation"],
  "mediaIds": ["'"${MEDIA_ID}"'"],
  "socialAccountIds": ["'"${TIKTOK_ID}"'"],
  "isDraft": true,
  "platformConfigurations": {
    "tiktok": {
      "privacyLevel": "PUBLIC_TO_EVERYONE",
      "allowComment": true,
      "allowDuet": false,
      "allowStitch": false
    }
  }
}')

POST_ID=$(echo "$POST" | jq -r '.id')

# Schedule for Friday at 6pm
posta_schedule_post "$POST_ID" "2026-03-06T18:00:00Z"
```

---

## 5. Batch Generate Marketing Videos and Schedule Them

**User:** "Generate 5 marketing videos and schedule them across the week"

**Claude's steps:**
1. Run the `create-promo-videos.js` script on the statapp server to generate 5 videos
2. Authenticate with Posta and list accounts
3. Upload each video to Posta
4. Create posts with generated captions and schedule across the week at optimal times
5. Show preview of the full schedule for confirmation

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Step 1: Generate 5 promo videos (run on statapp server)
cd ~/statapp_backend
node scripts/create-promo-videos.js 5
# Output: promo-videos/promo_1_*.mp4, promo_2_*.mp4, etc.

# Step 2: Get best posting times from Posta analytics
BEST_TIMES=$(posta_get_best_times)

# Step 3: Get TikTok account
ACCOUNTS=$(posta_list_accounts)
# Account IDs are integers — convert to string
TIKTOK_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "tiktok") | .id | tostring')

# Step 4: Upload each video and schedule
for video in ~/statapp_backend/promo-videos/promo_*.mp4; do
  MEDIA_ID=$(posta_upload_media "$video" "video/mp4")

  POST=$(posta_create_post '{
    "caption": "Mind-blowing correlation! 🤯📊 #stupidcorrelations #data #funfacts",
    "hashtags": ["stupidcorrelations", "data", "statistics", "correlation", "funfacts"],
    "mediaIds": ["'"${MEDIA_ID}"'"],
    "socialAccountIds": ["'"${TIKTOK_ID}"'"],
    "isDraft": true,
    "platformConfigurations": {
      "tiktok": { "privacyLevel": "PUBLIC_TO_EVERYONE", "allowComment": true }
    }
  }')

  POST_ID=$(echo "$POST" | jq -r '.id')
  # Schedule at optimal time (calculate per day)
  posta_schedule_post "$POST_ID" "2026-03-03T18:00:00Z"
done
```

---

## 6. Generate AI Image and Caption from Scratch

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

---

## 7. Create Post with Multiline Caption

**User:** "Create a LinkedIn post about EU data sovereignty with a detailed caption"

**Claude's steps:**
1. Write the multiline caption to a temp file
2. Use `posta_create_post_from_file` to handle escaping correctly
3. Manage the post lifecycle with get/update/delete helpers

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Get LinkedIn account (IDs are integers, convert to string)
ACCOUNTS=$(posta_list_accounts)
LINKEDIN_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "linkedin") | .id | tostring')

# Write multiline caption to file (avoids JSON escaping issues)
cat > /tmp/caption.txt << 'EOF'
The EU is taking a bold stance on data sovereignty.

Here's what every tech leader needs to know:

1. New regulations require EU data to stay in EU infrastructure
2. Cloud providers must offer EU-only deployment options
3. Compliance deadlines are approaching fast

What's your company's strategy? Drop a comment below.
EOF

# Upload media
MEDIA_ID=$(posta_upload_media /tmp/eu_data.png "image/png")

# Create post from file — handles all escaping correctly
POST=$(posta_create_post_from_file /tmp/caption.txt "[\"${MEDIA_ID}\"]" "[\"${LINKEDIN_ID}\"]" true)
POST_ID=$(echo "$POST" | jq -r '.id')

# Review the created post
posta_get_post "$POST_ID" | jq '{id, caption, status}'

# Update caption if needed
posta_update_post "$POST_ID" '{"hashtags": ["datasovereignty", "EU", "cloud", "tech"]}'

# After user confirms, schedule
posta_schedule_post "$POST_ID" "2026-03-06T09:00:00Z"

# Or if user changes mind, delete
# posta_delete_post "$POST_ID"
```
