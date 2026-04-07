# my-claude-code

Personal Claude Code hooks and status line config.

## What's here

- `hooks/label-inject.py` - auto-generates session labels (emoji + description) via background `claude --print`. Writes `custom-title` to session JSONL. One label per session, no duplicates.
- `hooks/tab-title.sh` - updates terminal tab title with status icon + session label. Shared by all hooks.
- `statusline.sh` - status line with model, project, label, context %, message count, last/next token stats, cumulative cost, rate limit bars.
- `statusline-parse.py` - JSON parser for statusline: extracts model, context, cost, rate limits, peak/off-peak detection.

Tab title shows status: `⋯` working, `⏸` needs attention, `✳` idle.

## Install

```bash
mkdir -p ~/.claude/hooks
cp hooks/label-inject.py ~/.claude/hooks/
cp hooks/tab-title.sh ~/.claude/hooks/
cp statusline.sh ~/.claude/statusline.sh
cp statusline-parse.py ~/.claude/statusline-parse.py
chmod +x ~/.claude/hooks/label-inject.py ~/.claude/hooks/tab-title.sh ~/.claude/statusline.sh ~/.claude/statusline-parse.py
```

Merge into `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
  },
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash -c 'INPUT=$(cat); echo \"$INPUT\" | ~/.claude/hooks/tab-title.sh ⋯ >/dev/null; echo \"$INPUT\" | python3 ~/.claude/hooks/label-inject.py; true'"}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tab-title.sh ⏸"}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tab-title.sh ⋯"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "~/.claude/hooks/tab-title.sh ✳"}]}]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

## Status line example

```
Opus | my-project: 🐛 fix auth bug | ctx 19% | #4 · last 312 · next 48K · sum 357K/1.8M · $1.8/1.1
0.0% 5h[··········]1.0% 2h30m | 0.0% w[|||||||····]66.0% Fr10.04
```

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
| `$1.8/1.1` | `$1.8` = estimated API cost (USD, calculated from token usage and per-model pricing). `$1.1` = cost reported by Claude Code itself (excludes subagents) |

**Line 2** (rate limits, subscription only):

| Segment | Meaning |
|---------|---------|
| `0.0%` (before bar) | Session delta (how much this session consumed) |
| `5h[··········]1.0%` | 5-hour rolling window usage with bar |
| `2h30m` | Time until 5h window resets |
| `w[|||||||····]66.0%` | 7-day window usage with bar |
| `Fr10.04` | 7-day window reset date |

Color thresholds: green/gray <50%, dim yellow 50-79%, red >=80%. Peak hours (8AM-2PM ET weekdays) shown with `↑` indicator.

See [docs/token-economics.md](docs/token-economics.md) for the full breakdown of how tokens are counted and priced.

Deps: `python3`, `jq`, `claude` CLI.
