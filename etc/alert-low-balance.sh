#!/usr/bin/env bash
# DeepSeek Balance Alert — sends notification via Telegram Bot API
#
# Called by deepseek-balance-poll when balance drops below threshold.
# Receives these env vars from the poll script:
#   DBT_BALANCE        Balance as dollars (e.g. "1.23")
#   DBT_BALANCE_CENTS  Balance as integer cents (e.g. 123)
#   DBT_THRESHOLD      Threshold from secrets.env (e.g. "2.00")
#   DBT_CURRENCY       "USD" or "CNY"
#
# Telegram credentials are read from the same secrets.env file:
#   ALERT_TELEGRAM_BOT_TOKEN   Your Telegram bot token
#   ALERT_TELEGRAM_CHAT_ID     Your Telegram numeric chat/user ID
#
# If those vars are already set in the environment, secrets.env is not read.

set -euo pipefail

SECRETS_FILE="${SECRETS_FILE:-$HOME/.config/deepseek-balance/secrets.env}"

# Source secrets if Telegram vars not already in environment
if [ -z "${ALERT_TELEGRAM_BOT_TOKEN:-}" ] || [ -z "${ALERT_TELEGRAM_CHAT_ID:-}" ]; then
    if [ -f "$SECRETS_FILE" ]; then
        eval "$(grep -E '^(ALERT_TELEGRAM_BOT_TOKEN|ALERT_TELEGRAM_CHAT_ID)=' "$SECRETS_FILE" 2>/dev/null || true)"
    fi
fi

BOT_TOKEN="${ALERT_TELEGRAM_BOT_TOKEN:-}"
CHAT_ID="${ALERT_TELEGRAM_CHAT_ID:-}"

if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
    echo "ALERT: Telegram bot token or chat ID not configured — cannot send alert" >&2
    # Don't fail the poll; the alert is still logged to journald by the poll script.
    exit 0
fi

# --- Build message ---------------------------------------------------------
MESSAGE=$(cat <<EOF
⚠️ DeepSeek balance is low!

Currency: ${DBT_CURRENCY:-?}
Balance: \$${DBT_BALANCE:-?}
Threshold: \$${DBT_THRESHOLD:-?}

Top up: https://platform.deepseek.com/top_up
EOF
)

# --- Send via Telegram Bot API ---------------------------------------------
curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${MESSAGE}" \
    >/dev/null 2>&1 || {
    echo "ALERT: Failed to send Telegram notification (curl exit code $?)" >&2
    exit 0  # don't fail the poll
}
