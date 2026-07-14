#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
source scripts/lib/live-proof.sh

usage() {
  cat <<'USAGE'
Usage:
  scripts/rollback-live.sh --bundle <origin-master.bundle> --dry-run
  scripts/rollback-live.sh --bundle <origin-master.bundle> --execute --confirm-rollback

The bundle must be a verified pre-publish bundle created under
~/Backups/webot-studio. Execution creates a normal rollback commit and pushes
it to master; it never force-pushes or edits GitHub Pages directly.
USAGE
}

bundle=""
execute=0
confirm=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --bundle)
      [[ $# -ge 2 ]] || { echo "--bundle requires a path." >&2; exit 2; }
      bundle="$2"
      shift 2
      ;;
    --dry-run)
      execute=0
      shift
      ;;
    --execute)
      execute=1
      shift
      ;;
    --confirm-rollback)
      confirm=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$bundle" && -f "$bundle" ]] || { echo "A readable --bundle is required." >&2; exit 2; }
[[ -z "$(git status --porcelain)" ]] || { echo "Refusing rollback from a dirty worktree." >&2; exit 2; }
[[ "$(git branch --show-current)" == "master" ]] || { echo "Refusing rollback outside master." >&2; exit 2; }

bundle_dir="$(cd "$(dirname "$bundle")" && pwd -P)"
backup_base="$(cd "$HOME/Backups/webot-studio" && pwd -P)"
case "$bundle_dir/" in
  "$backup_base"/*) ;;
  *) echo "Rollback bundle must be under $backup_base." >&2; exit 2 ;;
esac
bundle="$bundle_dir/$(basename "$bundle")"
[[ "$(basename "$bundle")" == "origin-master.bundle" ]] || {
  echo "Rollback requires the guarded origin-master.bundle artifact." >&2
  exit 2
}

git bundle verify "$bundle" >/dev/null
target_commit="$(git bundle list-heads "$bundle" | awk '$2 == "refs/remotes/origin/master" {print $1}')"
[[ "$target_commit" =~ ^[0-9a-f]{40}$ ]] || {
  echo "Bundle does not contain exactly the expected origin/master backup ref." >&2
  exit 2
}
git cat-file -e "$target_commit^{commit}"
git show "$target_commit:CNAME" >/dev/null

git fetch origin master
current_remote="$(git rev-parse origin/master)"
current_head="$(git rev-parse HEAD)"
[[ "$current_head" == "$current_remote" ]] || {
  echo "Local master must exactly match origin/master before rollback." >&2
  exit 2
}
[[ "$target_commit" != "$current_head" ]] || { echo "Target is already the current release." >&2; exit 2; }
git merge-base --is-ancestor "$target_commit" "$current_head" || {
  echo "Rollback target is not an ancestor of the current release." >&2
  exit 2
}

payment_hashes() {
  git grep -h -o 'https://buy[.]stripe[.]com/[^"< ]*' "$1" -- '*.html' \
    | sort -u | shasum -a 256 | awk '{print $1}'
}
working_payment_hashes() {
  rg --no-filename -o 'https://buy[.]stripe[.]com/[^"< ]*' --glob '*.html' . \
    | sort -u | shasum -a 256 | awk '{print $1}'
}
current_payment_hash="$(payment_hashes "$current_head")"
target_payment_hash="$(payment_hashes "$target_commit")"
[[ "$current_payment_hash" == "$target_payment_hash" ]] || {
  echo "Refusing rollback because protected payment links differ." >&2
  exit 2
}

echo "Current release:  $current_head"
echo "Rollback target:  $target_commit"
echo "Verified bundle:  $bundle"
if [[ "$execute" -ne 1 ]]; then
  echo "DRY RUN PASS. Re-run with --execute --confirm-rollback to create and publish the rollback commit."
  exit 0
fi
[[ "$confirm" -eq 1 ]] || { echo "Execution also requires --confirm-rollback." >&2; exit 2; }

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
rollback_backup="$HOME/Backups/webot-studio/rollback-$stamp"
install -d -m 700 "$rollback_backup"
git bundle create "$rollback_backup/current-origin-master.bundle" origin/master
git bundle verify "$rollback_backup/current-origin-master.bundle" >/dev/null
chmod 600 "$rollback_backup/current-origin-master.bundle"
git rev-parse origin/master >"$rollback_backup/pre-rollback-commit.txt"
git show origin/master:CNAME >"$rollback_backup/CNAME"
[[ -s "$rollback_backup/CNAME" ]] || { echo "Current-release backup validation failed." >&2; exit 1; }

# Restore the backed-up public tree while retaining the current guarded release
# tooling, so rollback remains recoverable and no direct live edit is required.
git restore --source="$target_commit" --staged --worktree -- .
git restore --source="$current_head" --staged --worktree -- .gitignore scripts project-map.md
[[ -n "$(git diff --cached --name-only)" ]] || { echo "Rollback produced no public changes." >&2; exit 1; }
[[ "$(working_payment_hashes)" == "$current_payment_hash" ]] || {
  echo "Protected payment-link verification failed after rollback preparation." >&2
  exit 1
}
git diff --cached --check
git commit -m "rollback: restore Studio public release $(printf '%.12s' "$target_commit")"

git push origin HEAD:master
expected_index_hash="$(webot_hash_git_file HEAD index.html)"
webot_wait_for_live_hash "https://webot.studio/index.html" "$expected_index_hash"
webot_capture_live_screenshots "https://webot.studio/index.html" "$rollback_backup/live-proof"
echo "PASS rollback published with a normal commit; recovery bundle: $rollback_backup/current-origin-master.bundle"
