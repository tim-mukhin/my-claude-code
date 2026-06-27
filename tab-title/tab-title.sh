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
# Find a writable tty by walking up the process tree.
# Claude Code 2.1.x runs hooks without a controlling tty, so /dev/tty fails.
# The parent claude/zsh still has a real pty (ttysNNN) we can write to.
TTY=""
PID=$$
for _ in 1 2 3 4 5 6 7 8; do
  PID=$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')
  [ -z "$PID" ] || [ "$PID" = "0" ] || [ "$PID" = "1" ] && break
  CAND=$(ps -o tty= -p "$PID" 2>/dev/null | tr -d ' ')
  if [ -n "$CAND" ] && [ "$CAND" != "??" ] && [ -w "/dev/$CAND" ]; then
    TTY="/dev/$CAND"
    break
  fi
done
[ -n "$TTY" ] && printf '\033]2;%s %s\007' "$ICON" "$T" > "$TTY" 2>/dev/null
# Pass stdin through for chaining
echo "$INPUT"
