# my-claude-code

Personal Claude Code hooks and status line config.

## What's here

- `hooks/label-inject.py` - auto-generates session labels (emoji + description) via background `claude --print`. Writes `custom-title` to session JSONL.
- `statusline.sh` - status line with model, project, label, context %, message count, last/next token stats.

Tab title shows status: `⋯` working, `⏸` needs attention, `✳` idle.

## Install

```bash
mkdir -p ~/.claude/hooks
cp hooks/label-inject.py ~/.claude/hooks/
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/hooks/label-inject.py ~/.claude/statusline.sh
```

Merge into `~/.claude/settings.json`:

```json
{
  "env": {
    "CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"
  },
  "hooks": {
    "UserPromptSubmit": [{"hooks": [{"type": "command", "command": "bash -c 'INPUT=$(cat); JSONL=$(echo \"$INPUT\" | jq -r .transcript_path); T=\"\"; [ -n \"$JSONL\" ] && [ -f \"$JSONL\" ] && T=$(grep custom-title \"$JSONL\" | tail -1 | jq -r .customTitle 2>/dev/null); [ -z \"$T\" ] && T=\"Claude Code\"; printf \"\\033]2;⋯ %s\\007\" \"$T\" > /dev/tty 2>/dev/null; echo \"$INPUT\" | python3 ~/.claude/hooks/label-inject.py; true'"}]}],
    "PermissionRequest": [{"hooks": [{"type": "command", "command": "bash -c 'JSONL=$(cat | jq -r .transcript_path); T=\"\"; [ -n \"$JSONL\" ] && [ -f \"$JSONL\" ] && T=$(grep custom-title \"$JSONL\" | tail -1 | jq -r .customTitle 2>/dev/null); [ -z \"$T\" ] && T=\"Claude Code\"; printf \"\\033]2;⏸ %s\\007\" \"$T\" > /dev/tty 2>/dev/null'"}]}],
    "PostToolUse": [{"hooks": [{"type": "command", "command": "bash -c 'JSONL=$(cat | jq -r .transcript_path); T=\"\"; [ -n \"$JSONL\" ] && [ -f \"$JSONL\" ] && T=$(grep custom-title \"$JSONL\" | tail -1 | jq -r .customTitle 2>/dev/null); [ -z \"$T\" ] && T=\"Claude Code\"; printf \"\\033]2;⋯ %s\\007\" \"$T\" > /dev/tty 2>/dev/null'"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "bash -c 'JSONL=$(cat | jq -r .transcript_path); T=\"\"; [ -n \"$JSONL\" ] && [ -f \"$JSONL\" ] && T=$(grep custom-title \"$JSONL\" | tail -1 | jq -r .customTitle 2>/dev/null); [ -z \"$T\" ] && T=\"Claude Code\"; printf \"\\033]2;✳ %s\\007\" \"$T\" > /dev/tty 2>/dev/null'"}]}]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

Deps: `python3`, `jq`, `claude` CLI.
