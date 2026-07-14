#!/usr/bin/env bash

webot_hash_url() {
  curl -fsSL --connect-timeout 10 --max-time 30 "$1" | shasum -a 256 | awk '{print $1}'
}

webot_hash_git_file() {
  local ref="$1"
  local file="$2"
  git show "${ref}:${file}" | shasum -a 256 | awk '{print $1}'
}

webot_wait_for_live_hash() {
  local url="$1"
  local expected="$2"
  local attempts="${PUBLISH_POLL_ATTEMPTS:-18}"
  local sleep_seconds="${PUBLISH_POLL_SLEEP_SECONDS:-10}"
  local actual attempt

  [[ "$attempts" =~ ^[1-9][0-9]*$ ]] || {
    echo "Invalid PUBLISH_POLL_ATTEMPTS: $attempts" >&2
    return 2
  }
  [[ "$sleep_seconds" =~ ^[0-9]+$ ]] || {
    echo "Invalid PUBLISH_POLL_SLEEP_SECONDS: $sleep_seconds" >&2
    return 2
  }

  echo "Waiting for $url to match the released index hash."
  for ((attempt = 1; attempt <= attempts; attempt++)); do
    actual="$(webot_hash_url "$url" 2>/dev/null || true)"
    if [[ "$actual" == "$expected" ]]; then
      echo "PASS live root matches the released index on attempt $attempt/$attempts."
      return 0
    fi
    if (( attempt < attempts )); then
      echo "GitHub Pages has not propagated yet ($attempt/$attempts); waiting ${sleep_seconds}s."
      sleep "$sleep_seconds"
    fi
  done

  echo "Live root did not match the released index within the bounded polling window." >&2
  return 1
}

webot_find_chrome() {
  local candidate
  if [[ -n "${CHROME_BIN:-}" && -x "${CHROME_BIN}" ]]; then
    printf '%s\n' "$CHROME_BIN"
    return 0
  fi
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    google-chrome-stable google-chrome chromium chromium-browser; do
    if [[ "$candidate" == /* && -x "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
    if [[ "$candidate" != /* ]] && command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done
  return 1
}

webot_capture_live_screenshots() {
  local url="$1"
  local output="$2"
  local chrome
  chrome="$(webot_find_chrome)" || {
    echo "Chrome/Chromium is required for live rollback screenshots." >&2
    return 1
  }
  install -d -m 700 "$output"
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=1440,1000 --screenshot="$output/desktop-studio.png" "$url" >/dev/null 2>&1
  "$chrome" --headless=new --disable-gpu --hide-scrollbars \
    --window-size=390,844 \
    --user-agent="Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1" \
    --screenshot="$output/mobile-studio.png" "$url" >/dev/null 2>&1
  [[ -s "$output/desktop-studio.png" && -s "$output/mobile-studio.png" ]] || {
    echo "Live rollback screenshot capture was incomplete." >&2
    return 1
  }
  echo "PASS live desktop/mobile screenshots: $output"
}
