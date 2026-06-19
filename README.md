# DeepSeek Balance Tracker

**Track your DeepSeek API spending.** Two shell scripts + a systemd timer. Zero runtime dependencies beyond `curl`, `jq`, and `sqlite3`.

Records your balance every 5 minutes into a SQLite database. Then query it: *how much did I spend today? What's my daily burn rate? How many days until I run out?*

## Install

```bash
git clone https://github.com/<you>/deepseek-balance-tracker.git
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
```

Output is human-readable by default:

```
$ deepseek-balance current
USD  $4.16     total  $0.00     granted  $4.16     topped-up  (2026-06-19 06:41 UTC)

$ deepseek-balance today
USD  spent $0.06 today  (9 snapshots)

$ deepseek-balance history 3
CUR  BALANCE  RECORDED AT
USD  $4.16    2026-06-19 06:41:56
USD  $4.17    2026-06-19 06:41:02
USD  $4.18    2026-06-19 06:38:02

$ deepseek-balance summary
USD  balance $4.16  avg $0.02/day (7d)  $0.01/day (30d)  ~347 days left  (1 day tracked)
```

Add `-j` for JSON (scripts, bots, piping to `jq`):

```bash
deepseek-balance -j current | jq '.[0].topped_up_balance'
deepseek-balance -j today | jq '.USD.spend_today'
deepseek-balance -j summary | jq '.USD.estimated_days_left'
```

## Commands

| Command | What it does |
|---|---|
| `deepseek-balance current` | Latest balance per currency |
| `deepseek-balance today` | Total spend today (UTC) |
| `deepseek-balance history [N]` | Last N snapshots (default 24) |
| `deepseek-balance summary` | 7d/30d averages, days remaining |
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

## Database

All monetary values are stored as **integer cents**.

```bash
sqlite3 ~/.local/share/deepseek-balance-tracker/balance.db \
  "SELECT recorded_at, topped_up_balance_cents / 100.0 AS balance
   FROM balance_snapshots WHERE currency = 'USD'
   ORDER BY id DESC LIMIT 5;"
```

## License

MIT
