#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib/live-proof.sh
[[ "${1:-}" == "--execute" ]] || { echo "Dry run only. Re-run with --execute to publish."; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "Refusing to publish a dirty worktree."; exit 2; }
[[ "$(git branch --show-current)" == "master" ]] || { echo "Refusing to publish outside master."; exit 2; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
backup_root="${HOME}/Backups/webot-studio/publish-${stamp}"
install -d -m 700 "$backup_root"
git fetch origin master
git bundle create "$backup_root/origin-master.bundle" origin/master
git bundle verify "$backup_root/origin-master.bundle" >/dev/null
chmod 600 "$backup_root/origin-master.bundle"
git rev-parse origin/master >"$backup_root/pre-publish-commit.txt"
chmod 600 "$backup_root/pre-publish-commit.txt"
git show origin/master:CNAME >"$backup_root/CNAME"
[[ -s "$backup_root/CNAME" ]] || { echo "Backup validation failed: CNAME missing."; exit 1; }
printf 'scripts/rollback-live.sh --bundle %q --execute --confirm-rollback\n' \
  "$backup_root/origin-master.bundle" >"$backup_root/rollback-command.txt"
chmod 600 "$backup_root/rollback-command.txt"

PROOF_DIR="$backup_root/local-proof" scripts/test-local.sh
git push origin HEAD:master
expected_index_hash="$(webot_hash_git_file HEAD index.html)"
webot_wait_for_live_hash "https://webot.studio/index.html" "$expected_index_hash"
BASE_URL="https://webot.studio" PROOF_DIR="$backup_root/live-proof" node scripts/test-local.mjs
echo "PASS published and browser-verified; rollback bundle: $backup_root/origin-master.bundle"
