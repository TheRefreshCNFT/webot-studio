# Project Map: webot-studio

## Purpose

Static public Studio marketing, pricing, and intake surface for
`https://webot.studio`.

## Runtime and release

- GitHub Pages publishes from `TheRefreshCNFT/webot-studio` branch `master`.
- Local git is the source of truth; never edit the live site directly.
- `scripts/test-local.sh` runs the desktop/mobile browser acceptance path.
- `scripts/publish-live.sh` is the backup-first guarded publish entry point.
- `scripts/rollback-live.sh` is the backup-first guarded GitHub Pages rollback
  entry point.
- `scripts/lib/live-proof.sh` contains bounded live propagation and screenshot
  helpers shared by publish and rollback.

## Public truth surfaces

- `index.html`: Studio family chooser and subscription surface.
- `agent-jobs.html`: crawlable five-family delivery summary.
- `pricing.html`: current subscription tiers and protected payment links.
- `robots.txt`, `sitemap.xml`, and `llms.txt`: crawler and assistant truth.

## Safety boundaries

- Preserve all Stripe payment links unless the owner explicitly approves an
  exact payment change.
- A publish or rollback must start from clean `master`, back up and verify the
  current remote branch, poll boundedly for GitHub Pages propagation, and save
  desktop/mobile proof.
