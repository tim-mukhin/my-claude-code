#!/bin/bash
# Claude Code status line: shows session task label + project + context usage
INPUT=$(cat)

# Parse JSON fields
eval "$(echo "$INPUT" | python3 -c "
import sys, json
d = json.load(sys.stdin)
sid = d.get('session_id', d.get('sessionId', ''))
cwd = d.get('cwd', '')
cw = d.get('context_window', {})
used = cw.get('used_percentage') or cw.get('used') or 0
used = int(round(float(used))) if used else 0
model = d.get('model', '')
# model may be a dict ({'id': ..., 'display_name': ...}) or a string
if isinstance(model, dict):
  model_id = model.get('id', '') or model.get('display_name', '')
else:
  model_id = model or ''
# Extract model name without version: claude-haiku-4-5-20251001 -> Haiku
model_name = ''
if model_id:
  parts = model_id.split('-')
  if len(parts) > 1 and parts[0] == 'claude':
    model_name = parts[1].capitalize()
  else:
    model_name = model_id.split(' ')[0]
print(f'SID=\"{sid}\"')
print(f'CWD=\"{cwd}\"')
print(f'USED=\"{used}\"')
print(f'MODEL=\"{model_name}\"')
" 2>/dev/null)"

# Read actual token stats from session JSONL
NEXT_K=""
LAST_TOK=""
MSG_NUM=""
if [ -n "$SID" ] && [ -n "$CWD" ]; then
  ENCODED=$(echo "$CWD" | tr '/' '-')
  JSONL="$HOME/.claude/projects/${ENCODED}/${SID}.jsonl"
  if [ ! -f "$JSONL" ]; then
    JSONL=$(find "$HOME/.claude/projects" -maxdepth 2 -name "${SID}.jsonl" 2>/dev/null | head -1)
  fi
  if [ -n "$JSONL" ] && [ -f "$JSONL" ]; then
    eval "$(python3 -c "
import json
# Count:    real user turns (main chat only, not subagents, not tool_results, not meta).
#           Dedup by promptId so interrupt+resume counts as one turn.
# next_k:   last assistant's full token cost (input+output+cache_creation+cache_read).
# last_tok: raw size of last user message (chars/4 for text, base64 bytes/750 for images).
last_total = 0
last_user_tokens = 0
prompt_ids = set()
try:
    with open('$JSONL') as f:
        for line in f:
            try:
                rec = json.loads(line.strip())
            except:
                continue
            if rec.get('isSidechain'):
                continue
            t = rec.get('type', '')
            if t == 'user' and not rec.get('isMeta') and not rec.get('isCompactSummary'):
                content = rec.get('message', {}).get('content', '')
                if isinstance(content, list):
                    if any(isinstance(c, dict) and c.get('type') == 'tool_result' for c in content):
                        continue
                pid = rec.get('promptId')
                if pid:
                    prompt_ids.add(pid)
                # Measure this user message directly
                tokens = 0
                if isinstance(content, str):
                    tokens = len(content) // 4
                elif isinstance(content, list):
                    for block in content:
                        if not isinstance(block, dict):
                            continue
                        if block.get('type') == 'text':
                            tokens += len(block.get('text', '')) // 4
                        elif block.get('type') == 'image':
                            b64 = block.get('source', {}).get('data', '')
                            tokens += len(b64) * 3 // 4 // 750
                last_user_tokens = tokens
            elif t == 'assistant':
                usage = rec.get('message', {}).get('usage', {})
                if not isinstance(usage, dict):
                    continue
                if usage.get('cache_read_input_tokens') is None and usage.get('cache_creation_input_tokens') is None:
                    continue
                input_t = int(usage.get('input_tokens', 0) or 0)
                output_t = int(usage.get('output_tokens', 0) or 0)
                cache_c = int(usage.get('cache_creation_input_tokens', 0) or 0)
                cache_r = int(usage.get('cache_read_input_tokens', 0) or 0)
                last_total = input_t + output_t + cache_c + cache_r
    next_k = round(last_total / 1000) if last_total else 0
    print(f'NEXT_K={next_k}')
    print(f'LAST_TOK={last_user_tokens}')
    print(f'MSG_NUM={len(prompt_ids)}')
except:
    pass
" 2>/dev/null)"
    # Read last custom-title from JSONL
    LABEL=$(jq -r 'select(.type=="custom-title") | .customTitle' "$JSONL" 2>/dev/null | tail -1)
  fi
fi

# Color ctx by used_percentage threshold
if [ "$USED" -ge 80 ] 2>/dev/null; then
  CTX_COLOR="\033[31m"
elif [ "$USED" -ge 60 ] 2>/dev/null; then
  CTX_COLOR="\033[33m"
else
  CTX_COLOR="\033[90m"
fi

# Color next (cumulative) by absolute size
if [ -n "$NEXT_K" ] && [ "$NEXT_K" -ge 180 ] 2>/dev/null; then
  NEXT_COLOR="\033[31m"
elif [ -n "$NEXT_K" ] && [ "$NEXT_K" -ge 140 ] 2>/dev/null; then
  NEXT_COLOR="\033[33m"
else
  NEXT_COLOR="\033[90m"
fi

# Color last (user message size) - flags heavy single messages
if [ -n "$LAST_TOK" ] && [ "$LAST_TOK" -ge 2000 ] 2>/dev/null; then
  LAST_COLOR="\033[31m"
elif [ -n "$LAST_TOK" ] && [ "$LAST_TOK" -ge 500 ] 2>/dev/null; then
  LAST_COLOR="\033[33m"
else
  LAST_COLOR="\033[90m"
fi

# Format last token count: <1000 = raw, >=1000 = K
LAST_FMT=""
if [ -n "$LAST_TOK" ] && [ "$LAST_TOK" -gt 0 ] 2>/dev/null; then
  if [ "$LAST_TOK" -ge 1000 ]; then
    LAST_FMT="$((LAST_TOK / 1000))K"
  else
    LAST_FMT="$LAST_TOK"
  fi
fi

SEP="\033[90m | \033[0m"

# LABEL is already set from JSONL parsing above

# Project name from cwd
PROJECT=$(basename "$CWD")

# Color from session_id hash (stable per session, different between sessions)
COLORS=(31 32 33 34 35 36 91 92 93 94 95 96)
if [ -n "$SID" ]; then
  HASH=$(echo -n "$SID" | cksum | cut -d' ' -f1)
  COLOR=${COLORS[$((HASH % ${#COLORS[@]}))]}
else
  COLOR=37
fi

# Output - pipe-separated blocks
FIRST=1
emit() {
  if [ "$FIRST" -eq 1 ]; then
    FIRST=0
  else
    printf "${SEP}"
  fi
  printf "%b" "$1"
}

if [ -n "$MODEL" ]; then
  emit "\033[36m${MODEL}\033[0m"
fi
if [ -n "$LABEL" ]; then
  emit "\033[${COLOR}m${PROJECT}: ${LABEL}\033[0m"
else
  emit "\033[${COLOR}m${PROJECT}\033[0m"
fi
emit "${CTX_COLOR}ctx ${USED}%\033[0m"

if [ -n "$MSG_NUM" ] && [ -n "$NEXT_K" ] && [ "$MSG_NUM" -gt 0 ] 2>/dev/null; then
  TOK_STR="\033[90m#${MSG_NUM}\033[0m"
  if [ -n "$LAST_FMT" ]; then
    TOK_STR="${TOK_STR} \033[90m·\033[0m ${LAST_COLOR}last ${LAST_FMT}\033[0m"
  fi
  TOK_STR="${TOK_STR} \033[90m·\033[0m ${NEXT_COLOR}next ${NEXT_K}K\033[0m"
  emit "${TOK_STR}"
fi
