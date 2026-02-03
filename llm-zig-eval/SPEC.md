# llm-zig-eval Specification

## Overview

A benchmark suite for evaluating LLM performance on Zig programming tasks. The system prompts models via OpenRouter, captures generated code, compiles/tests it, and produces a comparative report with optional multi-model judging.

---

## Architecture

```text
┌─────────────────────────────────────────────────────────────────────────┐
│                           USER CLI                                       │
│  $ zig build run -- --models=anthropic/claude-3.5,openai/gpt-4o         │
└─────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────┐    ┌──────────────────────────────────────────┐
│    MAIN ORCHESTRATOR    │◄───│   PROBLEM REGISTRY (problems/*.txt)      │
│    (src/main.zig)       │    │   + Test Harnesses (problems/*_test.zig) │
└─────────────────────────┘    └──────────────────────────────────────────┘
            │
            │ HTTP POST /api/v1/chat/completions
            ▼
┌─────────────────────────┐
│   OPENROUTER GATEWAY    │
│ (src/gateways/          │
│  openrouter.zig)        │
│  - Bearer Auth          │
│  - Model routing        │
└─────────────────────────┘
            │
            ▼
   ┌─────────────────────────────────────────────────────────────┐
   │                    OPENROUTER.AI API                        │
   │  Routes to: Anthropic, OpenAI, Meta, DeepSeek, Google, etc. │
   │  Returns: JSON with usage.{prompt_tokens, completion_tokens}│
   └─────────────────────────────────────────────────────────────┘
            │
            ▼
┌─────────────────────────┐    ┌──────────────────────────────────────────┐
│  RESULT PARSER & WRITER │───▶│  SANDBOX: ./out/{model}/{problem}.zig    │
│  (src/core/parser.zig)  │    └──────────────────────────────────────────┘
│  - Extract code blocks  │                        │
│  - Capture token usage  │                        ▼
└─────────────────────────┘    ┌──────────────────────────────────────────┐
            │                  │  ZIG COMPILER & TEST RUNNER              │
            │                  │  $ zig test problem_harness.zig          │
            │                  └──────────────────────────────────────────┘
            │                                      │
            ▼                                      ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                         REPORT GENERATOR                                 │
│  - Aggregates pass/fail, timing, cost, LOC                              │
│  - Renders ASCII table or JSON                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## File Structure

```
llm-zig-eval/
├── build.zig                 # Main build script
├── build.zig.zon             # Dependencies
├── README.md                 # Project overview
├── SPEC.md                   # This specification
├── .env.example              # Template for API keys
│
├── problems/                 # The "Gauntlet" - benchmark problems
│   ├── q1_memory.txt         # Problem 1 prompt
│   ├── q1_test.zig           # Problem 1 test harness
│   ├── q2_concurrency.txt    # Problem 2 prompt
│   ├── q2_test.zig           # Problem 2 test harness
│   ├── q3_comptime.txt       # Problem 3 prompt
│   └── q3_test.zig           # Problem 3 test harness
│
├── src/
│   ├── main.zig              # CLI entry point, orchestration
│   ├── config.zig            # .env loader, model cost table
│   │
│   ├── gateways/
│   │   └── openrouter.zig    # HTTP client for OpenRouter API
│   │
│   ├── core/
│   │   ├── parser.zig        # Extract code from LLM response
│   │   ├── sandbox.zig       # Write files, run zig test
│   │   ├── tokens.zig        # Parse usage JSON, calc cost
│   │   └── reporter.zig      # ASCII table / JSON output
│   │
│   └── council/
│       ├── types.zig         # JudgeVerdict, ConsensusResult
│       ├── tribunal.zig      # Multi-judge orchestration
│       └── prompts.zig       # Judge system prompts
│
└── docs/                     # Design documentation
    ├── gem_init_1.md
    ├── gem_init_2.md
    └── gem_init_3.md
```

---

## Benchmark Problems (The Gauntlet)

Three problems test core Zig competencies. Each includes a text prompt and a test harness.

### Problem 1: Arena Allocator from Scratch

**Focus:** Memory, pointers, manual layout, alignment

**Prompt Summary:**
> Create a `MiniArena` struct managing a fixed 1024-byte buffer.
> - `alloc(size: usize) ![]u8` — returns aligned slice, advances pointer
> - `reset() void` — rewinds the pointer
> - Must enforce 8-byte alignment
> - Return `error.OutOfMemory` when full

**Test Harness Validates:**
- Allocations return 8-byte aligned addresses
- Memory can be reused after reset
- OutOfMemory returned correctly

---

### Problem 2: Mock TCP Socket (Async/Threading)

**Focus:** Concurrency, threads, error handling

**Prompt Summary:**
> Create a `MockSocket` struct with:
> - `connect(address: []const u8) !void` — simulates network delay with `std.time.sleep`
> - Returns `error.ConnectionRefused` if address is "bad_host"
> - Uses `std.Thread` to run connection non-blocking
> - `isConnected() bool` to check status

**Test Harness Validates:**
- 5 connections run in parallel (total time ≈ 1 sleep, not 5×)
- Error handling for bad_host
- No deadlocks or race conditions

---

### Problem 3: JSON-to-Struct (Comptime Reflection)

**Focus:** Comptime, `@typeInfo`, string parsing

**Prompt Summary:**
> Create `jsonToStruct(comptime T: type, json: []const u8) !T`
> - Uses `@typeInfo` to iterate struct fields at comptime
> - Parses simple JSON without using `std.json`
> - Supports `u8`, `u32`, `[]const u8` field types

**Test Harness Validates:**
- `Point{ .x = 10, .y = 20 }` parsed from `{"x": 10, "y": 20}`
- String fields handled correctly
- Compile-time field iteration (not runtime reflection)

---

## Council of Judges (Multi-Model Consensus)

Optional qualitative evaluation using multiple LLM judges to reduce single-model bias.

### Architecture

```text
            ┌─────────────────────────────────────┐
            │       CANDIDATE SOLUTION            │
            │   (Generated Zig code)              │
            └─────────────────────────────────────┘
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
    ┌──────────┐       ┌──────────┐       ┌──────────┐
    │ JUDGE A  │       │ JUDGE B  │       │ JUDGE C  │
    │ Claude   │       │ GPT-4o   │       │ DeepSeek │
    │ (Pedant) │       │(Architect)│      │ (Hacker) │
    └──────────┘       └──────────┘       └──────────┘
          │                  │                  │
          │    PHASE 1: BLIND EVALUATION        │
          ▼                  ▼                  ▼
    [Draft Score]      [Draft Score]      [Draft Score]
          │                  │                  │
          └──────────────────┼──────────────────┘
                             │
              PHASE 2: CROSS-POLLINATION
           "Here's what the others said..."
                             │
          ┌──────────────────┼──────────────────┐
          ▼                  ▼                  ▼
    [Final Score]      [Final Score]      [Final Score]
          │                  │                  │
          └──────────────────┼──────────────────┘
                             ▼
                   ┌─────────────────┐
                   │ CONSENSUS ENGINE│
                   │  Average: 8.5   │
                   └─────────────────┘
```

### Judge Personas

| Judge | Model | Focus |
|-------|-------|-------|
| A (Pedant) | Claude 3.5 | Safety, `defer`, strict types |
| B (Architect) | GPT-4o | Readability, structure, logic |
| C (Hacker) | DeepSeek/Llama | Performance, cleverness, brevity |

### Grading Rubric

1. **Safety (Critical):** Correct allocator usage, `defer`, no use-after-free
2. **Correctness:** Actually solves the stated problem
3. **Zig-Zen:** Uses optionals (`.?`), `try`, slices over C-style pointers

### Cost Optimization

Council only runs if code **passes** compilation and tests. No point judging broken code.

```zig
if (compile_result == .Success and test_result == .Success) {
    if (config.enable_council) {
        const rating = try council.convene(solution_code);
        report.addRating(rating);
    }
} else {
    report.addRating("N/A (Build Failed)");
}
```

---

## OpenRouter Integration

### Why OpenRouter?

- **Single API client** — All models use OpenAI-compatible JSON format
- **Wide model access** — Claude, GPT-4, Llama, Gemini, DeepSeek, etc.
- **Normalized usage** — Token counts in consistent format
- **Future flexibility** — Easy to add new models as they release

### API Response Format

```json
{
  "id": "gen-123...",
  "model": "anthropic/claude-3-opus",
  "choices": [ { "message": { "content": "..." } } ],
  "usage": {
    "prompt_tokens": 150,
    "completion_tokens": 340,
    "total_tokens": 490
  }
}
```

### Cost Calculation

Option 1 (Recommended): Hardcoded lookup table in `config.zig`
```zig
const COSTS = .{
    .{ "anthropic/claude-3.5-sonnet", 3.0, 15.0 },  // $/M input, $/M output
    .{ "openai/gpt-4o", 2.5, 10.0 },
    .{ "meta/llama-3-70b", 0.5, 0.5 },
};
```

Option 2: Call `/api/v1/generation?id=...` for exact cost (extra API call)

---

## Report Output

### ASCII Table (Default)

```
BENCHMARK REPORT
================================================================================
MODEL                   | TIME   | SCORE | COST    | MEM SAFETY | LOC | RATING
--------------------------------------------------------------------------------
anthropic/claude-3.5    | 4.2s   | 3/3   | $0.0042 | PASS       | 145 | S (9.5)
openai/gpt-4o           | 2.8s   | 3/3   | $0.0038 | PASS       | 120 | A (8.8)
meta/llama-3-70b        | 5.1s   | 1/3   | $0.0005 | FAIL       | 160 | C (6.0)
--------------------------------------------------------------------------------
* Rating provided by "The Council" (3-judge consensus)
```

### Computed Metrics

| Metric | Source |
|--------|--------|
| TIME | `std.time.nanoTimestamp()` around LLM request |
| SCORE | Count of passed `zig test` runs (0-3) |
| COST | `(input_tokens × input_price) + (output_tokens × output_price)` |
| MEM SAFETY | `GeneralPurposeAllocator` with `.detect_leaks = true` |
| LOC | Line count after stripping comments/whitespace |
| RATING | Council consensus score (S/A/B/C/F scale) |

---

## Configuration

### Environment Variables

```bash
OPENROUTER_API_KEY=sk-or-v1-...
```

### CLI Arguments

| Flag | Description | Default |
|------|-------------|---------|
| `--models` | Comma-separated model IDs | required |
| `--runs` | Runs per model per problem | 1 |
| `--council` | Enable Council judging | false |
| `--output` | Output format (ascii/json) | ascii |
| `--parallel` | Max concurrent requests | 4 |

---

## Development Roadmap

### Phase 1: Core Benchmark
- [ ] OpenRouter HTTP client
- [ ] Problem prompt loading
- [ ] Code extraction from responses
- [ ] Sandbox execution (zig test)
- [ ] Basic ASCII reporter

### Phase 2: Metrics & Cost
- [ ] Token usage parsing
- [ ] Cost calculation
- [ ] LOC counting
- [ ] Memory leak detection

### Phase 3: Council
- [ ] Multi-judge orchestration
- [ ] Phase 1/2 prompt construction
- [ ] Consensus scoring

### Phase 4: Polish
- [ ] JSON output format
- [ ] Multiple runs per problem
- [ ] Result caching
- [ ] Historical comparison
