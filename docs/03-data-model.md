# 03 — Data Model

This is the **agreed schema**. Do not add, merge or rename business objects without asking.

**Packaging:** this ships in a managed 2GP. Once a version is released, API names, field types, and relationship
types are effectively permanent. Lengths can grow but not shrink, and picklist values can be added but not safely removed.
Get names right before the first released (non-beta) version. There is no channel secret on any object: secrets
live in a protected custom setting (§4).

## 1. Objects

| Object | API name | Type | Purpose |
|---|---|---|---|
| User | `User` | Standard | Sales rep who is mapped to a dedicated LINE OA |
| Contact | `Contact` | Standard | Customer record and LINE customer identity |
| Event | `Event` | Standard | Daily LINE conversation summary in Activity History |
| LINE OA Configuration | `LINE_OA_Configuration__c` | Custom | One record per LINE OA, assigned to a sales rep |
| LINE Conversation | `LINE_Conversation__c` | Custom | Conversation/thread between a Contact and a LINE OA |
| LINE Message | `LINE_Message__c` | Custom | Individual inbound/outbound LINE message |

## 2. Relationships (ERD)

```
 User ─────────────1:N──────────────► LINE_OA_Configuration__c      (Assigned_Rep__c)
 User ─────────────1:N──────────────► LINE_Conversation__c          (OwnerId)
 LINE_OA_Configuration__c ──1:N─────► Contact                       (Contact.LINE_OA_Configuration__c)
 LINE_OA_Configuration__c ──1:N─────► LINE_Conversation__c          (LINE_OA_Configuration__c)
 Contact ──────────1:N (optional)───► LINE_Conversation__c          (Contact__c, blank until linked)
 LINE_Conversation__c ──────1:N─────► LINE_Message__c               (master-detail)
 Contact ──────────1:N──────────────► Event                         (WhoId)
 LINE_Conversation__c ──────1:N─────► Event                         (WhatId)
```

**Interpretation of the diagram (confirm with the BA if any is wrong):**
- *User → LINE Conversation* is the record **owner** (`OwnerId`), which drives visibility. It equals the OA's assigned rep, or the fallback owner when the OA is inactive.
- *LINE OA Configuration → Contact* is the Contact's **primary LINE OA** (`Contact.LINE_OA_Configuration__c`). The chat panel opens that OA's conversation first. It is set when the Contact is first linked, if blank.
- *Contact = "LINE customer identity"*: `Contact.LINE_User_Id__c` stores the customer's LINE user ID. All OAs are under one LINE Provider, so a customer has the same user ID in every OA [VERIFY]. When the customer adds a second rep's OA, the new conversation is **linked automatically** to the same Contact.
- *Event* uses `WhoId` = Contact and `WhatId` = LINE Conversation. This needs **Allow Activities** on `LINE_Conversation__c`. One Event per conversation per day equals one Event per Contact per OA per day.

## 3. Fields

### LINE_OA_Configuration__c
OWD: **Public Read Only** (reps need the OA name in the UI). Owner: the admin who registered it.

| Field | Type | Notes |
|---|---|---|
| Name | Text(80) | OA display name (from bot info) |
| Channel_Id__c | Text(20), Unique, External ID, Required | LINE Messaging API channel ID |
| Bot_User_Id__c | Text(40), Unique, External ID | The `destination` value in webhooks (from `GET /v2/bot/info` `userId`) |
| Basic_Id__c | Text(40) | e.g. `@123abcde`, used for add-friend links and QR codes |
| Picture_Url__c | URL | OA picture |
| Assigned_Rep__c | Lookup(User) | Owner of all conversations of this OA |
| Is_Active__c | Checkbox, default true | Inactive: new/moved conversations go to the fallback owner (`LINE_Settings__c.Fallback_Owner_Id__c`); webhooks still accepted |
| Webhook_Status__c | Text(255) | Result of the last set/test webhook |
| Last_Verified_At__c | DateTime | |

Validation: `Is_Active__c && ISBLANK(Assigned_Rep__c)` → error.

### Contact (new fields)

| Field | Type | Notes |
|---|---|---|
| LINE_User_Id__c | Text(40), Unique, External ID | Customer's LINE user ID (`U…`). Set when linked. Used for auto-linking. |
| LINE_OA_Configuration__c | Lookup(LINE_OA_Configuration__c) | Primary LINE OA for this Contact |
| LINE_Invite_Code__c | Text(8), Unique (case sensitive), External ID | One-time QR invite code (alphabet `A-HJ-NP-Z2-9`). Cleared once used. |
| LINE_Invite_Expires_At__c | DateTime | Code expiry (`Invite_Code_Expiry_Days__c`) |

### LINE_Conversation__c
OWD: **Private**. Owner = the OA's assigned rep, or the fallback owner (a user or a subscriber-created queue that supports this object).
Allow Activities: **on**. Allow Reports: on.

| Field | Type | Notes |
|---|---|---|
| Name | Text(80) | LINE display name (fallback: LINE user ID) |
| LINE_OA_Configuration__c | Lookup(LINE_OA_Configuration__c), Required | Lookup, **not** master-detail (keeps OWD Private) |
| Contact__c | Lookup(Contact) | Blank until linked |
| LINE_User_Id__c | Text(40), Required | `source.userId` from the webhook |
| Unique_Key__c | Text(80), Unique, External ID | `<Channel_Id__c>:<LINE_User_Id__c>`, the upsert key |
| Picture_Url__c | URL | From the profile API |
| Status__c | Picklist: Following, Unfollowed | Updated on follow/unfollow |
| Last_Message_At__c | DateTime | Sorts the inbox |
| Last_Message_Preview__c | Text(255) | |
| Unread_Count__c | Number(6,0), default 0 | +1 on inbound; reset by `markRead` |

### LINE_Message__c
Master-detail → `LINE_Conversation__c` (sharing **Controlled by Parent**, reparenting **off**).
Get the Contact and OA through the parent (`LINE_Conversation__r.Contact__c`), not copied lookups.

| Field | Type | Notes |
|---|---|---|
| Name | Auto Number `LM-{0000000}` | |
| LINE_Conversation__c | Master-Detail(LINE_Conversation__c) | |
| Direction__c | Picklist: Inbound, Outbound | |
| Message_Type__c | Picklist: text, image, video, audio, file, sticker, location, unsupported | |
| Text__c | Long Text Area(5000) | LINE text max is 5,000 chars |
| Sent_At__c | DateTime | Inbound: event `timestamp` (ms epoch). Outbound: now. |
| Line_Message_Id__c | Text(40), External ID | `message.id` (inbound) |
| Webhook_Event_Id__c | Text(40), Unique, External ID | `webhookEventId`, used for idempotency (inbound only) |
| Status__c | Picklist: Received, Sent, Failed, Downloading, Download Failed, Too Large | |
| Error__c | Text(255) | LINE error message on failure |
| Sender__c | Lookup(User) | Outbound: the rep who sent it |
| File_Name__c | Text(255) | File messages |
| File_Size__c | Number(12,0) | Bytes |
| Content_Document_Id__c | Text(18) | Downloaded or sent file |
| Public_Url__c | Long Text Area(1000) | Outbound media or document link (ContentDistribution). **Not** a URL field: URL and Text fields stop at 255 characters and Salesforce content URLs can be longer (DECISIONS DEC-14) |
| Sticker_Package_Id__c / Sticker_Id__c | Text(20) | Sticker display |
| Location__c | Text(255) | "title, address (lat,long)" |

### Event (new field)

| Field | Type | Notes |
|---|---|---|
| LINE_Sync_Key__c | Text(80) | `<ConversationId>:<yyyy-MM-dd>`. Query before insert, so reruns don't duplicate. |

Event values: `WhoId` = conversation's Contact, `WhatId` = conversation, `OwnerId` = conversation owner (if a User),
`Subject` = `LINE Conversation - <OA name> - dd MMM yyyy`, `StartDateTime`/`EndDateTime` = first/last message,
`Description` = transcript `[HH:mm] Customer|<Rep name>: text` (times in the Event owner's time zone, truncated to 32,000 chars).
Skip conversations with no Contact.

## 4. Supporting metadata (technical, all packaged unless noted)

| Item | Details |
|---|---|
| Platform event `LINE_Webhook_Event__e` | Publish Immediately. Fields: `OA_Configuration_Id__c` Text(18), `Webhook_Event_Id__c` Text(40), `Event_Json__c` Long Text(131072). One event per LINE event. Subscriber: `LineWebhookEventTrigger` (runs as Automated Process; no subscriber config). |
| **Protected** list custom setting `LINE_OA_Credential__c` | `Name` = Channel ID (≤ 38 chars), `Channel_Secret__c` Text(255). Visibility **Protected**. Only `LineCredentialStore` reads or writes it. Never exposed to LWC, logs or debug. |
| Hierarchy custom setting `LINE_Settings__c` (org-level record; Visibility Public) | `Site_Base_Url__c` Text(255); `Fallback_Owner_Id__c` Text(18); `Poll_Interval_Seconds__c` Number (default 5); `Max_Download_Bytes__c` Number (default 10,000,000); `Public_Link_Expiry_Days__c` Number (7); `Invite_Code_Expiry_Days__c` Number (7); `Message_Retention_Months__c` Number (0 = keep forever); `Daily_Sync_Enabled__c` Checkbox (true); `Update_Contact_Owner_On_Reassign__c` Checkbox (false). `LineSettings` supplies code defaults when blank; edited through `lineAdmin`. |
| Object `LINE_Error_Log__c` | `Source__c` Text(100), `Message__c` Long Text(32000), `Stack_Trace__c` Long Text(32000), `LINE_OA_Configuration__c` Lookup, `Related_Record_Id__c` Text(18), `Http_Status__c` Number(3,0). OWD Private; visible to `LINE_Admin`. Kept 90 days by the retention batch. |
| Custom permission `LINE_Admin` | Checked by `LineAdminController` (in addition to object permissions) |
| CustomNotificationType `LINE_New_Message` (desktop + mobile) | New inbound message alert. Look up by DeveloperName + namespace. [VERIFY packageable] |
| Remote Site Settings `LINE_API` (https://api.line.me), `LINE_API_DATA` (https://api-data.line.me) | Callouts |
| Static resource `qrcode` | QR code JS library (MIT or similar; version and licence recorded in `docs/DECISIONS.md`) |
| Custom Labels (+ Thai translations) | All UI text, invite message text, notification text |
| Lightning App `LINE Chat` + tabs | Tabs: LINE Conversations, LINE OA Configurations, LINE Admin (app page with `lineAdmin`) |
| Record page/flexipage | **Not** auto-activated. Subscriber admins add `lineChat` to their Contact page (install guide). |
| Not packaged (subscriber creates) | Salesforce Site, fallback queue (optional), permission set assignments |

## 5. Linking rules

Implemented only in `LineLinkService`.

1. **Invite code** (inbound text contains `#XXXXXXXX`, matching `[A-HJ-NP-Z2-9]{8}`):
   - Look up `Contact.LINE_Invite_Code__c`. It must be unexpired.
   - Apply the manual-link checks (rule 3) → link, clear the code, and queue a confirmation **reply**.
   - An invalid or expired code: store the message as normal, don't link, and reply "code expired, ask your sales rep for a new one" (reply only).
2. **Auto-link**: `Contact.LINE_User_Id__c` = the conversation's `LINE_User_Id__c` → set `Contact__c`.
3. **Manual link** (`linkToContact(conversationId, contactId)`):
   - Contact has no LINE user ID → set `Contact.LINE_User_Id__c`; set `Contact.LINE_OA_Configuration__c` if blank.
   - Contact already has the **same** ID → link.
   - Contact has a **different** ID, or another Contact already has this ID → refuse with a message naming the other Contact
     (only if the user can see it; otherwise a generic message).
   - The rep needs Edit access to the Contact (checked in user mode).
4. **Unlink** (admin only): clear `Contact__c`; clear `Contact.LINE_User_Id__c` only if no other conversation still links it.
5. **Invite generation** (`createInvite(contactId)`): the rep must have Edit on the Contact. Generate a crypto-random code
   (`Crypto.getRandomInteger`) and retry on a unique collision. Set expiry. Return the `oaMessage` URL for the rep's active OA
   (the Contact's primary OA if the rep owns it). Generating a new code replaces the old one.

## 6. Permission sets (packaged)

| Permission set | Assigned to | Grants |
|---|---|---|
| `LINE_Chat_User` | Sales reps, managers | LINE_Conversation__c Read/Edit; LINE_Message__c Read/Create; LINE_OA_Configuration__c Read; Contact `LINE_User_Id__c` Read/Edit, `LINE_OA_Configuration__c` Read/Edit, invite fields Read/Edit; Event Read + `LINE_Sync_Key__c` Read; Apex `LineChatController`; app + tabs |
| `LINE_Admin` | Admins | Everything in Chat User + LINE_OA_Configuration__c CRUD; View All on conversations/messages; `LINE_Error_Log__c` Read/**Edit**/Delete + **View All**; custom permission `LINE_Admin`; Apex `LineAdminController`; LINE Admin tab |
| `LINE_Webhook_Guest` | The Site's guest user | Apex `LineWebhookResource` **only**; Create **and Read** on `LINE_Webhook_Event__e`. No object read. |

The Automated Process user needs no permission set, because processing runs in system mode.
There's no permission to read `LINE_OA_Credential__c`; protected settings are reachable only from package code.

**Three grants the platform forces** (approved 2026-09-22, DECISIONS DEC-13):

- `LINE_Error_Log__c` **Edit** for `LINE_Admin`: Salesforce refuses Delete without Edit. Field-level access stays read-only, so
  admins can delete a log but not rewrite one.
- `LINE_Error_Log__c` **View All** for `LINE_Admin`: the object is Private and most records are written by Automated Process,
  so without it an admin sees nothing, which contradicts §4 "visible to `LINE_Admin`".
- `LINE_Webhook_Event__e` **Read** for `LINE_Webhook_Guest`: Salesforce refuses Create without Read. On a platform event, Read
  only allows subscribing to the event stream, which a guest session can't do in practice; it grants no access to records.
