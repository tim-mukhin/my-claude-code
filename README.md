# my-claude-code

Personal Claude Code hooks and status line config.

## What's here

- `hooks/label-inject.py` - auto-generates session labels (emoji + description) via background `claude --print`. Writes `custom-title` to session JSONL. One label per session, no duplicates.
- `hooks/tab-title.sh` - updates terminal tab title with status icon + session label. Shared by all hooks.
- `statusline.sh` - status line with model, project, label, context %, message count, last/next token stats.

Tab title shows status: `⋯` working, `⏸` needs attention, `✳` idle.

## Install

```bash
mkdir -p ~/.claude/hooks
cp hooks/label-inject.py ~/.claude/hooks/
cp hooks/tab-title.sh ~/.claude/hooks/
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/hooks/label-inject.py ~/.claude/hooks/tab-title.sh ~/.claude/statusline.sh
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

Deps: `python3`, `jq`, `claude` CLI.
