# Limitations

This tool tracks spending by comparing balance snapshots. That approach is simple and lightweight, but has inherent blind spots from being a periodic poller rather than a real-time feed.

## Known blind spots

### Top-up + spend between polls

If you top up and spend the entire amount between two consecutive polls, the net delta is zero and the tracker sees nothing.

```
10:00  poll: balance $5.00
10:01  top up $10.00 → balance $15.00
10:02  spend $10.00 → balance $5.00
10:05  poll: balance $5.00  ← delta is 0, nothing recorded
```

**Mitigation**: poll more frequently. At 5-minute intervals this window is small. The raw data is still recorded — if you know a top-up happened, you can query the snapshots directly.

### Granted balance expiry

If your granted (free) balance expires, `total_balance` drops without any API usage. This shows up as "spend" in the delta calculation even though you didn't consume any tokens.

```
10:00  poll: total_balance $5.00  granted_balance $5.00
       → granted balance expires
10:05  poll: total_balance $0.00  granted_balance $0.00
       → tracker sees $5.00 "spend"
```

**Mitigation**: the tracker uses `topped_up_balance` (paid balance) for spend calculations, not `total_balance`. However, if you only look at `total_balance` in the raw history, this can be misleading.

### First snapshot has no delta

After a fresh install, `deepseek-balance today` and `deepseek-balance recent` show `$0.00` until the second snapshot is recorded. There's nothing to compare against yet.

### Concurrent polls

If two instances of `deepseek-balance-poll` run at the same time (e.g., a stuck timer + manual run), both will insert snapshots. The data is still correct — you'll just have two nearly-identical rows — but it wastes a tiny amount of space.

**Mitigation**: the systemd timer's `OnCalendar` plus `RandomizedDelaySec` prevents overlap in normal operation.

### API downtime

If the DeepSeek API is unreachable, the poll fails (exit code 2) and no snapshot is recorded. The gap means spend during the outage can't be attributed to a specific hour. When the API comes back, the next snapshot will capture the full delta since the last successful poll.

### SQLite locking

SQLite uses single-writer locking. If `deepseek-balance` (reader) runs at the exact same moment as `deepseek-balance-poll` (writer), the reader may get `SQLITE_BUSY` and fail. In practice this is extremely rare with WAL mode and sub-millisecond transactions.

**Mitigation**: could add `.timeout 5000` to the sqlite3 invocations if this becomes an issue.

### New currencies

If DeepSeek adds a new currency (e.g., EUR), it will be recorded automatically if `CURRENCY=both`. If you have `CURRENCY=USD`, the new currency is silently ignored until you update your config.

### Alert state is in-memory per poll

The `alert-state` file is read at the start of each alert check and written when state changes. If two polls overlap (rare — see concurrent polls above), the second poll may re-fire an already-fired alert because it reads stale state. The window is tiny and the worst case is a duplicate notification.

### Alert thresholds are poll-only

The `check-alert` subcommand reads thresholds from the current environment or `secrets.env`. It does *not* read from the alert-state file — it reports the current balance against the threshold, not whether an alert has already fired. Use `check-alert` to inspect the current situation, and rely on the poll's state tracking to avoid duplicate notifications.

### Alert command is synchronous

`ALERT_COMMAND` runs synchronously during the poll. If your script takes 30 seconds (e.g., waiting for a network call), the poll is delayed by 30 seconds. Keep alert scripts fast. For slow webhooks, background them: `your-script &`.

### UTC date boundaries

All "today" calculations use UTC. If you're in UTC-8, "today" resets at 4pm your time. This is by design (consistent, no DST issues) but can be surprising.

### Integer precision

Balances are stored as integer cents. The maximum representable balance is ~$92 quadrillion (2^63 / 100). This is not a practical concern.

## What this tool is not

- **Not a billing system** — don't use it for accounting or tax purposes
- **Not real-time** — it's a periodic poller, there's always a window of unobserved activity
- **Not multi-user** — one API key, one database
