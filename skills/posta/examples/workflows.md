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
1. Generate an image using fal.ai (FLUX) with a spring flowers prompt
2. Write the caption and hashtags directly (you are Claude — no text API needed)
3. Upload the image to Posta
4. Ask user which accounts to post to
5. Create the post

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Generate image with fal.ai — returns a hosted URL, not raw bytes
RESULT=$(curl -s -X POST "https://fal.run/fal-ai/flux/schnell" \
  -H "Authorization: Key ${FAL_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "vibrant spring flowers in a garden, cherry blossoms, tulips, daffodils, photorealistic, natural colors, proper white balance, high quality, detailed",
    "image_size": "square_hd",
    "num_images": 1
  }')
IMAGE_URL=$(echo "$RESULT" | jq -r '.images[0].url')

# Upload the hosted image to Posta
MEDIA_ID=$(posta_upload_from_url "$IMAGE_URL" "image/jpeg")

# Write the caption yourself (you are Claude) — no external text API
CAPTION="Spring has sprung 🌸 Fresh blooms, fresh starts. What's the first flower you look for each spring?"

# Show user for approval before posting
echo "Caption: ${CAPTION}"
echo "Image: ${IMAGE_URL}"
```

---

## 4. Create Post with Multiline Caption

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

---

## 5. Build a LinkedIn Carousel

**User:** "Make a LinkedIn carousel from these 3 images" (or "...5 slides about our launch lessons")

**Claude's steps:**
1. Authenticate with Posta and find the LinkedIn account
2. Upload the source images (or generate backgrounds with fal.ai for a text carousel)
3. Generate the carousel PDF — Posta returns a normal media id
4. Attach the carousel media id to a LinkedIn post (Posta publishes it via LinkedIn's Documents API)
5. Preview, then schedule or publish

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/posta/scripts/posta-api.sh"

# Find LinkedIn account
ACCOUNTS=$(posta_list_accounts)
LINKEDIN_ID=$(echo "$ACCOUNTS" | jq -r '.[] | select(.platform == "linkedin") | .id | tostring')

# --- Option A: carousel from existing images (one page per image) ---
M1=$(posta_upload_media "/path/slide1.jpg" "image/jpeg")
M2=$(posta_upload_media "/path/slide2.jpg" "image/jpeg")
M3=$(posta_upload_media "/path/slide3.jpg" "image/jpeg")

CAROUSEL=$(posta_generate_carousel_pdf "[\"${M1}\",\"${M2}\",\"${M3}\"]" "Our launch in 3 slides")
CAROUSEL_MEDIA_ID=$(echo "$CAROUSEL" | jq -r '.media_id')

# --- Option B: text carousel (title+body over background images, Pro plan) ---
# Generate backgrounds with fal.ai, upload, then pass their ids as slide backgrounds:
# BG1=$(posta_upload_from_url "$(curl -s -X POST https://fal.run/fal-ai/flux/schnell \
#   -H "Authorization: Key ${FAL_KEY}" -H "Content-Type: application/json" \
#   -d '{"prompt":"abstract gradient, brand colors","image_size":"portrait_4_3"}' \
#   | jq -r '.images[0].url')" "image/jpeg")
# CAROUSEL=$(posta_generate_text_carousel_pdf '{
#   "slides": [
#     {"media_id": "'"${BG1}"'", "title": "Hook", "body": "Why this matters"},
#     {"media_id": "'"${BG1}"'", "title": "Lesson 1", "body": "Ship small, ship often"}
#   ],
#   "title": "5 lessons from launch",
#   "logo_media_id": "'"${LOGO_ID}"'"
# }')
# CAROUSEL_MEDIA_ID=$(echo "$CAROUSEL" | jq -r '.media_id')

# Attach the carousel to a LinkedIn post
POST=$(posta_create_post '{
  "caption": "We learned a lot launching. Swipe through 👉",
  "hashtags": ["startups", "buildinpublic", "lessons"],
  "mediaIds": ["'"${CAROUSEL_MEDIA_ID}"'"],
  "socialAccountIds": ["'"${LINKEDIN_ID}"'"],
  "isDraft": true
}')
POST_ID=$(echo "$POST" | jq -r '.id')

# Preview, then publish or schedule
posta_get_post "$POST_ID" | jq '{id, caption, status}'
posta_schedule_post "$POST_ID" "2026-03-10T09:00:00Z"
```

> The carousel is a regular media id — no special post flag. Posta detects the PDF and routes it through LinkedIn's Documents API on publish. Best for LinkedIn (also works on Facebook); image-only platforms like Instagram can't take a PDF.
