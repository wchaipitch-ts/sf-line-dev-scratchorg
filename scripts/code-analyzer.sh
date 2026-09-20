#!/usr/bin/env bash
# Runs Salesforce Code Analyzer on the packaged source (09 §7).
# Fails (non-zero exit) on any High or Critical finding (severity 1-2).
#
#   ./scripts/code-analyzer.sh                  # whole force-app
#   ./scripts/code-analyzer.sh <file> [<file>]  # only these files (workspace stays force-app)
#
# Reports: reports/code-analyzer.html and reports/code-analyzer.json
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p reports

targets=()
for f in "$@"; do
    targets+=(--target "$f")
done

sf code-analyzer run \
    --workspace force-app \
    ${targets[@]+"${targets[@]}"} \
    --rule-selector Recommended \
    --rule-selector Security \
    --rule-selector AppExchange \
    --severity-threshold 2 \
    --view table \
    --output-file reports/code-analyzer.html \
    --output-file reports/code-analyzer.json
