#!/bin/bash
# Claude Code status line: shows session task label + project + context usage
INPUT=$(cat)

# Parse JSON fields
eval "$(echo "$INPUT" | python3 ~/.claude/statusline-parse.py 2>/dev/null)"

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
import glob as _glob
last_total = 0
last_user_tokens = 0
prompt_ids = set()
cum_main = 0
usd_main = 0.0
# Base input price per model (USD per 1M tokens)
_PRICES = {'opus': 5.0, 'sonnet': 3.0, 'haiku': 1.0}
def _base_price(model_id):
    m = (model_id or '').lower()
    for k, v in _PRICES.items():
        if k in m:
            return v
    return 5.0  # default opus
def _sum_usage(u):
    return (int(u.get('input_tokens', 0) or 0)
          + int(u.get('output_tokens', 0) or 0)
          + int(u.get('cache_creation_input_tokens', 0) or 0)
          + int(u.get('cache_read_input_tokens', 0) or 0))
def _usd_usage(u, base):
    # USD = (input*base + cc*base*1.25 + cr*base*0.1 + output*base*5) / 1M
    inp = int(u.get('input_tokens', 0) or 0)
    cc = int(u.get('cache_creation_input_tokens', 0) or 0)
    cr = int(u.get('cache_read_input_tokens', 0) or 0)
    out = int(u.get('output_tokens', 0) or 0)
    return (inp*base + cc*base*1.25 + cr*base*0.1 + out*base*5) / 1e6
try:
    with open('$JSONL') as f:
        for line in f:
            try:
                rec = json.loads(line.strip())
            except:
                continue
            t = rec.get('type', '')
            is_sc = rec.get('isSidechain')
            # Cumulative: count ALL assistant messages (including sidechain)
            if t == 'assistant':
                usage = rec.get('message', {}).get('usage', {})
                if isinstance(usage, dict) and usage.get('input_tokens') is not None:
                    cum_main += _sum_usage(usage)
                    _bp = _base_price(rec.get('message', {}).get('model', ''))
                    usd_main += _usd_usage(usage, _bp)
                    if not is_sc:
                        if usage.get('cache_read_input_tokens') is not None or usage.get('cache_creation_input_tokens') is not None:
                            last_total = _sum_usage(usage)
            if is_sc:
                continue
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
    # Sum subagent tokens
    cum_sub = 0
    usd_sub = 0.0
    _base = '$JSONL'.replace('.jsonl', '')
    for _sf in _glob.glob(_base + '/subagents/agent-*.jsonl'):
        try:
            with open(_sf) as _f:
                for _line in _f:
                    try:
                        _r = json.loads(_line.strip())
                    except:
                        continue
                    if _r.get('type') == 'assistant':
                        _u = _r.get('message', {}).get('usage', {})
                        if isinstance(_u, dict) and _u.get('input_tokens') is not None:
                            cum_sub += _sum_usage(_u)
                            _bp = _base_price(_r.get('message', {}).get('model', ''))
                            usd_sub += _usd_usage(_u, _bp)
        except:
            pass
    next_k = round(last_total / 1000) if last_total else 0
    cum_k = round((cum_main + cum_sub) / 1000)
    # eff = normalized to opus input-equivalent (USD / $5 per M)
    total_usd = usd_main + usd_sub
    eff_k = round(total_usd / 5.0 * 1000) if total_usd else 0
    print(f'NEXT_K={next_k}')
    print(f'LAST_TOK={last_user_tokens}')
    print(f'MSG_NUM={len(prompt_ids)}')
    print(f'CUM_K={cum_k}')
    print(f'EFF_K={eff_k}')
    print(f'REAL_USD={total_usd:.1f}')
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

# Color cumulative session total
if [ -n "$CUM_K" ] && [ "$CUM_K" -ge 7000 ] 2>/dev/null; then
  CUM_COLOR="\033[31m"
elif [ -n "$CUM_K" ] && [ "$CUM_K" -ge 3000 ] 2>/dev/null; then
  CUM_COLOR="\033[33m"
else
  CUM_COLOR="\033[90m"
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

# Format K/M helper: usage: fmt_km VALUE -> sets _FMT
fmt_km() {
  local v=$1
  if [ "$v" -ge 1000 ] 2>/dev/null; then
    _FMT="$((v / 1000)).$((v % 1000 / 100))M"
  elif [ "$v" -gt 0 ] 2>/dev/null; then
    _FMT="${v}K"
  else
    _FMT=""
  fi
}

fmt_km "${CUM_K:-0}"; CUM_FMT="$_FMT"
fmt_km "${EFF_K:-0}"; EFF_FMT="$_FMT"

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
  if [ -n "$EFF_FMT" ]; then
    TOK_STR="${TOK_STR} \033[90m·\033[0m ${CUM_COLOR}sum ${EFF_FMT}"
    if [ -n "$CUM_FMT" ]; then
      TOK_STR="${TOK_STR}\033[90m/${CUM_FMT}"
    fi
    TOK_STR="${TOK_STR}\033[0m"
  elif [ -n "$CUM_FMT" ]; then
    TOK_STR="${TOK_STR} \033[90m·\033[0m ${CUM_COLOR}sum ${CUM_FMT}\033[0m"
  fi
  if [ -n "$REAL_USD" ] && [ "$REAL_USD" != "0.0" ] 2>/dev/null; then
    TOK_STR="${TOK_STR} \033[90m·\033[0m \033[90m\$${REAL_USD}"
    if [ -n "$COST_USD" ] && [ "$COST_USD" != "0.0" ] 2>/dev/null; then
      TOK_STR="${TOK_STR}/${COST_USD}"
    fi
    TOK_STR="${TOK_STR}\033[0m"
  elif [ -n "$COST_USD" ] && [ "$COST_USD" != "0.0" ] 2>/dev/null; then
    TOK_STR="${TOK_STR} \033[90m·\033[0m \033[90m\$${COST_USD}\033[0m"
  fi
  # Rate limits (subscription only, null on API)
  if [ -n "$RL_5H" ] 2>/dev/null; then
    # Bar: 10 chars, | for filled, · (middle dot) for empty
    make_bar() {
      local pct=$1 width=10
      local full=$((pct * width / 100))
      local empty=$((width - full))
      local bar=""
      [ "$full" -gt 0 ] && for i in $(seq 1 $full); do bar="${bar}|"; done
      [ "$empty" -gt 0 ] && for i in $(seq 1 $empty); do bar="${bar}·"; done
      echo "$bar"
    }
    rl_color() {
      if [ "$1" -ge 80 ] 2>/dev/null; then echo "\033[31m"
      elif [ "$1" -ge 50 ] 2>/dev/null; then echo "\033[2;33m"
      else echo "\033[90m"; fi
    }
    # 5h bar
    RL_5H_INT=${RL_5H%.*}
    BAR5=$(make_bar "$RL_5H_INT")
    C5=$(rl_color "$RL_5H_INT")
    RESET_STR=""
    [ -n "$RL_RESET" ] && RESET_STR=" ${RL_RESET}"
    # Session delta prefix (always show)
    DELTA5=""
    if [ -n "$RL_5H_D" ]; then
      DELTA5="\033[90m${RL_5H_D}%\033[0m"
    fi
    RL_STR="${DELTA5} ${C5}5h\033[2;90m[\033[0m${C5}${BAR5}\033[2;90m]\033[0m${C5}${RL_5H}%\033[2;90m${RESET_STR}\033[0m"
    # 7d bar
    if [ -n "$RL_7D" ] 2>/dev/null; then
      RL_7D_INT=${RL_7D%.*}
      BAR7=$(make_bar "$RL_7D_INT")
      C7=$(rl_color "$RL_7D_INT")
      DELTA7=""
      if [ -n "$RL_7D_D" ]; then
        DELTA7="\033[90m${RL_7D_D}%\033[0m"
      fi
      RL_STR="${RL_STR} \033[2;90m|\033[0m ${DELTA7} ${C7}w\033[2;90m[\033[0m${C7}${BAR7}\033[2;90m]\033[0m${C7}${RL_7D}%\033[2;90m ${RL_7D_DATE}\033[0m"
    fi
    emit "${TOK_STR}"
    # Rate limits on second line
    PEAK_IND=""
    [ "$IS_PEAK" = "1" ] && PEAK_IND="\033[31m↑\033[0m "
    echo ""
    printf "%b" "${PEAK_IND}${RL_STR}"
  else
    emit "${TOK_STR}"
  fi
fi
