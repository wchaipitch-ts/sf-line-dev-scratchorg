# 04 — LINE Messaging API Reference (what this build uses)

Official reference: https://developers.line.biz/en/reference/messaging-api/
Everything marked **[VERIFY]** must be re-checked there before relying on it (fetch the page with WebFetch).

## 1. Authentication — stateless channel access token [VERIFY]

```
POST https://api.line.me/oauth2/v3/token
Content-Type: application/x-www-form-urlencoded

grant_type=client_credentials&client_id={Channel ID}&client_secret={Channel Secret}
```
Response:
```json
{ "token_type": "Bearer", "access_token": "eyJ...", "expires_in": 900 }
```
- Valid ~15 minutes, cannot be revoked. Issue on demand; cache per channel for ≤ 10 min.
- Use as `Authorization: Bearer {access_token}` on all calls below.
- URL-encode `client_secret` (`EncodingUtil.urlEncode(secret, 'UTF-8')`).

## 2. Webhook (LINE → Salesforce)

Headers: `X-Line-Signature: <base64 HMAC-SHA256 of raw body using channel secret>`, `Content-Type: application/json`.

### Signature check (Apex)
```apex
Blob mac = Crypto.generateMac('hmacSHA256', RestContext.request.requestBody, Blob.valueOf(channelSecret));
Boolean ok = EncodingUtil.base64Encode(mac) == signatureHeader;
```
- Use the **raw** `requestBody` Blob, never a re-serialized string.
- Header name case may vary: look it up case-insensitively in `RestContext.request.headers`.

### Body shape
```json
{
  "destination": "Uxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
  "events": [
    {
      "type": "message",
      "mode": "active",
      "timestamp": 1758000000000,
      "webhookEventId": "01J...",
      "deliveryContext": { "isRedelivery": false },
      "source": { "type": "user", "userId": "Uyyyyyyyy..." },
      "replyToken": "abc...",
      "message": { "id": "4680000000000", "type": "text", "text": "สวัสดีครับ", "quoteToken": "..." }
    }
  ]
}
```
- `destination` = bot user ID of the receiving OA → `LINE_OA_Configuration__c.Bot_User_Id__c`.
- One request can contain multiple events; may be empty (`"events": []`) for the console "Verify" button → return 200.
- Handle only `source.type = "user"`. Ignore `group`/`room`.
- `mode = "standby"` → ignore (another module owns the chat) [VERIFY whether relevant].

### Event types to handle

| `type` | Action |
|---|---|
| `message` | Store message (see types below) |
| `follow` | Upsert LINE_Conversation__c, Status Following, fetch profile. `follow.isUnblocked` true = re-follow |
| `unfollow` | Status Unfollowed (no replyToken) |
| others (`postback`, `join`, `leave`, `memberJoined`, `unsend`, `videoPlayComplete`, `beacon`, `accountLink`, `things`) | Ignore for now. Consider `unsend` later (customer deleted a message). |

### Message types (`message.type`)

| type | Useful fields | Content download? |
|---|---|---|
| `text` | `text`, `emojis`, `mention`, `quotedMessageId` | no |
| `image` | `contentProvider.type` (`line`/`external`), `imageSet` | yes if `line` |
| `video` | `duration`, `contentProvider` | yes if `line` |
| `audio` | `duration`, `contentProvider` | yes if `line` |
| `file` | `fileName`, `fileSize` | yes |
| `sticker` | `packageId`, `stickerId`, `stickerResourceType`, `keywords` | no — render via sticker CDN URL or show "[Sticker]" [VERIFY CDN URL pattern; optional] |
| `location` | `title`, `address`, `latitude`, `longitude` | no |

## 3. Endpoints used

| Purpose | Method & URL | Notes |
|---|---|---|
| Bot info (registration) | `GET https://api.line.me/v2/bot/info` | Returns `userId` (= destination), `basicId`, `displayName`, `pictureUrl`, `chatMode`, `markAsReadMode` |
| Set webhook URL | `PUT https://api.line.me/v2/bot/channel/webhook/endpoint` body `{"endpoint":"https://..."}` | "Use webhook" toggle still has to be ON in the LINE Developers Console [VERIFY] |
| Test webhook | `POST https://api.line.me/v2/bot/channel/webhook/test` body `{"endpoint":"..."}` (optional) | Returns `success`, `statusCode`, `reason` |
| Get profile | `GET https://api.line.me/v2/bot/profile/{userId}` | `displayName`, `pictureUrl`, `statusMessage`, `language`. Works for users who added the OA. |
| Push message | `POST https://api.line.me/v2/bot/message/push` | Header `X-Line-Retry-Key: <UUID>` for safe retry (409 = already accepted) |
| Get content | `GET https://api-data.line.me/v2/bot/message/{messageId}/content` | Binary body. Content is deleted by LINE after a period → download promptly [VERIFY retention]. Large video content may not be ready at once (see "get content transcoding status") [VERIFY]. |
| Reply message | `POST https://api.line.me/v2/bot/message/reply` body `{"replyToken":"...","messages":[...]}` | **Free** (doesn't use quota). The reply token is single-use and expires shortly after the event [VERIFY validity]. Used only for the invite confirmation/expired-code replies. If it fails, skip it; never fall back to push. |
| Quota | `GET https://api.line.me/v2/bot/message/quota` and `/v2/bot/message/quota/consumption` | Shown per OA in `lineAdmin` |

### LINE URL scheme for QR invites [VERIFY]
```
https://line.me/R/oaMessage/{basicId}/?{url-encoded text}
```
Opens a chat with the OA (offering to add it as a friend first if needed) with the text pre-filled; the user taps send.
`basicId` includes the `@`, URL-encoded as `%40`. Text example: `Link my account #K7PM2QXA` (from a Custom Label, EN/TH).
Check how it behaves when the user hasn't added the OA yet, on both iOS and Android, and record the result in `DECISIONS.md`.

### Push body
```json
{ "to": "Uyyyy...", "messages": [ { "type": "text", "text": "สวัสดีครับ ยินดีให้ข้อมูลครับ" } ] }
```
Up to 5 message objects per request. Text max 5,000 characters.

Image / video / audio objects:
```json
{ "type": "image", "originalContentUrl": "https://...", "previewImageUrl": "https://..." }
{ "type": "video", "originalContentUrl": "https://...mp4", "previewImageUrl": "https://...jpg" }
{ "type": "audio", "originalContentUrl": "https://...m4a", "duration": 60000 }
```
- URLs must be public HTTPS. Image: JPEG/PNG, original ≤ 10 MB, preview ≤ 1 MB [VERIFY current limits].
- **There is no "file" message type for sending.** Documents go out as a text (or Flex) message containing a link.
- Salesforce public URL: create `ContentDistribution` for the ContentVersion and use `ContentDownloadUrl`
  (direct download) for media, `DistributionPublicUrl` for document links; set `ExpiryDate` and
  `PreferencesExpires = true`. [VERIFY in M7 that LINE accepts `ContentDownloadUrl` for images — redirects/content-type.]

### Errors to surface

| HTTP | Meaning | UI message |
|---|---|---|
| 400 | Invalid request (e.g. bad URL, text too long) | Show LINE `message` |
| 401 | Token invalid → channel secret wrong/reissued | "LINE OA credentials invalid — contact admin" + error log |
| 403 | Not authorized for this API | error log |
| 409 | Retry key already accepted | Treat as success |
| 429 | Rate limit **or monthly message limit reached** (`"You have reached your monthly limit."`) | "This LINE OA has used its monthly message allowance" |
| 5xx | LINE error | Allow retry |

## 4. Limits (per channel, so they don't add up across OAs) [VERIFY]

- Push API rate limit: ~2,000 requests/second per channel.
- Monthly message allowance: depends on each OA's LINE plan (Thailand plans). Push messages count; reply messages (using `replyToken`) are free but the reply token expires quickly, so human replies from Salesforce are **push**.
- Webhook: LINE expects a quick 2xx. Enable **webhook redelivery** in the console so failed deliveries are retried (idempotency via `webhookEventId` makes that safe).

## 5. Things LINE does NOT give us

- Messages that a rep sends from the **LINE OA Manager** app/web chat are **not** delivered to the webhook → invisible to Salesforce.
- A LINE user ID is not visible in the LINE OA Manager UI → reps can't type it in; linking happens in Salesforce from follow/message events.
- Bots cannot send file attachments (PDF/Office).
