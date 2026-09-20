# 06 — MVP Implementation Plan

Work **milestone by milestone**. Each milestone ends deployed to a scratch org with its tests green. Claude stops after each one for review.
Estimates are person-days of development effort.

Milestones M3, M6 and M11 each end with a **beta package version installed in the QA org**, so packaging problems show up early, not at the end.

| # | Milestone | Est. |
|---|---|---|
| M0 | Packaging foundation | 2–3 |
| M1 | Data model, settings, security metadata | 2–3 |
| M2 | Core services: logger, settings, credential store, LINE API client | 2–3 |
| M3 | OA registration + inbound webhook + processing → **Beta 1** | 4–5 |
| M4 | Outbound text | 1.5–2 |
| M5 | Chat panel (`lineChat`) | 4–5 |
| M6 | Linking: manual, auto, QR invite + inbox (`lineInbox`) → **Beta 2** | 5–6 |
| M7 | Files and images, in and out | 5–7 |
| M8 | Admin UI (`lineAdmin`) + reassignment batch | 4–5 |
| M9 | Daily Event sync | 2–3 |
| M10 | Retention + error log housekeeping | 1.5–2 |
| M11 | Hardening: security review readiness, EN/TH labels, LDV test → **Release candidate** | 4–5 |
| M12 | QA org end-to-end, upgrade test, install guide, UAT support | 3–5 |
| | **MVP total** | **40–54 d** (+15–20% contingency) |

---

## M0 — Packaging foundation (2–3 d)
- [HUMAN] 05 Part A1–A5 (Dev Hub, namespace, link, auth).
- [CLAUDE] Set up `sfdx-project.json` (namespace, package dir, `unpackaged/`), the scratch definition, and `scripts/setup-scratch.sh`
  (create scratch → deploy → assign permission sets → create 2 test rep users → seed settings).
- [CLAUDE] `sf package create`. Create an empty beta version to prove the pipeline, and install it into the QA org.
- [CLAUDE] Create `docs/DECISIONS.md` and `docs/SECURITY_NOTES.md`. Add a Code Analyzer run script.

**Done when:** a scratch org is created by one script; an empty beta installs into `sf-line-dev`.

> **Order change (DECISIONS DEC-08):** M1–M2 are built first in non-namespaced scratch orgs from `sf-line-dev`.
> The [HUMAN] Dev Hub/namespace steps, `sf package create` and the beta install proof are completed before M3's Beta 1.

## M1 — Data model & security metadata (2–3 d)
Everything in 03: the 3 custom objects, Contact/Event fields, `LINE_Webhook_Event__e`, `LINE_OA_Credential__c` (protected),
`LINE_Settings__c`, `LINE_Error_Log__c`, custom permission, CustomNotificationType, remote site settings, the 3 permission sets,
the app and tabs, and a label skeleton. Include descriptions on every object and field.

**Done when:** deploys to a scratch org; permission sets match 03 §6; a beta version builds (no code yet → coverage not required).

## M2 — Core services (2–3 d)
`LineTriggerHandler` (base), `LineLogger`, `LineSettings`, `LineNamespace`, `LineCredentialStore`, `LineApiClient` (+ `LineApiException`,
typed DTOs), `LineHttpMock`, and `LineTestFactory`.

**Done when:** unit tests cover every `LineApiClient` method, including error mapping (400/401/403/409/429/5xx).

## M3 — Registration + inbound (4–5 d) → Beta 1
- `LineOAConfigSelector`, `LineOAConfigAdminService.registerOA` (anonymous-Apex callable at this stage).
- `LineSignatureVerifier`, `LineWebhookResource`, `LineWebhookEventTrigger` + handler, `LineInboundService` (text + follow/unfollow;
  store other types as placeholders), and a `LineCalloutQueueable` profile fetch.
- Notifications to the owner.
- **Beta 1** → QA org: create the Site, assign the guest permission set, register 2 real OAs, send from phones.

**Done when:** acceptance criteria 1 (inbound half), 3 and 4 pass in the QA org; a wrong signature returns 401; redelivery doesn't duplicate.
Record the [VERIFY] results for stateless tokens, `destination`, and Automated Process notifications/callouts.

## M4 — Outbound text (1.5–2 d)
`LineOutboundService.sendText`, `LineChatController.sendText` (user-mode access check, 1–5000 chars), and failure status/error mapping.

**Done when:** a send from a scratch org test passes; a mocked 429 monthly-limit error gives a readable message.

## M5 — Chat panel `lineChat` (4–5 d)
- Controller: `getConversations(contactId)` (default to the Contact's primary OA), `getMessages(conversationId, beforeSentAt, beforeId, pageSize)`,
  `getMessagesSince(conversationId, afterSentAt, afterId)`, `markRead`.
- UI:
  - bubbles, time in the user's time zone, failed state, placeholders for non-text;
  - load older on scroll-up; poll while visible; send on Enter (Shift+Enter for a newline);
  - empty state with an *Invite via LINE* button (wired in M6). All labels EN/TH.
- Jest tests.

**Done when:** acceptance criteria 1–2 (text) pass in a scratch org with simulated inbound events.

## M6 — Linking + inbox (5–6 d) → Beta 2
- `LineLinkService`: manual, auto, and invite code (03 §5); `createInvite`; confirmation/expired **reply** in the queueable.
- `lineInvite` modal: QR (static resource library), copy link, expiry shown.
- `lineInbox`: tabs *Unread* and *Unlinked*, link to Contact (`lightning-record-picker`), open the conversation.
- **Beta 2** → QA org: scan the QR with a real phone; add a second OA and check it auto-links.

**Done when:** acceptance criteria 6 passes on real phones (iOS and Android); the URL scheme result is recorded in DECISIONS.

## M7 — Files & images (5–7 d)
- Inbound: download content in `LineCalloutQueueable` (size check → Too Large; one large file per execution; chain the rest),
  ContentVersion with `FirstPublishLocationId` = conversation, and a ContentDocumentLink to the Contact if linked. Thumbnails and download links in `lineChat`.
- Outbound: upload in `lineChat` → image/video/audio sent natively, other files as an expiring `ContentDistribution` link in a text message.
  Validate type and size before the callout.
- Stickers rendered as a label or image (as verified), location as a text + map link.

**Done when:** acceptance criteria 2 (image + document) and 7 pass in the QA org with real files; LINE accepts the Salesforce public URL (recorded in DECISIONS).

## M8 — Admin UI + reassignment (4–5 d)
- `lineAdmin` app page:
  - **Settings form** for `LINE_Settings__c`;
  - **OA list** with register, rotate secret, reassign, deactivate/activate, test webhook and quota;
  - **Job status**, with schedule/unschedule of the nightly jobs;
  - **Error log** list.
- `LineAdminController` checks the `LINE_Admin` custom permission.
- `LineOAConfigTriggerHandler` → `LineReassignBatch` (optional Contact Owner update).

**Done when:** acceptance criterion 5 passes; OA onboarding is done entirely in the UI.

## M9 — Daily Event sync (2–3 d)
`LineDailyEventSyncBatch` per 03 §3 Event; `LineScheduler` runs it nightly (plus retention). Idempotent by `LINE_Sync_Key__c`.
Partial-success DML with logging.

**Done when:** acceptance criterion 8 passes, including a rerun and an org with a validation rule on Event (test).

## M10 — Retention (1.5–2 d)
`LineRetentionBatch`: delete messages older than `Message_Retention_Months__c`, and their ContentDocuments; delete error logs older than 90 days.
0 = off.

**Done when:** tests cover the boundary dates and the file deletion.

## M11 — Hardening → release candidate (4–5 d)
- Code Analyzer clean (no Critical/High); CRUD/FLS review; fill in `SECURITY_NOTES.md`.
- Thai translations for all labels (have a native speaker review them).
- LDV check in a scratch org: load 200k messages across 500 conversations with a script. Check message paging, poll query and batch times,
  and record the numbers in DECISIONS.
- Coverage ≥ 85% overall, every class ≥ 75%.
- A beta version with `--code-coverage` → QA.

## M12 — QA, upgrade, docs (3–5 d)
- Full acceptance run (01 §4) in the QA org on real phones.
- **Upgrade test**: previous beta → uninstall → install RC; later, released → next version upgrade.
- `docs/INSTALL_GUIDE.md` (from 05 Part C/D/E, with screenshots) and `docs/RELEASE_NOTES.md`.
- Promote only when the user approves.

## After MVP (backlog)
Person Account support, Pattern 1 (shared OA), LMA licensing, AppExchange security review submission, `unsend` event handling,
rich messages (Flex) for document links, a message search/report pack.
