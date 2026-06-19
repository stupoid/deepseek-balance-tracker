# DeepSeek Balance Tracker

Lightweight shell-script service that polls the [DeepSeek API](https://api-docs.deepseek.com/api/get-user-balance) every hour and records your account balance into a SQLite database. Other programs can query the DB to check current balance and usage patterns.

**Dependencies**: `curl`, `jq`, `sqlite3` — nothing else.

## Quick Start

### 1. Install dependencies

```bash
# NixOS: add `sqlite` to environment.systemPackages and rebuild
sudo nixos-rebuild switch

# Other distros: install sqlite3
sudo apt install sqlite3    # Debian/Ubuntu
sudo pacman -S sqlite       # Arch
```

### 2. Clone and set up secrets

```bash
git clone https://github.com/... /home/kelvin/code/deepseek-balance-tracker
cd /home/kelvin/code/deepseek-balance-tracker

# Create secrets file
sudo mkdir -p /etc/deepseek-balance
sudo cp secrets.env.example /etc/deepseek-balance/secrets.env
sudo chmod 600 /etc/deepseek-balance/secrets.env
# Edit: put your real API key in the file
sudo vim /etc/deepseek-balance/secrets.env
```

Your `secrets.env` should look like:

```
DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxx
CURRENCY=both
```

- `CURRENCY`: `USD`, `CNY`, or `both` (default)
- You can also set `DEEPSEEK_API_KEY` in your environment for manual runs

### 3. Test manually

```bash
# Record your first snapshot
./bin/poll-balance

# Check current balance
./bin/query-balance current

# See usage today
./bin/query-balance today

# Last 24 snapshots
./bin/query-balance history 24

# Summary stats
./bin/query-balance summary
```

### 4. Install systemd timer

```bash
sudo cp etc/deepseek-balance.service /etc/systemd/system/
sudo cp etc/deepseek-balance.timer /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now deepseek-balance.timer

# Verify it's running
sudo systemctl status deepseek-balance.timer
sudo systemctl status deepseek-balance.service
```

The timer fires every hour (`OnCalendar=hourly`). To change the interval, edit `/etc/systemd/system/deepseek-balance.timer` and run `sudo systemctl daemon-reload`.

### 5. Check logs

```bash
journalctl -u deepseek-balance.service -f
```

## Usage Reference

### `poll-balance`

No arguments. Reads config from environment or `/etc/deepseek-balance/secrets.env`.

```bash
DEEPSEEK_API_KEY=sk-... CURRENCY=USD ./bin/poll-balance
```

### `query-balance`

```
query-balance [-c USD|CNY] <subcommand> [args]
```

| Subcommand | Output |
|---|---|
| `current` | Latest balance for each currency |
| `today` | Spend today: sum of positive balance decreases (top-ups are ignored) |
| `history [N]` | Last N snapshots (default 24) as JSON array |
| `summary` | 7d/30d avg daily spend, current balance, estimated days remaining |

All output is JSON. Use `jq` to extract what you need:

```bash
# Just the USD balance number
./bin/query-balance -c USD current | jq '.[0].topped_up_balance'

# Today's USD spend
./bin/query-balance -c USD today | jq '.USD.spend_today'

# Estimated days left
./bin/query-balance -c USD summary | jq '.USD.estimated_days_left'
```

## How Usage Is Tracked

Each snapshot records `topped_up_balance` (your paid balance). The difference between consecutive snapshots = spend in that interval. If your balance increases between snapshots (top-up), that interval is ignored.

- **Today's usage**: sum of all positive `prev - curr` deltas across today's (UTC) snapshots
- **Daily average**: per-day spend totals averaged over 7 or 30 days
- **Estimated days left**: `current_balance / avg_daily_spend_30d`

## Database

SQLite file at `/var/lib/deepseek-balance-tracker/balance.db`. Schema:

```sql
CREATE TABLE balance_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recorded_at TEXT NOT NULL DEFAULT (datetime('now')),
    currency TEXT NOT NULL,
    total_balance REAL NOT NULL,
    granted_balance REAL NOT NULL,
    topped_up_balance REAL NOT NULL
);
```

Query it directly:

```bash
sqlite3 /var/lib/deepseek-balance-tracker/balance.db \
  "SELECT * FROM balance_snapshots ORDER BY id DESC LIMIT 5;"
```

## Files

| Path | Purpose |
|---|---|
| `bin/poll-balance` | Fetch + record balance from API |
| `bin/query-balance` | Query balance history and usage stats |
| `etc/deepseek-balance.service` | systemd oneshot service |
| `etc/deepseek-balance.timer` | systemd timer (hourly) |
| `secrets.env.example` | Template for `/etc/deepseek-balance/secrets.env` |
| `/var/lib/deepseek-balance-tracker/balance.db` | SQLite database (runtime) |
| `/etc/deepseek-balance/secrets.env` | API key + config (runtime, chmod 600) |
