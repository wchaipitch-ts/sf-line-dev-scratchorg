# 07 — Testing

Three layers: **Apex/Jest in scratch orgs** (every milestone), **real LINE end-to-end in the QA org** (every beta), and **install/upgrade tests** (every beta and release).

## 1. Apex unit tests

Rules:
- No `SeeAllData=true`. No real secrets or IDs; fake values only.
- No profile names; they're localized in Thai orgs. `LineTestFactory.createUser()` picks a profile by permissions
  (e.g. `SELECT Id FROM Profile WHERE UserType = 'Standard' AND PermissionsModifyAllData = false LIMIT 1`) and assigns package permission sets.
- Tests must not depend on subscriber customizations. Create the minimum valid Contact (`LastName` only) and expect partial-success paths.
- Every class ≥ 75%, overall ≥ 85%. Test behaviour: assert records, statuses and callouts made, not just coverage.

### Test data
- Rep A and Rep B (`LINE_Chat_User`), Admin (`LINE_Admin`).
- 2 `LINE_OA_Configuration__c`: Channel ID `1000000001`/`1000000002`, bot user ID `Ubot_a`/`Ubot_b`. Secrets `testsecret_a`/`testsecret_b` are set via `LineCredentialStore.putSecret`.
- `LineTestFactory.webhookBody(destination, events)`, `LineTestFactory.textEvent(userId, text, eventId)`, `followEvent`, `fileEvent`…
- `LineTestFactory.sign(body, secret)` → `EncodingUtil.base64Encode(Crypto.generateMac('hmacSHA256', Blob.valueOf(body), Blob.valueOf(secret)))`.

### Calling the webhook
```apex
RestRequest req = new RestRequest();
req.requestURI = '/services/apexrest/line/webhook';
req.httpMethod = 'POST';
req.requestBody = Blob.valueOf(body);
req.addHeader('X-Line-Signature', LineTestFactory.sign(body, 'testsecret_a'));
RestContext.request = req;
RestContext.response = new RestResponse();
LineWebhookResource.handlePost();
Test.getEventBus().deliver();   // runs the PE trigger
```

### HTTP mock
`LineHttpMock` routes by method + path (`/oauth2/v3/token`, `/v2/bot/info`, `/v2/bot/profile/`, `/v2/bot/message/push`,
`/v2/bot/message/reply`, `/content`, `/webhook/endpoint`, `/webhook/test`, `/quota`). Configurable status/body per route; records the requests made.

### Cases (minimum)

| Area | Case |
|---|---|
| Signature | valid → 200 + PE; wrong → 401, nothing published; missing header → 401; lowercase header name → accepted |
| Routing | destination A → owner Rep A; unknown destination → 403 |
| Events | empty events → 200; many events in one body; 200 PEs in one trigger batch (bulk); group source ignored |
| Idempotency | same `webhookEventId` twice → one message |
| Follow/unfollow | follow creates a conversation + a profile job; unfollow → Unfollowed; re-follow → Following |
| Inactive OA | owner = fallback owner; no notification when the owner is a queue |
| Linking — manual | sets Contact__c + Contact.LINE_User_Id__c + primary OA if blank; conflicts refused; no Edit on Contact → refused |
| Linking — auto | second OA conversation auto-links by LINE user ID |
| Linking — invite | valid code links + clears code + queues reply; expired/unknown code → no link, "expired" reply; code in the middle of the text still matches |
| Subscriber automation | a Contact validation rule that blocks updates → message still stored, link failure logged |
| Outbound | text/image/document success → Sent + Sender; 429 monthly limit → Failed + readable error; 409 → Sent; no access to the conversation → exception |
| Files | download → ContentVersion linked to conversation (+ Contact); over the size limit → Too Large, no callout; download 5xx → Download Failed + retry path |
| Visibility | `System.runAs(RepB)`: can't read Rep A's conversations/messages through the controller or SOQL |
| Reassignment | batch moves owners; optional Contact Owner update; Rep B now reads the history |
| Admin | non-admin calling `LineAdminController` → refused; register fills bot fields, sets the webhook, stores the secret; bad credentials → nothing saved; rotate secret |
| Secret handling | no controller DTO contains the secret (serialize and assert) |
| Daily sync | 3 messages in one conversation yesterday → one Event (Who/What correct); rerun → still one; unlinked conversation → none; Event validation rule → logged, batch continues |
| Retention | messages older than N months deleted with files; 0 = none deleted |

## 2. LWC Jest
`lineChat`, `lineInbox`, `lineInvite`, `lineAdmin`: render, empty state, send/success/error toast, polling starts/stops on visibility, paging.

## 3. End-to-end in the QA org (each beta)

Pre: 2 OAs registered in LINE Admin (OA-A → Rep A, OA-B → Rep B); phones 1 and 2 with LINE (iOS + Android).

1. Rep A opens Contact "Somchai" → Invite via LINE → phone 1 scans the QR → sends the pre-filled message. → Linked, confirmation received, Rep A notified.
2. Phone 1 sends text, a sticker, a photo and a PDF. → All shown in `lineChat` within ~10 s; the files are Salesforce Files.
3. Rep A replies with text, an image and a document. → Phone 1 receives them from OA-A; the document is a working link.
4. Phone 1 adds OA-B and says hi. → Auto-linked to Somchai; only Rep B sees it.
5. Phone 2 adds OA-A without an invite. → Appears in Rep A's *Unlinked* inbox → Rep A links it manually.
6. `curl` with a fake signature → 401, nothing stored.
   ```
   curl -i -X POST https://<site>/services/apexrest/<ns>/line/webhook -H 'Content-Type: application/json' \
     -H 'X-Line-Signature: invalid' -d '{"destination":"Ubot","events":[]}'
   ```
7. LINE console redelivery of an event → no duplicate.
8. Admin reassigns OA-A to Rep B. → Rep B sees the OA-A history; Rep A doesn't.
9. Run the daily sync manually → one Event per conversation for today (test mode) with the right transcript.
10. Reply from the LINE OA Manager app → confirm it does **not** appear (documented limitation).

Record the results, timings and screenshots in `docs/QA_RESULTS_<version>.md`.

## 4. Install & upgrade tests

| Test | When |
|---|---|
| Clean install into a fresh org + 05 Part C only → E2E steps 1–3 | Every beta |
| Install with "Admins only" and with "specific profiles" | RC |
| Upgrade: last released → new version with existing data; settings, secrets and schedules preserved | Every release after 1.0 |
| Uninstall leaves no scheduled jobs failing (document the unschedule step in the install guide) | RC |
