# 05 — Setup Runbook

Legend: **[HUMAN]** = a person has to do it in a UI or console. **[CLAUDE]** = Claude Code can do it from the CLI.

## Part A — Our side: packaging foundation (once)

| # | Step | Who |
|---|---|---|
| A1 | **Decide which org is the Dev Hub. Recommended: a Partner Business Org (PBO)** from the Salesforce Partner Program. The Dev Hub **owns the package**, and moving a package to another Dev Hub later is hard. An AppExchange listing and LMA (licensing) need the PBO. A Developer Edition Dev Hub works for development, but has low scratch-org and package-version limits. | [HUMAN] |
| A2 | In the Dev Hub: Setup → Dev Hub → **Enable Dev Hub** and **Enable Unlocked Packages and Second-Generation Managed Packages** | [HUMAN] |
| A3 | Sign up a **separate** Developer Edition org as the **namespace org** → Setup → Package Manager → register the namespace (short, permanent, e.g. `lineconn`) | [HUMAN] |
| A4 | Dev Hub → App Launcher → **Namespace Registries** → Link Namespace (log in to the namespace org) | [HUMAN] |
| A5 | `sf org login web --set-default-dev-hub --alias line-devhub` | [HUMAN] runs, or [CLAUDE] with the browser |
| A6 | Set `"namespace": "<ns>"` in `sfdx-project.json`. Restructure the package directory (see 09 §2). Update the scratch definition. | [CLAUDE] |
| A7 | `sf package create --name "LINE Connect" --package-type Managed --path force-app --target-dev-hub line-devhub` (package name TBD) | [CLAUDE] |
| A8 | `sf-line-dev` (existing Developer Edition) becomes the **QA org**. It never gets source deploys, only **installed package versions** (beta, then released). | – |

## Part B — LINE side, per client

1. **[HUMAN]** The client creates a company **LINE Business ID** that owns all their OAs.
2. **[HUMAN]** In the LINE Developers Console, create **one Provider** per client. All that client's rep OAs must be under it.
3. For each rep OA:
   - **[HUMAN]** Create the OA under the Business ID (a generic name helps handover, e.g. "ABC Sales – Team 3").
   - **[HUMAN]** Settings → Messaging API → Enable → choose the client's Provider.
   - **[HUMAN]** Response settings: Webhook **ON**; Auto-response **OFF**; Greeting optional. Chat ON/OFF is the client's decision (replies sent from OA Manager aren't captured).
   - **[HUMAN]** Developers Console → channel: copy the **Channel ID** and **Channel secret**. Messaging API tab: **Use webhook ON**, **Webhook redelivery ON**.
   - **[HUMAN]** Send the Channel ID and secret to the client's Salesforce admin over a secure channel.

## Part C — Subscriber org: install and configure (once per client org)

This is the install guide we give clients. Keep it this short: every extra step is a support ticket.

| # | Step |
|---|---|
| C1 | Install the package from the install link (Admins Only, or specific profiles) |
| C2 | Setup → Sites: register a site domain if none exists; create site `LineWebhook` (active; any home page) |
| C3 | Site → Public Access Settings → guest user → assign permission set **LINE_Webhook_Guest** |
| C4 | Assign **LINE_Admin** to admins and **LINE_Chat_User** to reps and managers |
| C5 | App Launcher → LINE Chat → **LINE Admin** tab → Settings: paste the site base URL, pick the fallback owner, and review retention, invite expiry and daily sync. **Schedule nightly jobs**. |
| C6 | Lightning App Builder → Contact record page → add **lineChat** → activate. Optionally add **lineInbox** to the Home page. |
| C7 | Optional: create a queue that supports LINE Conversation and use it as the fallback owner |

## Part D — Per rep OA (in the LINE Admin tab)

Register OA: Channel ID + Channel secret + rep. The package does the following, making all callouts before any DML:
1. Issues a stateless token (checks the ID and secret).
2. `GET /v2/bot/info` → bot user ID, basic ID, name, picture.
3. Sets the webhook URL (`<Site_Base_Url__c>/services/apexrest/<ns>/line/webhook`) and runs the webhook test.
4. Saves `LINE_OA_Configuration__c` and the secret in the protected setting. Shows the result.

## Part E — Handover (rep leaves or changes role)

1. **[HUMAN]** LINE Admin tab: **Reassign** the OA to the new rep, or **Deactivate** it (→ fallback owner). The batch moves ownership.
2. **[HUMAN]** LINE OA Manager: remove the old rep's access; add the new rep if they use the app.
3. **[HUMAN]** LINE Developers Console: reissue the channel secret → LINE Admin tab → **Rotate secret**.
4. **[HUMAN]** Optional: rename the OA or change its picture (verified accounts may need LINE review).
