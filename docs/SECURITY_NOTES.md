# Security Notes

This file becomes the AppExchange security review submission (09 §7). Keep it current as each milestone lands.
Status per section: what is designed (from the spec) and what is **implemented and tested** (filled in as we build).

## 1. External endpoints

| Host | Purpose | Remote Site Setting | Implemented |
|---|---|---|---|
| `https://api.line.me` | Token, bot info, webhook set/test, profile, push, reply, quota | `LINE_API` | M1/M2 |
| `https://api-data.line.me` | Message content download | `LINE_API_DATA` | M1/M2 |

No other callouts. No AI/LLM services. No runtime CDN loads; the QR library is a static resource.

## 2. Guest (unauthenticated) surface

- One Site guest user per subscriber org, holding only the `LINE_Webhook_Guest` permission set:
  Apex class `LineWebhookResource` and Create on `LINE_Webhook_Event__e`. No object read access.
- Endpoint: `POST /services/apexrest/<ns>/line/webhook`.
- Order of checks: resolve the OA by `destination` (unknown → 403) → verify `X-Line-Signature`
  (HMAC-SHA256 over the raw body with that OA's channel secret; bad or missing → 401) → publish one platform event per LINE event.
- No business DML and no callouts in the guest context. Processing runs later in the PE trigger as Automated Process.
- The permission set also holds **Read** on `LINE_Webhook_Event__e`, because the platform won't grant Create without it. Read on a
  platform event only allows subscribing, and it grants no record access (DECISIONS DEC-13c, pending approval).

Implemented (M3), tested and verified live with LINE:
- `LINE_Webhook_Guest` = Apex class `LineWebhookResource` + `LINE_Webhook_Event__e` Create/Read. No objects, no fields.
- Input limits before authentication: body ≤ 1 MB, and only the top-level `destination` is read (streaming parser) to pick the secret.
- Signature: HMAC-SHA256 over the raw body; Base64 compared **case-sensitively in constant time** (`LineSignatureVerifier`). Missing, wrong-case or wrong signatures → 401 (tests).
- Unknown destination → 403; malformed → 400; nothing is published or stored in any rejected case (tests).
- The webhook writes no records at all, not even error logs, so unauthenticated traffic can't create data. Its only output after authentication is `EventBus.publish`.
- Code Analyzer's graph engine flags the system-mode OA lookup on this path (High). It is suppressed at `LineOAConfigSelector.byBotUserIds` with the reason above (DECISIONS DEC-18).

## 3. Secret storage

- Channel secrets: protected list custom setting `LINE_OA_Credential__c` (Name = Channel ID, `Channel_Secret__c`).
  Only reachable from package code; only `LineCredentialStore` reads or writes it.
- Access tokens: stateless (~15 min), issued on demand and cached per transaction. Never stored.
- Secrets and tokens never appear in DTOs, LWC, logs, `System.debug`, error messages, tests, scripts or docs.
  Tests use fake values only.

Implemented: M1 — `LINE_OA_Credential__c` is a List custom setting with Visibility **Protected**; no permission set grants access to it.
The protection itself only applies once installed as a managed package; it will be checked in the QA org after the first beta.

Implemented: M2
- `LineCredentialStore` is the only class that references `LINE_OA_Credential__c`. It validates the channel ID (digits, at most 38 characters) and secret, and its errors never echo the value (tested).
- `LineApiClient` keeps the secret in a private `transient` field, sends it only in the token request body (URL-encoded), and never includes the request in errors.
- The token is only in the `Authorization` header and the per-transaction cache; no DTO or return value outside `issueToken()` carries it.
- `LineLogger` masks bearer tokens, `client_secret=…` and `access_token`/`channelSecret` JSON values before writing (tested).

## 4. `without sharing` classes (justification)

From 02 §2. Each class carries a justification comment in code. Filled in as each class is built.

| Class | Why system mode | Implemented |
|---|---|---|
| `LineWebhookResource` | Guest context; must look up the OA by `destination` without granting the guest read access | ✅ M3 |
| `LineCredentialStore` | Reads the protected custom setting | ✅ M2 (justification comment in class; DML uses explicit `AccessLevel.SYSTEM_MODE`) |
| `LineOAConfigSelector` | Used from the webhook and the PE trigger, which have no user context | ✅ M3 (queries use `WITH SYSTEM_MODE` explicitly) |
| `LineWebhookEventTriggerHandler` | PE trigger runs as Automated Process | ✅ M3 |
| `LineInboundService` (+ inner `OwnerResolver`) | Creates conversations/messages owned by reps, from system context | ✅ M3 (DML uses `AccessLevel.SYSTEM_MODE`) |
| `LineCalloutQueueable` | Async follow-up; updates conversations and OA configurations the running user may not own | ✅ M3 |
| `LineOAConfigAdminService` | Writes the secret and OA configurations; the caller checks `LINE_Admin` (M8) | ✅ M3 (anonymous-Apex only until M8) |
| `LineLinkService` | Invite-code links from the inbound path; user-initiated paths check access in user mode first | M6 |
| `LineCalloutQueueable` | Async follow-up to inbound processing | M3 |
| `LineOutboundService` | Called after the controller checks access in user mode; writes the message record | ✅ M4 (class-wide `sfge` suppression with reason, DEC-20) |
| `LineOAConfigAdminService` | Called after `LineAdminController` checks the `LINE_Admin` custom permission; writes the secret | M3/M8 |
| `LineOAConfigTriggerHandler` | Starts the reassignment batch | M8 |

## 5. CRUD/FLS and sharing

- User-facing Apex (`LineChatController`, `LineAdminController`) is `with sharing` and uses `WITH USER_MODE` / `AccessLevel.USER_MODE`.
- `LineAdminController` also checks the `LINE_Admin` custom permission.
- `LINE_Conversation__c` OWD Private (owner = the OA's rep); `LINE_Message__c` is master-detail (Controlled by Parent).

Implemented (M1):
- `LINE_Conversation__c` OWD Private (internal and external); `LINE_Message__c` Controlled by Parent; `LINE_OA_Configuration__c` Public Read Only; `LINE_Error_Log__c` Private.
- `LINE_Chat_User`: conversations Read/Edit (FLS edit only on `Contact__c`, `Unread_Count__c`); messages Read/Create (FLS read-only, since outbound inserts run in system mode); OA configuration Read; the four Contact LINE fields Read/Edit; `LINE_Sync_Key__c` Read.
- `LINE_Admin`: the above + OA configuration CRUD, View All on conversations and messages, error log Read/Edit/Delete/View All (field-level read-only), custom permission `LINE_Admin`.
- Neither permission set grants access to Contact or Event objects themselves; that stays with the subscriber's profiles.

Implemented (M4): `LineChatController` is `with sharing`; `sendText` queries the conversation `WITH USER_MODE` (so OWD Private
decides who may reply) and checks `LINE_Message__c.isCreateable()` before any callout. Tests prove Rep B cannot send to Rep A's
conversation and that nothing is sent or stored when the check fails. Errors reach the LWC as `AuraHandledException` with a
Custom Label; LINE's own wording is passed through only for errors the rep can act on (monthly limit, invalid text).

Pending: the remaining controller methods (M5) and `LineAdminController` (M8).

## 6. Client side (LWC)

- Message text is rendered as text, never HTML. Customer links are shown as text, not auto-linked.
- No `innerHTML` with untrusted data. No `console.log`.

Implemented: — (M5+)

## 7. Outbound public links

- Media and documents are shared through `ContentDistribution` with an expiry (`Public_Link_Expiry_Days__c`).

Implemented: — (M7)

## 8. Code Analyzer

Run: `npm run scan` (Recommended + Security + AppExchange rules, fails on High/Critical). The Flow engine is disabled because the package has no Flows (DECISIONS DEC-06).

| Date | Scope | Critical/High | Notes |
|---|---|---|---|
| 2026-09-19 | `force-app` (empty, M0) | 0 | Baseline |
| 2026-09-19 | `force-app` (M1 metadata) | 0 | 4 Moderate `ProtectSensitiveData` name-heuristic hits, justified in DECISIONS §3 |
| 2026-09-22 | `force-app` (M4 outbound text) | 0 (5 graph-engine Highs suppressed class-wide on `LineOutboundService` with reason, DEC-20) | 36 Moderate, 165 Low: unchanged categories |
| 2026-09-19 | `force-app` (M3 webhook + inbound) | 0 (2 graph-engine Highs + 1 Moderate suppressed with reasons, DEC-18) | 35 Moderate (complexity/parameter style, DTO naming, name heuristics), 157 Low (ApexDoc on DTO fields/tests) |
| 2026-09-19 | `force-app` (M2 core services) | 0 (1 High suppressed with reason: `ApexSuggestUsingNamedCred`, DEC-16) | 23 Moderate (style/complexity, DTO naming, name heuristics), 90 Low (ApexDoc on DTO fields/tests). All in DECISIONS §3 |
