# 09 — Packaging (Managed 2GP)

## 1. Environments

| Org | Purpose | How code gets there |
|---|---|---|
| Dev Hub (PBO recommended) | Owns the package, creates scratch orgs and package versions | – |
| Namespace org | Holds the registered namespace only | – |
| **Scratch orgs** (namespaced, 7–30 days) | Day-to-day development and Apex tests. Until the namespace exists (before M3), non-namespaced scratch orgs from `sf-line-dev` (DECISIONS DEC-08). | `sf project deploy start` |
| **QA org** = `sf-line-dev` (Developer Edition) | End-to-end tests with real LINE OAs, install and upgrade tests | Install **package versions** only |
| Client orgs | Production and sandboxes | Install **released** versions |

Why scratch orgs: namespaced source can only be deployed to orgs that have the namespace. Deploying to `sf-line-dev` without the
namespace would hide namespace bugs, such as the REST URL, dynamic references and CustomNotificationType lookup.

Real-LINE testing in a scratch org is possible (it needs its own Site and webhook registration), but do it in the QA org with
installed betas. Beta versions can't be upgraded, so uninstall the old beta before installing the next one (QA data is lost; that's fine).

## 2. Project layout

```
sfdx-project.json          namespace "<ns>", one package directory
force-app/main/default/    packaged metadata (everything in the package)
unpackaged/                org-specific metadata for scratch/QA setup (Site, sample flexipage activation, test users)  — NOT in the package
scripts/                   scratch-org setup scripts, sample data, anonymous Apex helpers
config/project-scratch-def.json
```

`sfdx-project.json` (target shape):
```json
{
  "packageDirectories": [
    { "path": "force-app", "default": true, "package": "LINE Connect",
      "versionName": "MVP", "versionNumber": "0.1.0.NEXT" },
    { "path": "unpackaged", "default": false }
  ],
  "namespace": "<ns>",
  "sourceApiVersion": "67.0",
  "packageAliases": { "LINE Connect": "0Ho..." }
}
```
After the first release, add `"ancestorVersion": "HIGHEST"` so upgrades are validated against the last released version.

Scratch definition: Developer edition, `hasSampleData: false`. Add features/settings as needed: e.g. enable Sites, and
`lightningExperienceSettings`. [VERIFY which scratch features Sites needs.] Keep the definition in `config/project-scratch-def.json`.

## 3. Everyday commands

```bash
# new scratch org (namespaced automatically from sfdx-project.json)
sf org create scratch --definition-file config/project-scratch-def.json --alias line-dev --duration-days 14 --target-dev-hub line-devhub --set-default
sf project deploy start --target-org line-dev
sf org assign permset --name LINE_Admin --target-org line-dev
sf apex run test --test-level RunLocalTests --code-coverage --result-format human --wait 20 --target-org line-dev

# beta package version (validation + 75% coverage are required for promotion later)
sf package version create --package "LINE Connect" --installation-key-bypass --code-coverage --wait 60 --target-dev-hub line-devhub
sf package install --package "LINE Connect@0.1.0-1" --target-org sf-line-dev --wait 20 --publish-wait 10

# release (only when the user says so)
sf package version promote --package "LINE Connect@0.1.0-3" --target-dev-hub line-devhub
```
Use an installation key for anything shared outside the team. Store it in a password manager, never in the repo.

## 4. Upgrade-safety rules (from the first **released** version on)

- Treat as permanent: object/field API names, field types, relationship types (lookup ↔ master-detail),
  `global` classes/methods/signatures, custom setting/permission/platform event names, picklist API values.
- Allowed later: new fields/objects/classes, longer text lengths, new picklist values, new optional parameters on non-global code.
- Keep `global` to `LineWebhookResource` only. Don't expose `global` Apex for "extensibility" without a design review.
- Required fields and validation rules on packaged objects: add only with defaults that keep existing data valid.
- Every new version is tested as an **upgrade** in the QA org (install the previous released version → add data → upgrade → run the acceptance checks).

## 5. Subscriber-org realities (design for them)

| Reality | Consequence |
|---|---|
| Unknown validation rules, triggers, flows and required fields on Contact/Event | `Database.*(…, false)` for Contact/Event DML. Log failures. Never block ingestion. |
| Non-English orgs (Thai) | No profile names in code or tests. Labels are translated EN/TH. |
| Time zones | Format times in the user's or Event owner's time zone. Store UTC. |
| Person Accounts may be on | MVP supports Contact pages only; see 08. Queries must not assume `Contact.AccountId` is a business account. |
| Shared Activities may be on/off | Event uses `WhoId` (single) + `WhatId`. Works either way. |
| Multi-currency, record types | Not used by the package |
| Governor limits shared with subscriber automation | Keep our transactions lean; move heavy work to async |
| Guest user security settings | Guest gets only the `LINE_Webhook_Guest` permission set; all record access happens after hand-off, in system mode |
| Package licensing | During private installs: no LMA license enforcement. **Before adding per-user licenses**, check that the Site guest user and Automated Process can still run package code (guest users can't hold package licenses) [VERIFY] |

## 6. Third-party code

- QR library in a static resource `qrcode` (e.g. `qrcode-generator`, MIT). Pin the version, and record the source URL, version and licence in `docs/DECISIONS.md`.
  Load it with `loadScript` from `lightning/platformResourceLoader`, and render to `<canvas>` or an `<img src="data:...">`. It must work under Lightning Web Security.
- No other external JS/CSS. No CDN loads at runtime.

## 7. Security-review readiness (AppExchange later, standard now)

- **Salesforce Code Analyzer**: `sf code-analyzer run --workspace force-app --output-file reports/code-analyzer.html` with no Critical/High findings.
  Justify remaining findings in `docs/DECISIONS.md`, and use a `// NOPMD` suppression only with a reason.
- **CRUD/FLS**:
  - user-facing Apex uses `WITH USER_MODE` / `AccessLevel.USER_MODE`;
  - system-mode classes are limited to the list in 02 §2, each with a justification comment.
- **Sharing:** every class declares `with sharing`, `without sharing` or `inherited sharing`; none is left undeclared.
- **Injection:** no dynamic SOQL/SOSL built from input. If unavoidable, use bind variables only.
- **Secrets:** only in the protected custom setting. They never go to the client side, logs or debug statements.
- **Guest:** one class, one platform event, signature check before anything else. Rate of junk traffic is bounded by rejecting early.
- **LWC:** no `innerHTML` with untrusted data; render message text as text. No `console.log` in packaged code. Links from customers are shown as text, not auto-linked.
- **Remote sites:** only LINE hosts.
- **Outbound public links:** `ContentDistribution` with expiry; no password-free links without expiry.
- Keep a `docs/SECURITY_NOTES.md` explaining each `without sharing` class, the guest surface and the secret storage. This becomes the security review submission.
