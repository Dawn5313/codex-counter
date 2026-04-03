#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CODE_SCRIPT="$ROOT_DIR/scripts/get_latest_openai_code.applescript"
SESSION="${PLAYWRIGHT_SESSION:-chatgpt-anon-register}"
ACCOUNT_NAME="${ACCOUNT_NAME:-River Vale}"
BIRTH_YEAR="${BIRTH_YEAR:-1990}"
BIRTH_MONTH="${BIRTH_MONTH:-01}"
BIRTH_DAY="${BIRTH_DAY:-08}"
RELAY_EMAIL="${RELAY_EMAIL:-}"
PASSWORD="${PASSWORD:-}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'missing required command: %s\n' "$1" >&2
    exit 127
  }
}

js_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

pw() {
  playwright-cli --session "$SESSION" "$@"
}

run_code() {
  local snippet="$1"
  pw run-code "$snippet" >/dev/null
}

sleep_brief() {
  sleep "${1:-1}"
}

if [[ -z "$RELAY_EMAIL" ]]; then
  printf 'usage: RELAY_EMAIL=<fresh_relay@icloud.com> %s\n' "$0" >&2
  exit 64
fi

require_cmd playwright-cli
require_cmd osascript
require_cmd openssl

if [[ -z "$PASSWORD" ]]; then
  PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 24)"
fi

EMAIL_JS="$(js_escape "$RELAY_EMAIL")"
PASSWORD_JS="$(js_escape "$PASSWORD")"
NAME_JS="$(js_escape "$ACCOUNT_NAME")"
YEAR_JS="$(js_escape "$BIRTH_YEAR")"
MONTH_JS="$(js_escape "$BIRTH_MONTH")"
DAY_JS="$(js_escape "$BIRTH_DAY")"

pw --browser chrome --headed open https://chat.com >/dev/null
sleep_brief 2

run_code "(page) => page.getByTestId('signup-button').click()"
sleep_brief
run_code "(page) => page.getByRole('textbox', { name: '电子邮件地址' }).fill(\"$EMAIL_JS\")"
run_code "(page) => page.getByRole('button', { name: '继续', exact: true }).click()"
sleep_brief 2

run_code "(page) => page.getByRole('textbox', { name: '密码' }).fill(\"$PASSWORD_JS\")"
run_code "(page) => page.getByRole('button', { name: '继续', exact: true }).click()"
sleep_brief 2

CODE="$(osascript "$CODE_SCRIPT")"
CODE_JS="$(js_escape "$CODE")"

run_code "(page) => page.getByRole('textbox', { name: '验证码' }).fill(\"$CODE_JS\")"
run_code "(page) => page.getByRole('button', { name: '继续', exact: true }).click()"
sleep_brief 2

run_code "(page) => page.getByRole('textbox', { name: '全名' }).fill(\"$NAME_JS\")"
run_code "(page) => page.getByRole('spinbutton', { name: '年, 生日日期' }).fill(\"$YEAR_JS\")"
run_code "(page) => page.getByRole('spinbutton', { name: '月, 生日日期' }).fill(\"$MONTH_JS\")"
run_code "(page) => page.getByRole('spinbutton', { name: '日, 生日日期' }).fill(\"$DAY_JS\")"
run_code "(page) => page.getByRole('button', { name: '完成帐户创建' }).click()"
sleep_brief 3

SNAPSHOT_OUTPUT="$(pw snapshot)"

printf 'REGISTERED_EMAIL=%s\n' "$RELAY_EMAIL"
printf 'PASSWORD=%s\n' "$PASSWORD"
printf 'PLAYWRIGHT_SESSION=%s\n' "$SESSION"
printf '%s\n' "$SNAPSHOT_OUTPUT"
