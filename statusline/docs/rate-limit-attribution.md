# Statusline: Token Economics & Rate Limit Attribution

## Architecture

```
Claude Code
    |
    | JSON stdin (session_id, cwd, model, context_window, rate_limits, cost, transcript_path)
    v
statusline-parse.py   -->  bash vars: SID, CWD, USED, MODEL, RL_5H, RL_START_TS, ...
    |
    v
statusline.sh
    |-- Python block: reads session JSONL, calculates MSG_NUM, tokens, USD
    |-- Writes rl-snapshot to JSONL
    |-- Python block: cross-session scanning, RL attribution
    |-- Bash: formats and outputs statusline
    v
Terminal output (2 lines)
```

## Output Format

Line 1: `Opus | work-brain: label | ctx 45% | #12 · last 1K · next 150K · sum 1.2M/8.5M · $15.3`

Line 2 (subscription only): `+3.2% 5h[||||······]45% 2h30m | 2.1% w[||········]12% Tu15.04`

### Line 1 Fields

| Field | Example | Meaning |
|-------|---------|---------|
| Model | `Opus` | Current model |
| Project: label | `work-brain: research` | Project + auto-generated session label |
| ctx N% | `ctx 45%` | Context window usage (red >=80%, yellow >=60%) |
| #N | `#12` | Message number (user turns, deduped by promptId) |
| last N | `last 1K` | Last user message size (chars/4) |
| next NK | `next 150K` | Last assistant response full cost (input+output+cache) |
| sum X/Y | `sum 1.2M/8.5M` | Effective tokens / raw cumulative tokens |
| $N | `$15.3` | Session USD cost |

### Line 2 Fields (Rate Limits)

| Field | Example | Meaning |
|-------|---------|---------|
| Delta | `+3.2%` | This session's estimated RL consumption |
| 5h bar | `5h[||||······]45%` | 5-hour rolling window: bar + current % |
| Reset | `2h30m` | Time until 5h window resets |
| 7d bar | `w[||········]12%` | 7-day limit: bar + current % |
| 7d date | `Tu15.04` | 7d limit reset date |
| Peak | `↑` (red arrow) | Peak hours active (8AM-2PM ET weekdays) |

When only 1 session is active, the raw delta is shown as-is. With multiple sessions, the attributed share is shown instead.

## Token Economics

### Pricing (per 1M tokens)

| Type | Opus | Sonnet | Haiku | Multiplier |
|------|------|--------|-------|------------|
| input | $5 | $3 | $1 | 1x |
| cache_creation | $6.25 | $3.75 | $1.25 | 1.25x |
| cache_read | $0.50 | $0.30 | $0.10 | 0.1x |
| output | $25 | $15 | $5 | 5x |

### Formulas

**USD cost:**
```
base = base_input_price  (Opus: $5, Sonnet: $3, Haiku: $1)
usd = (input*base + cc*base*1.25 + cr*base*0.1 + output*base*5) / 1,000,000
```

**Effective tokens (eff_k)** - normalized to Opus input cost:
```
eff_k = usd / $5 * 1000  (in thousands)
```

**Raw cumulative (sum_k)** - sum of all tokens:
```
sum_k = (input + output + cache_creation + cache_read) / 1000
```

### Snowball Effect

Each API call sends the FULL context. Size grows with each message:
- Msg #1: ~100K (system prompt)
- Msg #10: ~200K
- Msg #30: ~400K+

90%+ will be cache_read (cheap but voluminous).

## Compact Reset

On `/compact` or auto-compact, all counters reset to zero:
- MSG_NUM (prompt_ids)
- Cumulative tokens (sum_k, eff_k)
- USD
- last/next token stats

Logic: `isCompactSummary: true` on a user record in JSONL signals a compact event. On detection, all accumulators are cleared.

After compact, subagents from previous context are not scanned (their data is already in sidechain messages in the main JSONL).

## Rate Limit Attribution

### Problem

Rate limits are account-wide. When 3 sessions run in parallel, the RL% delta includes consumption from all three. No way to tell how much a specific session contributed.

### Solution: rl-snapshot

After each statusline update, a snapshot is appended to the session JSONL:

```json
{"type":"rl-snapshot","ts":1712345678,"sid":"abc-123","rl5":45,"rl7":12,"eff_k":1500,"sum_k":8000,"usd":10.5}
```

| Field | Type | Description |
|-------|------|-------------|
| type | str | Always `"rl-snapshot"` |
| ts | int | UNIX timestamp |
| sid | str | Session ID |
| rl5 | int | Current 5-hour limit % |
| rl7 | int | Current 7-day limit % |
| eff_k | int | Effective tokens (K), cumulative from session start |
| sum_k | int | Raw tokens (K), cumulative |
| usd | float | USD cost, cumulative |

Size: ~120 bytes per record. 100 messages = 12KB. Negligible vs 1-43MB session files.

### Attribution Algorithm

**Input**: current session A, started at T0, RL at start = 10%, now = 50%.

**Step 1**: Find parallel sessions.
```python
# All JSONL files modified since T0 (by mtime), excluding subagents
candidates = glob.glob('~/.claude/projects/*/*.jsonl')
recent = [f for f in candidates if os.path.getmtime(f) >= T0 and '/subagents/' not in f]
```

**Step 2**: Collect rl-snapshot records.
```bash
rg --no-filename 'rl-snapshot' file1.jsonl file2.jsonl file3.jsonl
```

**Step 3**: Calculate spend per session (sum of positive eff_k deltas).
```python
def spend(snapshots):
    snapshots.sort(key=lambda x: x.ts)
    total = 0
    for i in range(1, len(snapshots)):
        d = snapshots[i].eff_k - snapshots[i-1].eff_k
        if d > 0:  # positive delta only
            total += d
    return total
```

Why sum of positive deltas instead of `max - min`:
```
Session with compact:  ...1200, 1500, 0, 100, 300
                             +300      +100 +200  = 600  (correct)
max - min:              1500 - 0                   = 1500 (wrong)
```

Compact resets eff_k to 0. `max - min` would produce a huge value because of the 0. Sum of positive deltas correctly accounts for pre-compact + post-compact spend.

**Step 4**: Proportional attribution.
```python
spends = {A: 1000, B: 500, C: 200}  # eff_k during overlap
total = 1700
rl_delta = 50 - 10 = 40%

A_share = (1000 / 1700) * 40% = 23.5%
B_share = (500 / 1700) * 40%  = 11.8%
C_share = (200 / 1700) * 40%  = 4.7%
```

**Step 5**: Display in statusline.
```
+23.5% 5h[|||||·····]50%
 ^
 this session's estimated RL consumption
```

### Full Example

```
T=0h   Session A starts. rate-limits-start: rl5=10%, ts=1712340000
T=0h   Session A, msg#1. rl-snapshot: {ts:1712340060, sid:"A", rl5:11, eff_k:50}
T=1h   Session B starts. rate-limits-start: rl5=15%
T=1h   Session B, msg#1. rl-snapshot: {ts:1712343660, sid:"B", rl5:16, eff_k:30}
T=2h   Session A, msg#5. rl-snapshot: {ts:1712347200, sid:"A", rl5:25, eff_k:400}
T=2h   Session B, msg#3. rl-snapshot: {ts:1712347260, sid:"B", rl5:26, eff_k:150}
T=3h   Session A, /compact. rl-snapshot: {ts:1712350800, sid:"A", rl5:30, eff_k:0}
T=3h   Session A, msg#1 (post-compact). rl-snapshot: {ts:1712350860, sid:"A", rl5:32, eff_k:80}

Attribution for session A at T=3h:
  A snapshots (ts >= T0): [50, 400, 0, 80]
  A spend: (400-50) + (80-0) = 350 + 80 = 430  (0-400 = -400, skipped)
  B snapshots (ts >= T0): [30, 150]
  B spend: 150-30 = 120
  Total: 430 + 120 = 550
  RL delta: 32 - 10 = 22%
  A share: (430/550) * 22% = 17.2%
  Display: +17.2% 5h[|||·······]32%
```

### Edge Cases

| Situation | Behavior |
|-----------|----------|
| First run (no rl-snapshot records) | Falls back to raw delta |
| API mode (no RL data) | Snapshot not written, scanning not triggered |
| Single session (N_SESS=1) | Shows raw delta as-is |
| Compact | eff_k resets, sum of positive deltas handles it correctly |
| Session >5h (rolling window) | RL delta may be small/negative due to roll-off. If <= 0, attribution is skipped |
| RL% arrives as integer | Attribution calculates with decimal precision |

## JSONL Record Types

The statusline reads and writes several record types in session JSONL:

| type | Written by | Purpose |
|------|-----------|---------|
| `rate-limits-start` | statusline-parse.py | Once at session start: captures RL% and timestamp |
| `rl-snapshot` | statusline.sh | After each message: full metrics snapshot |
| `assistant` | Claude Code | Model responses with usage (input/output/cache tokens) |
| `user` | Claude Code | User messages. `isCompactSummary` = compact event |
| `custom-title` | label-inject.py | Auto-generated session label |

## Performance

| Operation | Time |
|-----------|------|
| statusline-parse.py (JSON parse) | ~30ms |
| Python block (read session JSONL) | 50-500ms (depends on file size) |
| rl-snapshot write | <1ms |
| rg scan (2-5 recent files) | 5-10ms |
| Attribution Python block | 10-20ms |
| **Total** | **100-600ms** |

Statusline is invoked once after each assistant response.
