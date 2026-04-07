#!/usr/bin/env python3
"""Parse statusline JSON input, output bash variables."""
import sys, json, time, os, datetime

d = json.load(sys.stdin)
sid = d.get('session_id', d.get('sessionId', ''))
cwd = d.get('cwd', '')
cw = d.get('context_window', {})
used = cw.get('used_percentage') or cw.get('used') or 0
used = int(round(float(used))) if used else 0

model = d.get('model', '')
if isinstance(model, dict):
    model_id = model.get('id', '') or model.get('display_name', '')
else:
    model_id = model or ''
model_name = ''
if model_id:
    parts = model_id.split('-')
    if len(parts) > 1 and parts[0] == 'claude':
        model_name = parts[1].capitalize()
    else:
        model_name = model_id.split(' ')[0]

cost_usd = d.get('cost', {}).get('total_cost_usd', 0) or 0

# Peak/off-peak (8AM-2PM ET weekdays)
is_peak = False
try:
    os.environ['TZ'] = 'America/New_York'
    time.tzset()
    lt = time.localtime()
    is_peak = lt.tm_wday < 5 and 8 <= lt.tm_hour < 14
    del os.environ['TZ']
    time.tzset()
except:
    pass

# Rate limits
rl = d.get('rate_limits') or {}
rl_5h = rl.get('five_hour', {}).get('used_percentage')
rl_7d = rl.get('seven_day', {}).get('used_percentage')
rl_5h_reset = rl.get('five_hour', {}).get('resets_at')
rl_7d_reset = rl.get('seven_day', {}).get('resets_at')

# Session start delta via JSONL
rl_5h_delta = ''
rl_7d_delta = ''
tp = d.get('transcript_path', '')
if tp and rl_5h is not None:
    rl_start = None
    try:
        with open(tp) as f:
            for line in f:
                if '"rate-limits-start"' in line:
                    rl_start = json.loads(line.strip())
                    break
    except:
        pass
    if rl_start is None:
        try:
            rec = json.dumps({
                'type': 'rate-limits-start',
                'five_hour': rl_5h,
                'seven_day': rl_7d or 0,
                'timestamp': int(time.time()),
                'sessionId': sid
            }, ensure_ascii=False, separators=(',', ':'))
            with open(tp, 'a') as f:
                f.write(rec + '\n')
        except:
            pass
    else:
        rl_5h_delta = rl_5h - rl_start.get('five_hour', 0)
        rl_7d_delta = (rl_7d or 0) - rl_start.get('seven_day', 0)

# Output bash variables
print(f'SID="{sid}"')
print(f'CWD="{cwd}"')
print(f'USED="{used}"')
print(f'MODEL="{model_name}"')
print(f'COST_USD={cost_usd:.1f}')
print(f'IS_PEAK={1 if is_peak else 0}')
if rl_5h is not None:
    print(f'RL_5H={rl_5h:.1f}')
    if rl_5h_delta != '':
        print(f'RL_5H_D={rl_5h_delta:.1f}')
    else:
        print(f'RL_5H_D=0.0')
if rl_7d is not None:
    print(f'RL_7D={rl_7d:.1f}')
    if rl_7d_delta != '':
        print(f'RL_7D_D={rl_7d_delta:.1f}')
    else:
        print(f'RL_7D_D=0.0')
if rl_5h_reset is not None:
    remaining = int(rl_5h_reset) - int(time.time())
    if remaining > 0:
        h, m = remaining // 3600, (remaining % 3600) // 60
        print(f'RL_RESET={h}h{m:02d}m' if h > 0 else f'RL_RESET={m}m')
if rl_7d_reset is not None:
    rd = datetime.datetime.fromtimestamp(int(rl_7d_reset))
    days = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']
    print(f'RL_7D_DATE={days[rd.weekday()]}{rd.day:02d}.{rd.month:02d}')
