#!/usr/bin/env bash
# Creates a namespaced scratch org for LINE Connect and prepares it for development (06 M0).
#
#   ./scripts/setup-scratch.sh [alias]          # default alias: line-dev
#
# Environment overrides:
#   DEVHUB=line-devhub   Dev Hub alias
#   DAYS=14              scratch org lifetime (1-30)
#   SKIP_CREATE=1        reuse an existing org with this alias (re-run the setup steps only)
#
# Steps: create scratch org → deploy force-app + unpackaged → create the LineWebhook Site → assign permission sets
# (admin, 2 test reps, Site guest) → seed LINE_Settings__c. Steps whose metadata isn't built yet are skipped.
set -euo pipefail

ALIAS="${1:-line-dev}"
DEVHUB="${DEVHUB:-line-devhub}"
DAYS="${DAYS:-14}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { printf '\n==> %s\n' "$*"; }
has_source() { [ -n "$(find "$1" -type f -not -name '.DS_Store' -not -name '.gitkeep' 2>/dev/null | head -1)" ]; }
has_permset() { [ -f "force-app/main/default/permissionsets/$1.permissionset-meta.xml" ]; }

if [ "${SKIP_CREATE:-0}" != "1" ]; then
    log "Creating scratch org '$ALIAS' ($DAYS days) from Dev Hub '$DEVHUB'"
    sf org create scratch \
        --definition-file config/project-scratch-def.json \
        --alias "$ALIAS" \
        --duration-days "$DAYS" \
        --target-dev-hub "$DEVHUB" \
        --set-default \
        --wait 20
fi

log "Deploying source"
deploy_dirs=()
has_source force-app && deploy_dirs+=(--source-dir force-app)
has_source unpackaged && deploy_dirs+=(--source-dir unpackaged)
sf project deploy start "${deploy_dirs[@]}" --target-org "$ALIAS" --wait 20

log "Creating the LineWebhook Site"
ADMIN_USERNAME="$(sf org display --target-org "$ALIAS" --json | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>console.log(JSON.parse(s).result.username))')"
SITE_TMP="$(mktemp -d)"
trap 'rm -rf "$SITE_TMP"' EXIT
cp -R scripts/templates/site/. "$SITE_TMP/"
sed -i '' "s|__ADMIN_USERNAME__|$ADMIN_USERNAME|g" "$SITE_TMP/sites/LineWebhook.site"
sf project deploy start --metadata-dir "$SITE_TMP" --target-org "$ALIAS" --wait 20

if has_permset LINE_Admin; then
    log "Assigning LINE_Admin to the admin user"
    sf org assign permset --name LINE_Admin --target-org "$ALIAS" || true
fi

log "Creating test reps (Rep A: English, Rep B: Thai)"
sf apex run --file scripts/apex/create-test-users.apex --target-org "$ALIAS" >/dev/null

if has_permset LINE_Webhook_Guest; then
    log "Assigning LINE_Webhook_Guest to the Site guest user"
    sf apex run --file scripts/apex/assign-guest-permset.apex --target-org "$ALIAS" >/dev/null
fi

if [ -d force-app/main/default/objects/LINE_Settings__c ]; then
    log "Seeding LINE_Settings__c"
    sf apex run --file scripts/apex/seed-settings.apex --target-org "$ALIAS" >/dev/null
fi

log "Done. Open the org with: sf org open --target-org $ALIAS"
