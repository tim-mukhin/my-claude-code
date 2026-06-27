# statusline (Claude Code)

Rich status line: model, project, label, context %, message count, token stats,
cumulative cost, and rate-limit bars with per-session attribution.

```
Opus | my-project: 🐛 fix auth bug | ctx 19% | #4 · last 312 · next 48K · sum 357K/1.8M · $1.8/1.1
0% 5h[··········]1% 2h30m | 0% w[|||||||····]66% Fr10.04
```

## Install

```bash
cp statusline/statusline.sh       ~/.claude/statusline.sh
cp statusline/statusline-parse.py ~/.claude/statusline-parse.py
chmod +x ~/.claude/statusline.sh ~/.claude/statusline-parse.py
```

Merge into `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

## Reading it

**Line 1** (left to right):

| Segment | Meaning |
|---------|---------|
| `Opus` | Current model |
| `my-project: 🐛 fix auth bug` | Project + auto-generated session label |
| `ctx 19%` | Context window usage (yellow >=60%, red >=80%) |
| `#4` | User message count (deduplicated by promptId) |
| `last 312` | Last user message size (~tokens, chars/4) |
| `next 48K` | Next API call cost estimate (input+output+cache, last assistant turn) |
| `sum 357K/1.8M` | `357K` = cost-normalized tokens (input-equivalent: input x1 + cache_create x1.25 + cache_read x0.1 + output x5). `1.8M` = raw token throughput (all tokens including subagents) |
| `$1.8/1.1` | `$1.8` = estimated API cost (USD, from token usage and per-model pricing). `$1.1` = cost reported by Claude Code itself (excludes subagents) |

**Line 2** (rate limits, subscription only):

| Segment | Meaning |
|---------|---------|
| `+3.2%` (before bar) | This session's estimated RL consumption (see [rate limit attribution](docs/rate-limit-attribution.md)) |
| `5h[··········]1%` | 5-hour rolling window usage with bar |
| `2h30m` | Time until 5h window resets |
| `w[\|\|\|\|\|\|\|····]66%` | 7-day window usage with bar |
| `Fr10.04` | 7-day window reset date |

Color thresholds: green/gray <50%, dim yellow 50-79%, red >=80%. Peak hours
(8AM-2PM ET weekdays) shown with `↑` indicator.

See [docs/token-economics.md](docs/token-economics.md) for the full breakdown of
how tokens are counted and priced, and
[docs/rate-limit-attribution.md](docs/rate-limit-attribution.md) for how rate
limit consumption is attributed across parallel sessions.

Deps: `python3`, `jq`, `claude` CLI.
