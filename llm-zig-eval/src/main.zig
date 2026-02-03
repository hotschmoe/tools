//! llm-zig-eval main entry point
//! CLI orchestrator for benchmarking LLMs on Zig programming tasks.

const std = @import("std");
const lib = @import("llm_zig_eval");

const Config = lib.Config;
const Client = lib.Client;
const Message = lib.Message;
const Report = lib.Report;
const ModelResult = lib.ModelResult;
const ProblemResult = lib.ProblemResult;
const Sandbox = lib.Sandbox;
const SandboxResult = lib.SandboxResult;
const TokenUsage = lib.TokenUsage;
const PROBLEMS = lib.PROBLEMS;

const parser = lib.parser;
const sandbox = lib.sandbox;
const tokens = lib.tokens;
const config = lib.config;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse CLI arguments
    var cfg = config.parseArgs(allocator) catch |err| {
        switch (err) {
            error.HelpRequested => return,
            error.MissingApiKey => {
                std.debug.print("\nHint: Set OPENROUTER_API_KEY environment variable\n", .{});
                std.debug.print("  PowerShell: $env:OPENROUTER_API_KEY = \"sk-or-v1-...\"\n", .{});
                std.debug.print("  Bash: export OPENROUTER_API_KEY=\"sk-or-v1-...\"\n", .{});
                return err;
            },
            error.MissingModels => {
                std.debug.print("\nHint: Specify models to benchmark\n", .{});
                std.debug.print("  llm-zig-eval --models=anthropic/claude-3.5-sonnet,openai/gpt-4o\n", .{});
                return err;
            },
            else => return err,
        }
    };
    defer cfg.deinit();

    // Print banner
    printBanner();

    // Initialize OpenRouter client
    var client = Client.init(allocator, cfg.api_key);
    defer client.deinit();

    // Initialize sandbox
    var sbx = Sandbox.init(allocator, "out");

    // Initialize report
    var report = Report.init(allocator);
    defer report.deinit();

    // Run benchmark for each model
    for (cfg.models) |model_id| {
        std.debug.print("\n🔄 Benchmarking: {s}\n", .{model_id});

        const model_result = try runModelBenchmark(
            allocator,
            &client,
            &sbx,
            model_id,
            cfg.runs,
        );

        try report.addResult(model_result);
    }

    // Render report
    const stdout = std.io.getStdOut().writer();
    switch (cfg.output_format) {
        .pretty => try report.renderTable(stdout),
        .json => try report.renderJson(stdout),
    }
}

fn runModelBenchmark(
    allocator: std.mem.Allocator,
    client: *Client,
    sbx: *Sandbox,
    model_id: []const u8,
    runs: u32,
) !ModelResult {
    var problem_results: std.ArrayList(ProblemResult) = .empty;
    errdefer problem_results.deinit(allocator);

    var total_usage = TokenUsage.init();
    var total_time_ms: i64 = 0;
    var passed: u32 = 0;

    // Create model output directory
    const model_dir = try sbx.createModelDir(model_id);
    defer allocator.free(model_dir);

    // Run each problem
    for (PROBLEMS) |problem| {
        std.debug.print("  ├─ {s}... ", .{problem.name});

        // Load problem prompt
        const prompt = try sandbox.loadProblemPrompt(allocator, problem);
        defer allocator.free(prompt);

        // Best result across runs
        var best_status: SandboxResult.Status = .compile_error;
        var best_loc: usize = 0;
        var problem_time_ms: i64 = 0;

        for (0..runs) |_| {
            // Send to LLM
            const messages = [_]Message{
                .{
                    .role = .system,
                    .content = "You are an expert Zig programmer. Provide only the requested code in a single ```zig code block. No explanations outside the code.",
                },
                .{
                    .role = .user,
                    .content = prompt,
                },
            };

            var response = try client.sendChatCompletion(model_id, &messages);
            defer response.deinit(allocator);

            problem_time_ms += response.response_time_ms;
            total_usage.add(.{
                .prompt_tokens = response.usage.prompt_tokens,
                .completion_tokens = response.usage.completion_tokens,
                .total_tokens = response.usage.total_tokens,
            });

            // Extract code
            const code = try parser.extractZigCode(allocator, response.content) orelse {
                std.debug.print("✗ (no code)\n", .{});
                continue;
            };
            defer allocator.free(code);

            // Write to sandbox
            const solution_path = try sbx.writeSolution(model_dir, problem.id, code);
            defer allocator.free(solution_path);

            // Run tests
            var test_result = try sbx.runTest(solution_path, problem.test_path);
            defer test_result.deinit();

            // Track best result
            if (@intFromEnum(test_result.status) < @intFromEnum(best_status)) {
                best_status = test_result.status;
                best_loc = parser.countLoc(code);
            }
        }

        // Record problem result
        const status_str = switch (best_status) {
            .pass => "✓",
            .compile_error => "✗ compile",
            .test_error => "✗ test",
            .timeout => "✗ timeout",
        };
        std.debug.print("{s}\n", .{status_str});

        if (best_status == .pass) passed += 1;
        total_time_ms += problem_time_ms;

        try problem_results.append(allocator, .{
            .problem_id = problem.id,
            .problem_name = problem.name,
            .status = best_status,
            .response_time_ms = problem_time_ms,
            .loc = best_loc,
        });
    }

    // Calculate cost
    const cost = tokens.calculateCost(model_id, total_usage);

    return ModelResult{
        .model_id = model_id,
        .problems = try problem_results.toOwnedSlice(allocator),
        .total_time_ms = total_time_ms,
        .score = passed,
        .total_problems = @intCast(PROBLEMS.len),
        .usage = total_usage,
        .cost = cost,
        .rating = null, // Council rating would go here
    };
}

fn printBanner() void {
    const banner =
        \\
        \\╔═══════════════════════════════════════════════════════════╗
        \\║     ╦   ╦   ╔╦╗    ╔═╗  ╦  ╔═╗    ╔═╗  ╦  ╦  ╔═╗  ╦       ║
        \\║     ║   ║   ║║║    ╔═╝  ║  ║ ╦    ║╣   ╚╗╔╝  ╠═╣  ║       ║
        \\║     ╩═╝ ╩═╝ ╩ ╩    ╚═╝  ╩  ╚═╝    ╚═╝   ╚╝   ╩ ╩  ╩═╝     ║
        \\║                                                           ║
        \\║    Find which LLM writes the best Zig code.               ║
        \\╚═══════════════════════════════════════════════════════════╝
        \\
    ;
    std.debug.print("{s}\n", .{banner});
}

test "main module tests" {
    // Basic sanity tests
    const allocator = std.testing.allocator;
    _ = allocator;
}
