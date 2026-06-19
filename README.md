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

# Optional: keep it running when logged out
loginctl enable-linger
```

Done. It's recording. Check with:

```bash
journalctl --user -u deepseek-balance.service -f
```

## Query

```bash
./bin/query-balance current       # latest balance
./bin/query-balance today         # how much you spent today
./bin/query-balance history 10    # last 10 snapshots
./bin/query-balance summary       # 7d/30d averages, days remaining
```

All output is JSON. Pipe to `jq`:

```bash
./bin/query-balance -c USD current | jq '.[0].topped_up_balance'
# → 4.21

./bin/query-balance -c USD today | jq '.USD.spend_today'
# → 0.05

./bin/query-balance -c USD summary | jq '.USD.estimated_days_left'
# → 84
```

## How it works

```
systemd timer (every 5 min)
       │
       ▼
  poll-balance ──curl──▶ DeepSeek API /user/balance
       │
       ▼
  SQLite DB (~/.local/share/deepseek-balance-tracker/balance.db)
       │
       ▼
  query-balance ◀── any script, bot, or status bar
```

- **Spending** = decrease in `topped_up_balance` between snapshots. Balance increases (top-ups) are ignored.
- **Currency** = `USD`, `CNY`, or `both` — set `CURRENCY` in your secrets file.
- **Interval** = edit `OnCalendar` in the timer file to change it (default: every 5 min).

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
| Scripts | `bin/poll-balance`, `bin/query-balance` |
| systemd units | `etc/deepseek-balance.service`, `etc/deepseek-balance.timer` |
| Your API key | `~/.config/deepseek-balance/secrets.env` |
| SQLite DB | `~/.local/share/deepseek-balance-tracker/balance.db` |

## Database

All monetary values are stored as **integer cents** to avoid floating-point issues.

```bash
sqlite3 ~/.local/share/deepseek-balance-tracker/balance.db \
  "SELECT recorded_at, topped_up_balance_cents / 100.0 AS balance
   FROM balance_snapshots WHERE currency = 'USD'
   ORDER BY id DESC LIMIT 5;"
```

## License

MIT
