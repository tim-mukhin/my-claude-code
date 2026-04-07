#!/bin/bash
# Updates terminal tab title with status icon + session label.
# Usage: tab-title.sh ⋯|⏸|✳
# Stdin: hook JSON payload (must contain transcript_path)
ICON="${1:-⋯}"
INPUT=$(cat)
JSONL=$(echo "$INPUT" | jq -r .transcript_path 2>/dev/null)
T=""
if [ -n "$JSONL" ] && [ -f "$JSONL" ]; then
  T=$(grep '"type":"custom-title"' "$JSONL" | tail -1 | jq -r .customTitle 2>/dev/null)
fi
[ -z "$T" ] || [ "$T" = "null" ] && T="Claude Code"
printf '\033]2;%s %s\007' "$ICON" "$T" > /dev/tty 2>/dev/null
# Pass stdin through for chaining
echo "$INPUT"
