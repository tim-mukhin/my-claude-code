# tab-title (Claude Code)

Terminal tab title with a status icon + an auto-generated session label.

```
⋯ 🐛 fix auth bug   working
⏸ 🐛 fix auth bug   needs your attention (permission prompt)
✳ 🐛 fix auth bug   idle / done
```

The label (emoji + 1-4 words about your goal, in your language) is generated
once per session by a background `claude --print` and written as a
`custom-title` record into the session JSONL, so it survives `/resume`.

## Install

```bash
mkdir -p ~/.claude/hooks
cp tab-title/label-inject.py ~/.claude/hooks/
cp tab-title/tab-title.sh    ~/.claude/hooks/
chmod +x ~/.claude/hooks/label-inject.py ~/.claude/hooks/tab-title.sh
```

Merge into `~/.claude/settings.json` (disables Claude Code's native title so it
doesn't fight the hook, and wires the status icons):

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
  }
}
```

## Choose your model

The label model is a constant near the top of `label-inject.py`:

```python
LABEL_MODEL = 'claude-sonnet-4-6'
```

Set it to a model **you** have access to. A cheap/fast model is plenty for short
labels — Sonnet is just the default.

## Files

| File | Purpose |
|------|---------|
| `label-inject.py` | `UserPromptSubmit` hook. Fire-and-forget: on the first prompt, spawns a background `claude --print` that writes the `custom-title` label. Holds the `LABEL_MODEL` constant. |
| `tab-title.sh` | Sets the tab title with the given status icon + cached label. Shared by all the status hooks. |

Deps: `python3`, `claude` CLI.
