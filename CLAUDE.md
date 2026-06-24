# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

DeepSeek Balance Tracker tracks DeepSeek API spending by periodically polling `/user/balance`, recording snapshots into a local SQLite database, and providing a CLI to query spending history. Pure Bash — zero runtime dependencies beyond `bash`, `curl`, `jq`, and `sqlite3`.

## Commands

```bash
./test/run                 # Run the full test suite
bash -n bin/*              # Syntax-check all scripts
shellcheck -x bin/*        # Lint all scripts (if shellcheck installed)
```

No build step. The pre-commit hook (`.githooks/pre-commit`) runs `bash -n`, `shellcheck`, and `./test/run`. Install it with `git config core.hooksPath .githooks`.

## Architecture

Two independent scripts communicate only through a shared SQLite database:

**`bin/deepseek-balance-poll`** (210 lines) — Writer. Called by the systemd timer every 5 minutes. Fetches the DeepSeek API, parses the JSON response with `jq`, converts dollar strings to integer cents via `awk`, inserts rows. After insert: prunes old rows (row cap `MAX_ROWS`, default 1M), runs the alert state machine.

**`bin/deepseek-balance`** (431 lines) — Reader. CLI for humans and scripts. Each subcommand (`current`, `today`, `recent`, `history`, `summary`, `check-alert`) has two implementations: `text_*` and `json_*`, dispatched on the `-j` flag. Never calls the API.

### Data flow

```
systemd timer → deepseek-balance-poll → curl → DeepSeek API
                                      → SQLite DB
deepseek-balance ← SQLite DB ← any script, bot, or status bar
```

### Key design decisions

- **Integer cents**: All monetary values stored as `INTEGER` cents (e.g. $4.26 → 426). Conversion happens at the boundary — `dollars_to_cents()` on insert, `cents_to_dollars()` on display. This avoids floating-point errors.
- **Spend = topped-up delta**: Spending is calculated as the decrease in `topped_up_balance` between consecutive snapshots using a SQLite window function (`LAG() OVER`, `MAX(prev - current, 0)`). Top-ups (balance increases) are ignored. Using `topped_up_balance` rather than `total_balance` avoids false spend from granted balance expiry.
- **Alert state machine**: Fire-once, re-arm on recovery. State persisted to `~/.local/state/deepseek-balance-tracker/alert-state` as `CURRENCY:ok|fired` lines. The poll script checks thresholds after each insert; the `check-alert` subcommand only reads the current balance (stateless — does not read alert-state).
- **XDG paths**: DB at `$XDG_DATA_HOME/deepseek-balance-tracker/balance.db`, secrets at `$XDG_CONFIG_HOME/deepseek-balance/secrets.env`, alert state at `$XDG_STATE_HOME/deepseek-balance-tracker/alert-state`. All default to `~/.local/share`, `~/.config`, `~/.local/state`.
- **Config priority**: Environment variables override `secrets.env` file values. The poll script sources `secrets.env` only if `DEEPSEEK_API_KEY` is not already set; alert thresholds are read from env first, then `grep`'d from the file.

### Database schema

```sql
CREATE TABLE balance_snapshots (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    recorded_at INTEGER NOT NULL DEFAULT (unixepoch()),  -- Unix timestamp
    currency TEXT NOT NULL,                               -- 'USD' or 'CNY'
    total_balance_cents INTEGER NOT NULL,
    granted_balance_cents INTEGER NOT NULL,
    topped_up_balance_cents INTEGER NOT NULL
);
CREATE INDEX idx_snapshots_currency_time ON balance_snapshots(currency, recorded_at);
```

### Test suite

`test/run` (474 lines) uses a temporary directory with `XDG_DATA_HOME` pointed at it. Tests insert synthetic data via `insert_row()` helper, run the CLI, and assert output with `assert_contains`, `assert_not_contains`, `assert_json_key`. Covers: empty DB, single/multiple snapshots, spend calculation, top-up handling, currency filtering, UTC date boundaries, JSON output, alert exit codes, and the alert fire-once/re-arm state machine (mocking `curl`).

## File map

| Path | Role |
|---|---|
| `bin/deepseek-balance` | Query CLI (reader) |
| `bin/deepseek-balance-poll` | API poller (writer) |
| `etc/deepseek-balance.service` | systemd oneshot service unit |
| `etc/deepseek-balance.timer` | systemd timer (every 5 min) |
| `etc/alert-low-balance.sh` | Telegram alert notifier |
| `test/run` | Test suite |
| `secrets.env.example` | Template for user secrets |
| `.githooks/pre-commit` | Pre-commit hook |
| `LIMITATIONS.md` | Documented blind spots and edge cases |
