# DeepSeek Balance Tracker

**Track your DeepSeek API spending.** Two shell scripts + a systemd timer. Zero runtime dependencies beyond `curl`, `jq`, and `sqlite3`.

Records your balance every 5 minutes into a SQLite database. Then query it: *how much did I spend today? What's my daily burn rate? How many days until I run out?*

## Install

```bash
git clone https://github.com/stupoid/deepseek-balance-tracker.git
cd deepseek-balance-tracker

# 1. Install sqlite3 if you don't have it (apt, pacman, brew, nix — whatever)

# 2. Put your DeepSeek API key in a file
mkdir -p ~/.config/deepseek-balance
cp secrets.env.example ~/.config/deepseek-balance/secrets.env
chmod 600 ~/.config/deepseek-balance/secrets.env
# Edit the file: replace sk-your-api-key-here with your real key
# Get a key at: https://platform.deepseek.com/api_keys

# 3. Install the systemd timer (runs every 5 minutes, userspace, no root)
mkdir -p ~/.config/systemd/user
cp etc/deepseek-balance.service ~/.config/systemd/user/
cp etc/deepseek-balance.timer ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now deepseek-balance.timer

# 4. Put the commands on your PATH (or skip and use ./bin/...)
ln -s "$(pwd)/bin/deepseek-balance" ~/.local/bin/deepseek-balance
ln -s "$(pwd)/bin/deepseek-balance-poll" ~/.local/bin/deepseek-balance-poll

# Optional: keep the timer running when logged out
loginctl enable-linger
```

Done. Watch it record:

```bash
journalctl --user -u deepseek-balance.service -f
```

## Usage

```bash
deepseek-balance current       # latest balance
deepseek-balance today         # how much you spent today
deepseek-balance history 10    # last 10 snapshots
deepseek-balance summary       # averages, projection
deepseek-balance check-alert   # check balance against alert thresholds
```

Output is human-readable by default:

```
$ deepseek-balance current
USD  $4.03     total  $0.00     granted  $4.03     topped-up  (2026-06-19 07:06:02)

$ deepseek-balance today
USD  spent $0.03 today  (2 snapshots)

$ deepseek-balance history 3
CUR  BALANCE  RECORDED AT
USD  $4.03     2026-06-19 07:06:02
USD  $4.06     2026-06-19 07:02:04

$ deepseek-balance summary
USD  balance $4.03  avg $0.00/day (7d)  $0.00/day (30d)  (1 days tracked)
```

Add `-j` for JSON (scripts, bots, piping to `jq`):

```bash
deepseek-balance -j current | jq '.[0].topped_up_balance'
deepseek-balance -j today | jq '.USD.spend_today'
deepseek-balance -j summary | jq '.USD.estimated_days_left'
deepseek-balance -j check-alert | jq '.USD.alert'
```

## Commands

| Command | What it does |
|---|---|
| `deepseek-balance current` | Latest balance per currency |
| `deepseek-balance today` | Total spend today (UTC) |
| `deepseek-balance recent` | Total spend in the last 60 minutes |
| `deepseek-balance history [N]` | Last N snapshots (default 24) |
| `deepseek-balance summary` | 7d/30d averages, days remaining |
| `deepseek-balance check-alert` | Check balance against alert thresholds |
| `deepseek-balance-poll` | Fetch from API and record (called by timer) |

Flags: `-c USD|CNY` (currency), `-j` (JSON output), `-h` (help).

## How it works

```
systemd timer (every 5 min)
       │
       ▼
  deepseek-balance-poll ──curl──▶ DeepSeek API /user/balance
       │
       ▼
  SQLite DB (~/.local/share/deepseek-balance-tracker/balance.db)
       │
       ▼
  deepseek-balance ◀── any script, bot, or status bar
```

- **Spending** = decrease in `topped_up_balance` between snapshots. Balance increases (top-ups) are ignored.
- **Currency** = `USD`, `CNY`, or `both` — set `CURRENCY` in your secrets file.
- **Interval** = edit `OnCalendar` in the timer file (default: every 5 min).

## Adjust the polling interval

Edit `~/.config/systemd/user/deepseek-balance.timer`:

```ini
# Every 5 minutes (default)
OnCalendar=*:0/5

# Every 15 minutes
OnCalendar=*:0/15

# Every hour
OnCalendar=hourly
```

Then `systemctl --user daemon-reload && systemctl --user restart deepseek-balance.timer`.

## Files

| What | Where |
|---|---|
| Query tool | `bin/deepseek-balance` |
| Poll script | `bin/deepseek-balance-poll` |
| systemd units | `etc/deepseek-balance.service`, `etc/deepseek-balance.timer` |
| Your API key | `~/.config/deepseek-balance/secrets.env` |
| SQLite DB | `~/.local/share/deepseek-balance-tracker/balance.db` |
| Alert state | `~/.local/state/deepseek-balance-tracker/alert-state` |

## Database

All monetary values are stored as **integer cents**. At 5-minute intervals (~288 rows/day), each row is ~75 bytes.

| Retention | Rows | Approx size |
|---|---|---|
| 30 days | ~8,600 | ~650 KB |
| 90 days (default) | ~26,000 | ~2 MB |
| 1 year | ~105,000 | ~8 MB |
| Forever (set `RETENTION_DAYS=0`) | grows ~8 MB/year | — |

Old snapshots are auto-pruned on each poll. Set `RETENTION_DAYS` in your secrets file.

```bash
sqlite3 ~/.local/share/deepseek-balance-tracker/balance.db \
  "SELECT recorded_at, topped_up_balance_cents / 100.0 AS balance
   FROM balance_snapshots WHERE currency = 'USD'
   ORDER BY id DESC LIMIT 5;"
```

## Alert thresholds

Set a threshold in `secrets.env` and the poll script will run a shell command whenever your balance drops below it. Useful for notifications (e.g. tell nanobot to ping you), topping-up scripts, or webhooks.

**Configuration** (in `~/.config/deepseek-balance/secrets.env`):

```bash
# Alert when topped-up balance drops below these amounts (in dollars/yuan)
ALERT_THRESHOLD_USD=2.00
ALERT_THRESHOLD_CNY=10.00

# Path to the alert script (bundled script uses Telegram — see below)
ALERT_COMMAND=/home/kelvin/code/deepseek-balance-tracker/etc/alert-low-balance.sh

# Telegram credentials for the bundled alert script
ALERT_TELEGRAM_BOT_TOKEN=123456:ABC...
ALERT_TELEGRAM_CHAT_ID=123456789
```

**How it works:**

- After each poll, the script checks the latest `topped_up_balance` against each configured threshold.
- If the balance is below threshold and the alert hasn't fired yet → **fires**: state marked `fired`, `ALERT_COMMAND` is executed.
- While the balance stays below threshold, the alert is **not repeated** (no spam).
- When the balance returns above threshold (e.g. after a top-up), the alert **re-arms** automatically.
- Omit a threshold or leave it empty to disable alerts for that currency.

**Environment variables** passed to your alert script:

| Variable | Example | Description |
|---|---|---|
| `DBT_BALANCE` | `0.95` | Current topped-up balance in dollars |
| `DBT_BALANCE_CENTS` | `95` | Balance in integer cents |
| `DBT_THRESHOLD` | `1.00` | The threshold that was breached |
| `DBT_CURRENCY` | `USD` | Which currency triggered the alert |

**Example alert script** (notify via Telegram Bot API):

```bash
#!/usr/bin/env bash
# etc/alert-low-balance.sh  (bundled — just configure secrets.env and go)
# Reads ALERT_TELEGRAM_BOT_TOKEN and ALERT_TELEGRAM_CHAT_ID from secrets.env.
# Receives DBT_BALANCE, DBT_BALANCE_CENTS, DBT_THRESHOLD, DBT_CURRENCY from the poll script.

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
    echo "ALERT: Telegram bot token or chat ID not configured" >&2
    exit 0
fi

MESSAGE="⚠️ DeepSeek balance is low!
Currency: ${DBT_CURRENCY:-?}
Balance: \$${DBT_BALANCE:-?}
Threshold: \$${DBT_THRESHOLD:-?}

Top up: https://platform.deepseek.com/top_up"

curl -sS -X POST "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
    -d "chat_id=${CHAT_ID}" \
    -d "text=${MESSAGE}" \
    >/dev/null 2>&1 || true
```

**Manual check** (no API call — uses latest DB snapshot):

```bash
# Text output
deepseek-balance check-alert
# USD  $4.03     ok        (threshold: $1.00)
# CNY  $50.00    ok        (threshold: $10.00)

# JSON output
deepseek-balance -j check-alert
# {"USD": {"balance": 4.03, "threshold": 1.00, "alert": false}, ...}

# Exit code: 0 = all ok, 1 = alert would fire
```

**Logging:** Alert fires are logged to stderr (→ journald):
```
ALERT: USD balance $0.95 is below threshold $1.00 — executing ALERT_COMMAND
ALERT: USD balance $5.00 is back above threshold $1.00 — alert re-armed
```

State is tracked in `~/.local/state/deepseek-balance-tracker/alert-state`.

## License

MIT
