# CLAUDE.md — sf-line-dev

Salesforce DX project for **LINE Connect** (working name): a **managed 2GP package** that connects LINE Official Accounts to Salesforce.
Each sales rep has their own OA and chats with Contacts from Salesforce. The target is an **MVP** installed privately in client orgs, built to
**AppExchange security-review standards** for a later listing. Claude Code does all of the implementation.

The spec is in `docs/`. Start at `docs/README.md`.

## Project facts

- Package type: **Managed 2GP**. The namespace `<ns>` and package name are set in M0 (see `docs/09-packaging.md`).
- `sourceApiVersion` 67.0. Every `-meta.xml` uses `<apiVersion>67.0</apiVersion>`.
- **Orgs:**
  - Dev Hub alias `line-devhub`.
  - Development happens in **namespaced scratch orgs** (default alias `line-dev`).
  - `sf-line-dev` is the **QA org**. It gets **installed package versions only**, never `sf project deploy`.
- `force-app/` = everything that ships in the package. `unpackaged/` = org setup for scratch/QA only.
- Fresh project: no existing trigger framework, logger or test factory. Use the conventions below.
- Not a git repo yet. Don't `git init`, commit or push unless asked.

## Source of truth

| Topic | File |
|---|---|
| Scope, flows, MVP acceptance criteria | `docs/01-requirements.md` |
| Components and design decisions D1–D12 | `docs/02-architecture.md` |
| **Schema (fixed)** | `docs/03-data-model.md` |
| LINE API | `docs/04-line-api-reference.md` |
| Setup: ours, LINE, subscriber | `docs/05-setup-runbook.md` |
| Milestones M0–M12 and done-criteria | `docs/06-implementation-plan.md` |
| Tests | `docs/07-testing.md` |
| Limits, risks, open questions | `docs/08-limitations-and-open-questions.md` |
| Packaging, environments, upgrade safety, security review | `docs/09-packaging.md` |
| Decisions made and [VERIFY] results | `docs/DECISIONS.md` (keep current) |
| Security review notes | `docs/SECURITY_NOTES.md` (keep current) |

If the code must differ from the spec, **ask first**. Then record the change in `DECISIONS.md` and update the spec file.

## Hard rules

1. **Schema is fixed.** Business objects: User, Contact, Event, `LINE_OA_Configuration__c`, `LINE_Conversation__c`, `LINE_Message__c`.
   No new business objects, relationships or renames without asking. The supporting metadata in 03 §4 is allowed.
2. **Upgrade safety.** Everything packaged is effectively permanent once released (09 §4). Before creating any packaged
   object, field, picklist value, `global` member, custom setting, custom permission or event, check that its name and type
   match the spec exactly.
   - `global` is allowed **only** on `LineWebhookResource`.
   - Never make destructive changes to packaged metadata without asking.
3. **No AI services.** No runtime AI/LLM calls (no Gemini, OpenAI, Einstein or Agentforce). The only external hosts are `api.line.me` and `api-data.line.me`.
4. **Secrets.**
   - Channel secrets live **only** in the protected custom setting `LINE_OA_Credential__c`. Only `LineCredentialStore` touches it.
   - Never put a secret or access token in a DTO, LWC, log, `System.debug`, error message, test, script or doc.
   - Tests use fake values only.
   - If the user pastes a real secret, use it only in the command that needs it, and never write it to a file.
5. **Webhook.**
   - Verify `X-Line-Signature` over the raw body before anything else.
   - The guest user gets only `LINE_Webhook_Guest`.
   - The webhook does no business DML and no callouts; it only publishes `LINE_Webhook_Event__e`.
6. **Callouts before DML** in every transaction. No callouts in triggers; use `LineCalloutQueueable`.
7. **Unknown subscriber orgs.**
   - DML on Contact/Event uses `Database.*(…, false)` and logs failures. It must never block message storage.
   - No profile names, hardcoded IDs or org-specific URLs in code or tests.
   - No dynamic SOQL on package fields.
8. **Security-review standard** (09 §7):
   - user-facing Apex runs in user mode;
   - every class declares its sharing;
   - `without sharing` only where 02 §2 lists it, with a justification comment;
   - Code Analyzer has no Critical/High findings;
   - no `console.log` or `innerHTML` with untrusted data in LWC.
9. **[VERIFY] items:** check the current LINE or Salesforce docs before relying on them, and record the result in `DECISIONS.md`.
10. **[HUMAN] steps** (LINE consoles, Dev Hub/namespace, Sites, installs that need browser login):
    - stop and list exactly what the user must do and which values to send back;
    - never invent IDs, URLs or secrets.
11. **Package versions:** create beta versions only at the milestones that call for them, or when asked. **Never promote** a version without explicit approval.

## Workflow per milestone

1. Re-read the milestone in `docs/06-implementation-plan.md` and the spec sections it touches.
2. Build it. Keep it deployable on its own; if the change is large, split it into small deploys.
3. Check it:
   - `npm run prettier:verify`
   - `npm run lint`
   - `npm run test:unit` (for LWC)
   - `sf code-analyzer run` on changed files
4. Deploy to the scratch org and run the tests for the touched classes. Fix any failure before moving on.
5. Report back:
   - what was built;
   - test results and coverage;
   - Code Analyzer summary;
   - [HUMAN] steps, with exact Setup paths;
   - [VERIFY] results;
   - new risks or questions, also added to 08.

   Then **stop** and wait for the user.

## Commands

```bash
./scripts/setup-scratch.sh                                    # new scratch org, deploy, perm sets, test users, settings
sf project deploy start --target-org line-dev --wait 10
sf apex run test --class-names <Class>Test --target-org line-dev --code-coverage --result-format human --wait 10
sf apex run test --test-level RunLocalTests --target-org line-dev --code-coverage --result-format human --wait 20
sf code-analyzer run --workspace force-app --output-file reports/code-analyzer.html
sf package version create --package "LINE Connect" --installation-key-bypass --code-coverage --wait 60 --target-dev-hub line-devhub
sf package install --package "<version alias>" --target-org sf-line-dev --wait 20 --publish-wait 10
npm run prettier && npm run lint && npm run test:unit
```
Ask before: deleting orgs, uninstalling the package from the QA org, `sf package version promote`, or changing Dev Hub settings.

## Apex conventions

- **Naming:**
  - classes `Line<Purpose>`;
  - tests `<Class>Test`;
  - one trigger per object, named `<Object>Trigger` (`LineOAConfigTrigger`, `LineWebhookEventTrigger`).
- **Triggers:** no logic in the trigger itself. Handlers extend `LineTriggerHandler` (switch on `Trigger.operationType`, static bypass).
- **Sharing:**
  - classes called from LWC are `with sharing` and use `WITH USER_MODE` / `AccessLevel.USER_MODE`;
  - admin entry points also check `FeatureManagement.checkPermission('LINE_Admin')`.
- **Bulkify:**
  - no SOQL or DML in loops;
  - the platform event handler handles 200 events;
  - one `LineCalloutQueueable` per transaction, carrying a work list, which chains itself for the remainder.
- **Upserts:** use the external IDs from 03 (`Unique_Key__c`, `Webhook_Event_Id__c`, `Channel_Id__c`, `LINE_Invite_Code__c`).
- **HTTP:** only `LineApiClient`. Non-2xx responses → `LineApiException(statusCode, lineMessage)`. Use typed DTOs for JSON.
- **Errors:**
  - catch at entry points (webhook, platform event handler, queueables, batches, `@AuraEnabled` methods);
  - log with `LineLogger` (buffered, `flush()` at the end, never throws);
  - rethrow to LWC as `AuraHandledException` with a Custom Label message.
  - Use `EventBus.RetryableException` only for transient errors.
- **Config:**
  - settings only via `LineSettings` (defaults in code);
  - the namespace only via `LineNamespace`;
  - no literals for IDs or URLs except the LINE base URLs in `LineApiClient`.
- **Queries:** selective (indexed filters), keyset pagination (`Sent_At__c`, `Id`) with `LIMIT`. Never `OFFSET` on messages.
- **Documentation:** ApexDoc on public methods. Comments explain *why*.

## LWC conventions

- Components: `lineChat`, `lineInbox`, `lineInvite`, `lineAdmin`.
- **Apex calls:** imperative calls for anything polled or mutable. `@wire` only for static data.
- **Polling:**
  - interval from settings;
  - only while `document.visibilityState === 'visible'`;
  - clear timers in `disconnectedCallback`.
- **UI:**
  - SLDS and base components first, with minimal CSS;
  - all text from Custom Labels (EN + TH);
  - message text rendered as text, never HTML;
  - times in the user's locale and time zone.
- **QR:** the `qrcode` static resource, loaded via `loadScript`. No CDNs.
- **Jest:** a test for every component (render, empty state, send/error, polling on/off).

## Metadata conventions

- Every object and field has a `<description>`. API names exactly as in 03.
- Permission sets: only `LINE_Chat_User`, `LINE_Admin` and `LINE_Webhook_Guest`. Don't package profiles.
- Custom Labels are prefixed `LINE_`, with Thai translations in `translations/th.translation-meta.xml`.
- Record pages are not auto-activated; subscribers add components themselves (install guide).

## Testing

- Every class ≥ 75%, overall ≥ 85%. Assert behaviour, not just coverage.
- Build test data with `LineTestFactory` (users picked by permission, not profile name). Don't use `SeeAllData=true`.
- Use `LineHttpMock` for all callouts. Build webhook tests with a signed `RestContext.request` + `Test.getEventBus().deliver()` (07 §1).
- Use `System.runAs` for visibility cases. Include at least one "subscriber validation rule" style failure test for Contact and for Event DML.
- Cover every case in `docs/07-testing.md` for the milestone being built.

## Communication

- Keep updates short. At the end of each milestone, give a checklist of [HUMAN] actions.
- If the spec, the LINE docs and platform behaviour disagree, say so and propose a fix before coding.
- Keep `docs/08-limitations-and-open-questions.md`, `DECISIONS.md` and `SECURITY_NOTES.md` up to date.
