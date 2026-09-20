# 01 — Requirements (MVP, Managed 2GP)

## 1. Product context

- We are building a **managed second-generation package (2GP)**. It is installed into client orgs through private
  install links first. It will be listed on AppExchange later, so it is built to **security-review standards from day one**.
- Each client has many sales reps, and **each rep has their own LINE Official Account** ("Pattern 2").
  A shared company OA ("Pattern 1") is on hold. The design must not block adding it in a later version:
  "OA configuration" is a first-class object, so Pattern 1 becomes one OA routed by Contact Owner.
- Salesforce is the reps' main working tool. They should not need LINE OA Manager to chat.
- Customers are Salesforce **Contacts**.
- The package makes no AI or LLM calls at runtime. The only external API is LINE.

## 2. Actors

| Actor | Description |
|---|---|
| Customer | LINE user who adds a rep's OA and chats with it |
| Sales Rep | Subscriber user assigned to one LINE OA. Sees only their own OA's conversations. |
| Sales Manager | Sees their team's conversations through the role hierarchy |
| LINE Admin | Subscriber admin who configures the package, registers OAs and reassigns them |
| Automated Process | Platform user that runs webhook processing in the subscriber org |
| Us (ISV) | Builds, versions and installs the package |

## 3. User flows

### F1 — Configure the package (admin, once per org)
Admin opens the **LINE Admin** app page. The admin enters the public Site base URL and picks a fallback owner.
The admin also sets retention, invite expiry and daily sync on/off.

### F2 — Register a LINE OA (admin)
Admin enters Channel ID, Channel Secret and the assigned rep. The package checks the credentials with LINE,
fetches the OA's bot user ID, basic ID, name and picture, and sets the OA's webhook URL. The admin sees the
result of a webhook test. Admins can also rotate the secret, reassign the rep, deactivate the OA, and see the OA's monthly message quota.

### F3 — Customer adds the OA
LINE sends a `follow` event. The package creates a `LINE_Conversation__c` owned by the OA's rep and fetches
the customer's LINE name and picture. If a Contact already has this LINE user ID, it auto-links. The rep is notified.

### F4 — Link a conversation to a Contact
Three ways, in order of preference:
1. **QR / link invite (self-service)**: on a Contact, the rep clicks *Invite via LINE* and shows a QR code, or copies a link
   to send by SMS or email. The customer scans or opens it. LINE opens the rep's OA chat with a pre-filled message
   holding a one-time code. The customer taps send, and the package links the conversation to that Contact and
   replies with a confirmation.
2. **Auto-link**: the Contact already has this LINE user ID (linked earlier through another rep's OA) → linked immediately.
3. **Manual**: the rep links an unlinked conversation from their inbox to a Contact.

### F5 — Customer sends a message
Text, image, video, audio, file (PDF/Office/etc.), sticker or location → stored on the conversation. Files are saved as
Salesforce Files. The unread count goes up, and the OA's rep is notified.

### F6 — Rep replies from Salesforce
Rep opens the Contact → the LINE chat panel shows the history → the rep sends text, images or documents.
Documents are sent as expiring download links, because LINE bots cannot send file attachments. The message goes out through
**the OA of that conversation**.

### F7 — Rep leaves or changes role
Admin reassigns the OA to another rep. All of that OA's conversations and history move to the new rep, and customers do nothing.
Contact Owner can optionally follow (setting). If there is no replacement yet, the admin deactivates the OA and its
conversations go to the fallback owner.

### F8 — Daily Activity History
A nightly job creates **one Event per LINE Conversation per day** (Who = Contact, What = conversation) with that day's transcript.

### F9 — Retention
A nightly job deletes messages older than N months (setting; 0 = keep forever). Files linked to deleted messages are
deleted too. Conversations are kept.

## 4. MVP scope

**In:** F1–F9, the inbox (unread and unlinked lists), notifications, error log, Thai + English UI labels,
package versioning and install guide.

**Out (later versions):** group/room chats, broadcast/marketing, rich menus, chatbots or any AI, LINE Login,
Pattern 1, Person Account record pages (see 08), license management (LMA) enforcement, AppExchange listing itself.

### MVP acceptance criteria
1. A message to OA-A reaches only Rep A. A message to OA-B reaches only Rep B.
2. Each rep replies from the Contact page, and the customer receives it from the correct OA (text, image, document link).
3. A request without a valid LINE signature is rejected and stores nothing.
4. Rep A can't see Rep B's conversations in the UI, SOQL or reports.
5. Reassigning OA-A to Rep B gives Rep B the full history of OA-A.
6. QR invite links a new customer to the right Contact with no manual step. The same customer adding OA-B auto-links.
7. Customer files up to the size limit appear as Salesforce Files. Larger files show "too large, view in LINE".
8. The daily Event is created once per conversation per day and is not duplicated on rerun.
9. The package installs into a clean org, is configured with only the steps in 05 Part C, and passes 1–8.
10. Upgrading from the previous beta or released version keeps data and configuration.
11. Salesforce Code Analyzer shows no Critical or High security findings.

## 5. Non-functional requirements

| Area | Requirement |
|---|---|
| Security | Every webhook is checked with an HMAC-SHA256 signature using the receiving OA's secret. Secrets live only in a protected custom setting. The guest user gets only the webhook class and platform event create. CRUD/FLS is enforced in all user-facing code. |
| Visibility | Reps see only conversations they own. Managers see them through the role hierarchy. |
| Latency | An inbound message is visible in the open chat panel within ~10 s. |
| Scale (per subscriber org) | 100 OAs × 100 messages/day, and 1 M+ `LINE_Message__c` rows, without limit errors or slow queries. All queries are selective and paginated. |
| Reliability | Duplicate webhook deliveries create no duplicates. Failed sends and downloads are visible and retryable. Processing errors are logged, never lost silently. |
| Robustness in unknown orgs | Subscriber validation rules or triggers on Contact/Event must not break message ingestion. Errors are logged, and the message is still stored. |
| Upgradeability | No destructive changes between versions. API names, field types and `global` signatures are treated as permanent once released. |
| Localization | All UI text in Custom Labels, with English and Thai translations. Times shown in the user's time zone. |
| Auditability | Outbound messages record the sending user. Admin actions on OAs are logged. |
| Privacy | PDPA consent/notice is the client's responsibility. The package stores only what's needed and supports retention. |
