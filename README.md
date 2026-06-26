# DeepSeek Balance Tracker

Track DeepSeek API spending by periodically polling `/user/balance`, recording snapshots into a local SQLite database, and providing a CLI to query spending history.

Pure Bash — dependencies: `bash`, `curl`, `jq`, `sqlite3`.

## Quick start

```bash
git clone https://github.com/stupoid/deepseek-balance-tracker.git
cd deepseek-balance-tracker

# Configure
mkdir -p ~/.config/deepseek-balance
chmod 700 ~/.config/deepseek-balance
cp secrets.env.example ~/.config/deepseek-balance/secrets.env
chmod 600 ~/.config/deepseek-balance/secrets.env
# Edit ~/.config/deepseek-balance/secrets.env and set your DEEPSEEK_API_KEY

# Install systemd timer (user service)
mkdir -p ~/.config/systemd/user
cp etc/deepseek-balance.service ~/.config/systemd/user/
cp etc/deepseek-balance.timer ~/.config/systemd/user/
# Edit the service file if your clone path differs from ~/code/deepseek-balance-tracker
systemctl --user daemon-reload
systemctl --user enable --now deepseek-balance.timer

# Query
bin/deepseek-balance current
bin/deepseek-balance summary
```

## Usage

```
deepseek-balance [-j] [-c USD|CNY] <subcommand> [args]

Subcommands:
  current         Latest balance per currency
  today           Total spend today (UTC)
  recent          Total spend in the last 60 minutes
  history [N]     Last N snapshots (default 24)
  summary         Averages over 7d/30d, estimated days remaining
  check-alert     Check current balance against configured thresholds

Options:
  -j              JSON output (for scripts/bots)
  -c USD|CNY      Filter to a single currency
```

## Alerting

Set `ALERT_THRESHOLD_USD` / `ALERT_THRESHOLD_CNY` and `ALERT_COMMAND` in `secrets.env`. The poll script fires `ALERT_COMMAND` once when balance drops below threshold and re-arms when balance recovers. A bundled Telegram notifier is at `etc/alert-low-balance.sh`.

See `LIMITATIONS.md` for known blind spots and edge cases.
