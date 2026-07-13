#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
[[ "${1:-}" == "--execute" ]] || { echo "Dry run only. Re-run with --execute to publish."; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "Refusing to publish a dirty worktree."; exit 2; }
[[ "$(git branch --show-current)" == "main" ]] || { echo "Refusing to publish outside main."; exit 2; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root="${HOME}/Backups/webot-studio/publish-${stamp}"
install -d -m 700 "$backup_root"
git fetch origin main
git bundle create "$backup_root/origin-main.bundle" origin/main
git bundle verify "$backup_root/origin-main.bundle" >/dev/null
chmod 600 "$backup_root/origin-main.bundle"
git show origin/main:CNAME >"$backup_root/CNAME"
[[ -s "$backup_root/CNAME" ]] || { echo "Backup validation failed: CNAME missing."; exit 1; }

PROOF_DIR="$backup_root/local-proof" scripts/test-local.sh
git push origin HEAD:main
BASE_URL="https://webot.studio" PROOF_DIR="$backup_root/live-proof" node scripts/test-local.mjs
echo "PASS published and browser-verified; rollback bundle: $backup_root/origin-main.bundle"
