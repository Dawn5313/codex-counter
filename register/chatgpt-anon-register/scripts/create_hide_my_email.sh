#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OCR_SWIFT="$ROOT_DIR/scripts/ocr_text.swift"
HIDE_MY_EMAIL_LABEL="${HIDE_MY_EMAIL_LABEL:-Codex}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

take_screenshot() {
  local image_path="$TMP_DIR/shot-$(date +%s%N).png"
  screencapture -x "$image_path"
  printf '%s\n' "$image_path"
}

find_line() {
  local image_path="$1"
  local regex="$2"
  local strategy="${3:-first}"

  case "$strategy" in
    first)
      swift "$OCR_SWIFT" "$image_path" "$regex" | head -n 1
      ;;
    leftmost)
      swift "$OCR_SWIFT" "$image_path" "$regex" | awk -F '\t' '
        NR == 1 { best = $0; best_x = $2 + 0; next }
        ($2 + 0) < best_x { best = $0; best_x = $2 + 0 }
        END { if (best != "") print best }'
      ;;
    topmost)
      swift "$OCR_SWIFT" "$image_path" "$regex" | awk -F '\t' '
        NR == 1 { best = $0; best_y = $3 + 0; next }
        ($3 + 0) < best_y { best = $0; best_y = $3 + 0 }
        END { if (best != "") print best }'
      ;;
    *)
      printf 'unknown strategy: %s\n' "$strategy" >&2
      exit 64
      ;;
  esac
}

click_match() {
  local regex="$1"
  local strategy="${2:-first}"
  local attempts="${3:-8}"
  local image_path line left top width height x y

  for ((attempt = 1; attempt <= attempts; attempt++)); do
    image_path="$(take_screenshot)"
    line="$(find_line "$image_path" "$regex" "$strategy" || true)"
    if [[ -n "$line" ]]; then
      IFS=$'\t' read -r _ left top width height <<<"$line"
      x=$((left + width / 2))
      y=$((top + height / 2))
      cliclick "c:${x},${y}"
      return 0
    fi
    sleep 1
  done

  printf 'could not find on-screen text matching: %s\n' "$regex" >&2
  return 1
}

read_new_relay_email() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
	tell process "System Settings"
		set ecs to entire contents of window 1
		set best_text to ""
		set best_y to 999999
		repeat with e in ecs
			try
				if (role of e as text) is "AXStaticText" then
					set candidate to name of e as text
					if candidate contains "@icloud.com" then
						set p to position of e
						set y to item 2 of p
						if y > 200 and y < best_y then
							set best_y to y
							set best_text to candidate
						end if
					end if
				end if
			end try
		end repeat
		return best_text
	end tell
end tell
APPLESCRIPT
}

fill_label_and_continue() {
  local label="$1"

  LABEL_TEXT="$label" osascript <<'APPLESCRIPT'
set target_label to system attribute "LABEL_TEXT"

tell application "System Events"
	tell process "System Settings"
		set ecs to entire contents of window 1
		set best_field to missing value
		set best_y to 999999
		
		repeat with e in ecs
			try
				if (role of e as text) is "AXTextField" then
					set current_value to value of e as text
					set p to position of e
					set y to item 2 of p
					if current_value is "" and y > 200 and y < best_y then
						set best_y to y
						set best_field to e
					end if
				end if
			end try
		end repeat
		
		if best_field is missing value then error "No writable label field found"
		
		set focused of best_field to true
		delay 0.2
		keystroke target_label
		delay 0.5
		
		repeat with e in ecs
			try
				if (role of e as text) is "AXButton" and (name of e as text) is "继续" then
					click e
					return "continued"
				end if
			end try
		end repeat
		
		error "No continue button found"
	end tell
end tell
APPLESCRIPT
}

dismiss_completion() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
	tell process "System Settings"
		repeat 5 times
			try
				click button "完成" of window 1
				return "dismissed"
			end try
			delay 1
		end repeat
	end tell
end tell
return "no completion dialog found"
APPLESCRIPT
}

require_cmd osascript
require_cmd cliclick
require_cmd screencapture
require_cmd swift
require_cmd awk

osascript -e 'tell application "System Settings" to activate'
sleep 2

# This flow is tuned for the Simplified Chinese macOS UI seen in the original run.
click_match '^iCloud$' leftmost
sleep 2
click_match '隐藏邮件地址' topmost
sleep 2
click_match '创建新地址' first
sleep 2

RELAY_EMAIL="$(read_new_relay_email)"
if [[ -z "$RELAY_EMAIL" ]]; then
  printf 'failed to read the new relay address from System Settings\n' >&2
  exit 1
fi

fill_label_and_continue "$HIDE_MY_EMAIL_LABEL"
sleep 2
dismiss_completion >/dev/null || true

printf '%s\n' "$RELAY_EMAIL"
