# 02 — Architecture

## 1. Component overview

```
                     LINE Platform                                    Subscriber Salesforce Org (package installed)
 ┌──────────┐   ┌─────────────────────┐  POST (signed)   ┌─────────────────────────────────────────────┐
 │ Customer │◄─►│ Rep A OA / Rep B OA │─────────────────►│ Public Site (guest, LINE_Webhook_Guest PS)   │
 └──────────┘   └─────────────────────┘                  │  /services/apexrest/<ns>/line/webhook        │
                         ▲                               │  LineWebhookResource (global)                │
                         │                               │   1. find OA by destination                  │
                         │                               │   2. verify X-Line-Signature                 │
                         │                               │   3. publish LINE_Webhook_Event__e per event │
                         │                               └───────────────────┬─────────────────────────┘
                         │                                                   │
                         │                               ┌───────────────────▼─────────────────────────┐
                         │  profile / content / reply    │ LineWebhookEventTrigger (Automated Process)  │
                         ├───────────────────────────────│  → LineInboundService (conversations,        │
                         │                               │    messages, linking, unread, notifications) │
                         │                               │  → LineCalloutQueueable (profile, media,     │
                         │                               │    invite confirmation reply)                │
                         │                               └─────────────────────────────────────────────┘
                         │  push                         ┌─────────────────────────────────────────────┐
                         └───────────────────────────────│ lineChat / lineInbox / lineAdmin (LWC)       │
                                                         │  → LineChatController / LineAdminController  │
                                                         │  → LineOutboundService → LineApiClient       │
                                                         └─────────────────────────────────────────────┘
      Scheduled: LineDailyEventSyncBatch, LineRetentionBatch  (scheduled by LineScheduler from the admin UI)
```

## 2. Apex classes

Only `LineWebhookResource` is `global`. Everything else is `public`. `@AuraEnabled` methods work from the package's own LWCs.

| Class | Sharing | Responsibility |
|---|---|---|
| `LineWebhookResource` | `without sharing` (global) | `@RestResource(urlMapping='/line/webhook')`. Resolve the OA by `destination`, verify the signature, publish one PE per LINE event, return a status. No DML on business objects, no callouts. |
| `LineSignatureVerifier` | – | `Boolean isValid(Blob rawBody, String signature, String secret)` |
| `LineCredentialStore` | `without sharing` | **Only** class that reads or writes the protected custom setting `LINE_OA_Credential__c`. Methods: `getSecret(channelId)`, `putSecret(channelId, secret)`, `remove(channelId)`. |
| `LineOAConfigSelector` | `without sharing` | Queries for `LINE_OA_Configuration__c` (`byBotUserIds`, `byIds`, `activeForUser`) |
| `LineSettings` | – | Reads `LINE_Settings__c` (hierarchy, org level) with code defaults when blank. Builds the webhook URL, including namespace. |
| `LineNamespace` | – | Namespace prefix at runtime (e.g. from `LineNamespace.class.getName()`). Used for the REST URL and CustomNotificationType lookup. |
| `LineWebhookEventTriggerHandler` | `without sharing` | PE trigger entry. Parses events, calls `LineInboundService` in bulk, uses `setResumeCheckpoint` for partial failures. |
| `LineInboundService` | `without sharing` | message / follow / unfollow. Upserts conversations, messages (idempotent), linking (auto + invite code), unread counts, notifications. Collects follow-up callouts into **one** queueable. |
| `LineLinkService` | `without sharing` | Linking rules (03 §5): manual, auto, invite code. Generates and validates invite codes. |
| `LineApiClient` | – | All HTTP to LINE: token, bot info, webhook endpoint set/test, profile, push, reply, content, quota. Per-transaction token cache. Throws `LineApiException`. |
| `LineCalloutQueueable` | `without sharing`, `Database.AllowsCallouts` | Work items: fetch profile, download content → ContentVersion, send invite confirmation reply. Chains itself if more work remains (respecting callout/heap limits). |
| `LineOutboundService` | `without sharing` | Send text/image/document link. Callout first, then DML. Uses `X-Line-Retry-Key`. |
| `LineChatController` | `with sharing` | LWC API for reps: conversations for a Contact, message pages, poll since, send, mark read, link, create invite, unlinked list. All queries `WITH USER_MODE`. |
| `LineAdminController` | `with sharing` | LWC API for the admin page: settings, register OA, rotate secret, reassign, deactivate, test webhook, quota, schedule jobs. Checks the `LINE_Admin` custom permission. |
| `LineOAConfigAdminService` | `without sharing` | Register, rotate, reassign, deactivate (callouts first, then DML). |
| `LineOAConfigTriggerHandler` | `without sharing` | On rep or active change → start `LineReassignBatch`. |
| `LineReassignBatch` | | Moves the owner of an OA's conversations; optionally Contact Owner. |
| `LineDailyEventSyncBatch` | | One Event per conversation per day. |
| `LineRetentionBatch` | | Deletes messages older than retention, and their files. |
| `LineScheduler` | – | One `Schedulable` that runs both nightly batches. Scheduled or unscheduled from the admin UI. |
| `LineLogger` | – | Writes `LINE_Error_Log__c`; never throws. Buffers entries, and `flush()` runs at the end of each entry point. |
| `LineTriggerHandler` (base) | – | Minimal virtual trigger handler with bypass. |

LWC: `lineChat` (Contact record page), `lineInbox` (Home/App page), `lineInvite` (modal used by `lineChat`),
`lineAdmin` (admin app page). Static resource: QR code library (see 09 §6).

## 3. Key design decisions

### D1 — One webhook URL per org; route by `destination`
Every webhook body has `destination` = the receiving OA's bot user ID, stored on `LINE_OA_Configuration__c.Bot_User_Id__c`.
Adding an OA needs no code or deployment. The URL includes the namespace: `https://<site>/services/apexrest/<ns>/line/webhook`.

### D2 — Verify the signature in the webhook, synchronously
Resolve the OA by `destination`, then compute `Base64(HMAC-SHA256(rawBody, secret))` and compare it with `X-Line-Signature`.
An unknown destination → 403; a bad or missing signature → 401. Nothing is published in either case.

### D3 — The webhook only publishes platform events; processing runs as Automated Process
The guest context does minimal work. It publishes **one PE per LINE event**, which keeps each payload small.
The PE trigger runs as the **Automated Process** user by default, so subscribers don't need a `PlatformEventSubscriberConfig`,
which can't be packaged because it references a user. Owners are always set explicitly. [VERIFY that Automated Process can
send custom notifications and enqueue callout queueables; if not, document an optional subscriber-side config.]

### D4 — Secrets in a protected custom setting; stateless tokens
- `LINE_OA_Credential__c`: a **List custom setting, Visibility = Protected**. Record `Name` = Channel ID, field `Channel_Secret__c`.
  In a managed package, protected settings can't be seen by subscriber admins, API or non-namespace code.
  Only `LineCredentialStore` touches it.
- Access tokens: **stateless channel access tokens** issued from Channel ID + secret (`POST /oauth2/v3/token`, ~15 min) [VERIFY].
  There are no long-lived tokens to store or rotate. They are cached per transaction.
- Callouts use packaged **Remote Site Settings** (`api.line.me`, `api-data.line.me`), and Apex sets the `Authorization` header itself.
  No Named Credentials: a principal per OA would need subscriber metadata for every OA.

### D5 — Customer identity: the Contact holds the LINE user ID, conversations are per OA
All OAs of a client are under one LINE Provider, so a customer's user ID is the same in every OA [VERIFY].
`Contact.LINE_User_Id__c` is the identity (unique). `LINE_Conversation__c.Unique_Key__c = <Channel_Id__c>:<userId>`.
A second OA's conversation auto-links to the same Contact.

### D6 — Visibility by ownership
`LINE_Conversation__c` OWD **Private**, owner = the OA's assigned rep (or the fallback owner). `LINE_Message__c` is
**master-detail** (Controlled by Parent). Reassignment updates only conversations. Managers see through the role hierarchy.
OWD is set in the object metadata and is part of the package.

### D7 — Chat refresh by polling, not streaming
Streaming (empApi/CDC) counts each delivery per subscribed tab against the subscriber's daily event delivery allocation, and we can't
control subscriber volume. So:
- `lineChat` polls `getMessagesSince(conversationId, afterSentAt, afterId)` every N s (setting), only while the tab is visible.
- `lineInbox` polls every 30 s.

Instant alerts use Custom Notifications.

### D8 — Callouts before DML; idempotent sends
Push is called first, then the message is inserted (Sent or Failed). Push uses `X-Line-Retry-Key` (UUID). A 409 response means "already accepted".

### D9 — Idempotent ingestion
`LINE_Message__c.Webhook_Event_Id__c` is unique and used as the upsert key. Redeliveries are no-ops.

### D10 — QR invite uses the LINE URL scheme, not LIFF
The invite is `https://line.me/R/oaMessage/<basicId>/?<urlencoded text>` [VERIFY]. It opens the OA chat (and offers to add the OA)
with a pre-filled text holding a one-time code, e.g. `Link my account #K7PM2QXA`. The inbound service matches `#[A-HJ-NP-Z2-9]{8}`
against `Contact.LINE_Invite_Code__c`. If the code is valid and not expired, it links, clears the code, and sends a free **reply**
confirmation (skipped if the reply token has expired; never a paid push).
This needs no web page, LIFF app or LINE Login channel, and it works in every subscriber org with no extra setup.

### D11 — Built for unknown subscriber orgs
- DML on Contact/Event uses `Database.update/insert(records, false)`. Failures are logged and never block message storage.
- There is no dynamic SOQL on package fields. If it's ever needed, prefix names via `LineNamespace`.
- No hardcoded profile names, record type IDs or user IDs. Tests create their own users with a profile found by permissions, not by name.
- All user-facing text is in Custom Labels (EN + TH).

### D12 — Large data volume
- Message pages use keyset pagination (`Sent_At__c`, `Id`) with `LIMIT`. No `OFFSET`.
- Every query filters on an indexed field: master-detail, lookup, external ID or `Id`.
- Batches use `QueryLocator`. The retention batch keeps the table bounded.
- Inbound processing is bulkified for 200-event PE batches. At most one queueable is enqueued per trigger execution.

## 4. Sequences

### Inbound message
1. LINE → `POST /services/apexrest/<ns>/line/webhook`.
2. Resolve the OA by `destination` (403 if unknown) → `LineCredentialStore.getSecret` → verify (401 if invalid).
3. Publish `LINE_Webhook_Event__e(OA_Configuration_Id__c, Webhook_Event_Id__c, Event_Json__c)` for each event → return 200 (also for empty `events`).
4. PE trigger → `LineInboundService`:
   - upsert the conversation by `Unique_Key__c`. Owner = the rep, or the fallback owner if the OA is inactive.
   - link: invite code in the text → link; else auto-link by `Contact.LINE_User_Id__c`.
   - upsert the message by `Webhook_Event_Id__c`. Media → `Status__c = Downloading`.
   - update the unread count and last message; send a custom notification to the owner if the owner is a user.
   - enqueue one `LineCalloutQueueable` (profile / content / invite reply).
5. `lineChat`'s next poll shows the message.

### Outbound
1. `LineChatController.sendText|sendImage|sendDocument(conversationId, …)` → `WITH USER_MODE` access check.
2. `LineOutboundService` → `LineApiClient.issueToken` → push (+ `ContentDistribution` for media/docs).
3. Insert an Outbound message (Sent/Failed, Sender = current user). Return a DTO. Show LINE errors (e.g. monthly limit) to the rep.

### Reassignment
Admin reassigns/deactivates in `lineAdmin` → `LINE_OA_Configuration__c` update → trigger → `LineReassignBatch`
(owner → new rep or fallback owner; optionally Contact Owner) → the admin sees job status.

## 5. Governor limit notes

| Limit | Where | Handling |
|---|---|---|
| Heap / callout response 12 MB async | Media download | Queueable only. Skip if `fileSize` > `Max_Download_Bytes__c` → Too Large. One download per queueable execution if large, then chain. |
| 100 callouts / 120 s per transaction | Queueable work list | Process a slice, then re-enqueue the rest |
| No callouts from triggers | PE trigger | Queueable |
| 50 enqueues / transaction | PE trigger | One queueable per execution with a work list |
| PE trigger retries | Transient errors | `EventBus.RetryableException` only for transient failures, max 3; otherwise log |
| Event Description 32,000 chars | Daily sync | Truncate with a pointer to the chat |
| Data storage | Messages | Retention batch |
