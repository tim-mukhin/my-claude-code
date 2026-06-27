# Token Economics

How Claude Code counts tokens, calculates cost, and what the statusline numbers mean.

## Pricing (API, per 1M tokens)

| Token Type | Opus 4.6 | Sonnet 4.6 | Haiku 4.5 | Multiplier |
|-----------|---------|-----------|----------|-----------|
| **input** | $5.00 | $3.00 | $1.00 | 1x |
| **cache_creation** (5 min) | $6.25 | $3.75 | $1.25 | 1.25x |
| **cache_creation** (1 hour) | $10.00 | $6.00 | $2.00 | 2x |
| **cache_read** | $0.50 | $0.30 | $0.10 | 0.1x |
| **output** | $25.00 | $15.00 | $5.00 | 5x |

Fast mode (Opus 4.6 only): 6x ($30/$150 per MTok).

Multipliers are identical across all models: cache_write = 1.25x, cache_read = 0.1x, output = 5x input.

## Session Cost Formula

```
base = base_input_price  (Opus: $5, Sonnet: $3, Haiku: $1)

cost_usd = (input × base + cache_creation × base×1.25 + cache_read × base×0.1 + output × base×5) / 1,000,000
```

Example (April 7 session, Opus 4.6, main + 10 subagents):

```
input:            28K  × $5.00/M  = $  0.14   (0.3%)
cache_creation: 3.5M   × $6.25/M  = $ 22.03  (39.8%)
cache_read:      56M   × $0.50/M  = $ 28.14  (50.8%)
output:         202K   × $25.0/M  = $  5.05   (9.1%)
TOTAL:                              $ 55.36
```

**cache_read accounts for 51% of cost** despite a 10x discount, due to volume.

## Four Levels of Token Counting

| Level | Formula | All Time Total | Hidden |
|---------|--------|-----------------|-------------|
| `/stats` "Total tokens" | `Σ(input_tokens + output_tokens)` | 4.7M | Cache (99.8% of tokens!) |
| `stats-cache.json` `modelUsage` | All 4 fields, no subagents | ~2.4B | Subagents |
| JSONL main + subagents (our `sum`) | Everything | ~2.6B+ | Nothing |
| USD cost (weighted) | Normalized by pricing | ~$340+ | - |

**Verification**: `modelUsage.inputTokens + outputTokens` = 4,570,159 - matches `/stats` 4.7M exactly.

`stats-cache.json` omits subagents: in the example from issue #24147 - 257 main + 1,214 sub = 1,471 sessions.

Important: the `SaH` function in code (`latestInput + cumulativeOutput`) is used to estimate context window size (autocompact threshold), NOT for `/stats`. `/stats` uses `modelUsage.inputTokens + outputTokens` from stats-cache.

## Where Tokens Go

### Snowball Effect

Each API call sends the ENTIRE context: system prompt (~100K) + full history + new message.

- Msg #1:  ~100K (system) + question = ~100K
- Msg #5:  ~100K + 4 previous messages = ~150K
- Msg #20: ~100K + long history = ~300K+
- Msg #50: could be 500K+ for a single call

Cumulatively: if 50 messages average 200K each, that's 50 × 200K = 10M "processed". But 90%+ will be cache_read.

### Subagents

Each subagent receives the FULL context: ~100K base overhead (system prompt + MCP tools + CLAUDE.md + memory).

10 MCP servers (ADO x3, teams, mail, calendar, playwright, figma, enghub, context7) = 310 tools.
Even with deferred loading (names only) - base overhead is ~100K per subagent.

### Compaction

When context hits the limit, Claude Code performs compaction (compression). Compaction itself is an API call with full context + output as summary. `agent-acompact` in subagents is the compaction agent (11.9M tokens in the example).

## Peak Hours and Dynamic Limits

Peak hours (consistent): **8 AM - 2 PM ET** weekdays. No peak on weekends.

| Timezone | Peak Hours | Off-Peak |
|----------|----------|----------|
| ET (New York) | 08:00-14:00 | 14:00-08:00 |
| PT (San Francisco) | 05:00-11:00 | 11:00-05:00 |
| GMT | 12:00-18:00 | 18:00-12:00 |
| CET (Belgrade) | **14:00-20:00** | **20:00-14:00** |

For Belgrade: work hours 9:00-14:00 = off-peak, 14:00-20:00 = peak.
Evening work after 20:00 = off-peak.

During peak hours, limits burn faster - Anthropic throttles due to GPU shortage.

**5-hour window**: rolling window. Not "5 hours and reset", but gradual recovery - what you spent 5 hours ago becomes available.

**2x Promotion (March 13-28, 2026, completed)**: off-peak 2x limits, weekends 2x all day. Overspend on off-peak did NOT count toward weekly limit.

## Max Plan Limits

Anthropic does not publish exact limits. Known:

- **5-hour window**: rolling window, ~900 messages (Max 20x) or ~88K tokens (Max 5x)
- **Weekly limit**: 7-day window, introduced mid-2025. ~24-40 hours Opus or ~240-480 hours Sonnet
- **Max 5x** ($100/mo): 5x Pro limits
- **Max 20x** ($200/mo): 20x Pro limits
- Limits are dynamic and depend on load (peak hours vs off-peak)

### Limit Bugs (March 2026)

7 confirmed bugs:
- Cache invalidation bugs (cache recreated 10-20x more often than necessary)
- Session-resume: full context rework on resume
- Off-peak 2x promotion cancelled without notification
- Max 20x limit exhausted in 70 min instead of 5 hours (issue #41788)

Some fixed in v2.1.91.

## Mode Detection (API vs Subscription)

- `ANTHROPIC_API_KEY` env var: if present - API mode (pay-per-token)
- If absent - subscription mode (Pro/Max limits)
- `/status` in Claude Code shows current mode and email/org
- At work: API via `agency` wrapper with MCP servers

## Statusline Metric Options

### 1. Raw sum (current implementation)

```
sum 60.0M
```
Full throughput. Simple, but doesn't reflect real cost. cache_read = 92% of volume but 51% of cost.

### 2. USD cost

```
sum $55
```
Accurate for API. For subscription - proxy (if $200/mo = ~$200 compute budget).
Formula depends on model - need to know current model.

### 3. Normalized tokens (input-equivalent)

```
sum 11.1Me  (effective input-equivalent tokens)
```
Formula: `input × 1 + cc × 1.25 + cr × 0.1 + output × 5`
Normalizes to "what it would cost if everything were base input".

### 4. Dual metric

```
sum $55 (60M)
```
USD + raw for context.

### 5. Limit-aware (for subscription)

Measure % limit before and after messages via `/status` or API.
Problem: no programmatic access to current limit %.

## What Actually Affects Cost

By cost share in typical session:

1. **cache_read** (~51% USD) - unavoidable, grows with session length
2. **cache_creation** (~40% USD) - new subagents, context changes, compaction
3. **output** (~9% USD) - model responses, 5x cost
4. **input** (<1% USD) - negligible

### Optimizations

- Fewer subagents = less cache_creation (each = ~100K × $6.25/M = $0.63)
- Disable unneeded MCP servers (ADO x3 -> ADO x1 = -200 tools)
- Short sessions (compaction = expensive API call)
- Sonnet instead of Opus for simple tasks (3x cheaper)

## Sources

- [Pricing - Claude API Docs](https://platform.claude.com/docs/en/about-claude/pricing)
- [Rate limits - Claude API Docs](https://platform.claude.com/docs/en/api/rate-limits)
- [Prompt caching - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/prompt-caching)
- [Issue #24147 - token accounting](https://github.com/anthropics/claude-code/issues/24147)
- [Issue #41788 - Max 20 limit exhausted in 70 min](https://github.com/anthropics/claude-code/issues/41788)
- [Issue #41930 - widespread drain since March 23](https://github.com/anthropics/claude-code/issues/41930)
- [Anthropic admits quotas running out too fast](https://www.theregister.com/2026/03/31/anthropic_claude_code_limits/)
- [Cache bugs causing 10-20x inflation](https://github.com/ArkNill/claude-code-cache-analysis)
- [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) - precise system prompt measurements
