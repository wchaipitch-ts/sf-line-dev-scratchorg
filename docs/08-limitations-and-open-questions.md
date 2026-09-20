# 08 — Limitations, Risks, Open Questions

## Product limitations (communicated to the business)

| # | Limitation | Mitigation |
|---|---|---|
| L1 | Replies sent from LINE OA Manager (app/web) never reach Salesforce | Business rule: reply from Salesforce only |
| L2 | Each OA has its own LINE plan and monthly message allowance; Salesforce replies are push messages and count | The client sizes plans; `lineAdmin` shows quota; clear "monthly limit" error |
| L3 | Per-rep OA setup in the LINE consoles is manual (~20–30 min per rep) | The Salesforce side is one form in `lineAdmin` |
| L4 | One OA = one rep; splitting a rep's customers means customers must add the new rep's OA | Reassign the whole OA; generic OA names |
| L5 | Chat refresh is polling (~5 s), not instant | Custom notifications for instant alerts |
| L6 | Inbound files limited to ~10 MB by Apex heap/callout limits | "Too large, view in LINE" |
| L7 | LINE bots can't send file attachments; documents go as expiring links | ContentDistribution with expiry |
| L8 | 1:1 chats only | Groups out of scope |
| L9 | Storage grows with message volume | Retention setting |
| L10 | Contact record pages only (no Person Account page support in MVP) | Backlog |
| L11 | PDPA: chats and files stored in Salesforce | Client provides consent/notice; retention |

## Technical risks (verify early; results go to DECISIONS.md)

| Risk | Checked in |
|---|---|
| Stateless token issuance works with Channel ID + secret | M2/M3 |
| Same LINE user ID across OAs under one Provider (auto-link depends on it) | M6 |
| `line.me/R/oaMessage` pre-fill works for users who haven't added the OA yet (iOS/Android) | M6 |
| Automated Process user can send custom notifications and run callout queueables | M3 |
| CustomNotificationType is packageable and resolvable in subscriber orgs | M1/M3 |
| LINE accepts Salesforce `ContentDownloadUrl` for images/video | M7 |
| Reply token validity is long enough for PE → queueable latency | M6 |
| Guest user + package licensing interaction (before any LMA licensing) | Before licensing |
| Scratch org features needed for Sites | M0 |
| `sf-line-dev` (the QA org) is currently registered as a **Dev Hub**. If it also becomes this project's Dev Hub, the org that owns the package is the org that receives the betas, so installs aren't tested in a clean org. A Developer Edition Dev Hub also has low daily limits for scratch orgs and package versions. Recommended: a separate Dev Hub (PBO), with `sf-line-dev` used only as the QA org. | M0 |
| Apex tests create users (up to ~3 per test: Rep A, Rep B, admin). Orgs with no spare "Salesforce"/"Salesforce Platform" licences (a scratch org has 2 + 3, some already used) fail with `LICENSE_LIMIT_EXCEEDED`. Mitigation: `LineTestFactory` uses either licence, tests use the running admin as the admin, and each test creates at most 2 users. Watch this in the package-version build org. | M3 |
| Platform event triggers get batches of up to 2,000 events by default, and the batch size can't be set without a subscriber-side `PlatformEventSubscriberConfig` (not packageable). `LineInboundService` uses a fixed number of queries and DML statements per batch, and notifications are capped at 100 per batch; confirm CPU/heap headroom with a 2,000-event test in the M11 load check. | M11 |
| The M0 "empty beta" may be refused if the package directory has no metadata. Fallback: put one harmless component in the beta (e.g. a single Custom Label). Betas can't be upgraded, so nothing in them is permanent. | M0 |

## Open questions — business (via BA)

1. Can reps keep replying from the LINE OA Manager app, or Salesforce only? (L1)
2. When a rep leaves: does the whole OA move to one new rep (recommended), or are customers split?
3. Should Contact Owner follow the OA's rep on reassignment? (setting exists; what's the default?)
4. Default message retention period?
5. Do managers need to reply on behalf of a rep, or only read?
6. Invite message wording in Thai/English (shown in the customer's LINE).
7. Do target clients use Person Accounts? (affects post-MVP priority)

## Open questions — ours

1. Package name and namespace (permanent).
2. Dev Hub: join the Partner Program and use a PBO now (recommended), or a Developer Edition Dev Hub for development first?
3. Licensing model later (free, per-org or per-user). Affects the guest-user design check above.
4. Can `archive/qa-org-retrieve-2026-09-19/` be deleted? It's a reference retrieve of `sf-line-dev` that was moved out of `force-app/` in M0 (DECISIONS DEC-01).
5. Approve the permission-set differences forced by the platform (DECISIONS DEC-13) and the type of `LINE_Message__c.Public_Url__c` (URL fields max out at 255 characters; DEC-14).
6. Should `LINE_OA_Configuration__c` track field history (`Assigned_Rep__c`, `Is_Active__c`) to meet "admin actions on OAs are logged" (01 §5)? Not in 03 today.
