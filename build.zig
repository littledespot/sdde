const std = @import("std");
const builtin = @import("builtin");
const zig_version = @import("build/zig_version.zig");
const packaging_smoke = @import("test/packaging/smoke.zig");

comptime {
    if (!zig_version.isSupported(builtin.zig_version)) {
        @compileError("SDDE requires Zig 0.16.0 exactly");
    }
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const unicode_dependency = b.dependency("utf8proc", .{});
    const unicode_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/text/unicode_normalization.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    unicode_module.addIncludePath(unicode_dependency.path(""));
    unicode_module.addCMacro("UTF8PROC_STATIC", "1");
    unicode_module.addCSourceFile(.{ .file = unicode_dependency.path("utf8proc.c"), .flags = &.{"-DUTF8PROC_STATIC"} });
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(unicode_dependency.path("LICENSE.md"), .prefix, "share/licenses/utf8proc/LICENSE.md").step);
    const yaml_dependency = b.dependency("yaml", .{
        .target = target,
        .optimize = optimize,
    });
    const yaml_module = yaml_dependency.module("yaml");
    const bounded_yaml_syntax_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/parsers/yaml_syntax.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "yaml", .module = yaml_module },
        },
    });

    const sdde_module = b.addModule("sdde", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module },
            .{ .name = "unicode_normalization", .module = unicode_module },
        },
    });

    const executable = b.addExecutable(.{
        .name = "sdde",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "sdde", .module = sdde_module },
            },
        }),
    });
    b.installArtifact(executable);

    const run_command = b.addRunArtifact(executable);
    run_command.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_command.addArgs(args);

    const run_step = b.step("run", "Run SDDE");
    run_step.dependOn(&run_command.step);

    const module_tests = b.addTest(.{
        .root_module = sdde_module,
    });
    const run_module_tests = b.addRunArtifact(module_tests);

    const executable_tests = b.addTest(.{
        .root_module = executable.root_module,
    });
    const run_executable_tests = b.addRunArtifact(executable_tests);

    const yaml_safety_tests = b.addTest(.{
        .root_module = bounded_yaml_syntax_module,
    });
    const run_yaml_safety_tests = b.addRunArtifact(yaml_safety_tests);

    const version_policy_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("build/zig_version.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_version_policy_tests = b.addRunArtifact(version_policy_tests);

    const architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/architecture_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_architecture_tests = b.addRunArtifact(architecture_tests);
    run_architecture_tests.setCwd(b.path("."));

    const test_step = b.step("test", "Run all unit tests");
    const evaluator_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("harness.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const run_evaluator_tests = b.addRunArtifact(evaluator_tests);
    const evaluator_exe = b.addExecutable(.{ .name = "sdde-evaluate-spec", .root_module = b.createModule(.{
        .root_source_file = b.path("harness.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const run_evaluator = b.addRunArtifact(evaluator_exe);
    if (b.args) |args| run_evaluator.addArgs(args);
    b.step("evaluate-spec", "Grade a supplied specification through OpenAI (explicit --live required)").dependOn(&run_evaluator.step);
    b.step("build-rubric-evaluator", "Build the development-only evaluator without an API call").dependOn(&evaluator_exe.step);
    b.step("test-rubric-evaluator", "Test development-only rubric evaluation").dependOn(&run_evaluator_tests.step);
    test_step.dependOn(&run_evaluator_tests.step);
    const evaluator_directory = b.addTempFiles();
    const evaluator_binary = evaluator_directory.addCopyFile(evaluator_exe.getEmittedBin(), evaluator_exe.out_filename);
    const evaluator_help = std.Build.Step.Run.create(b, "run standalone evaluator help without development assets or credentials");
    evaluator_help.addFileArg(evaluator_binary);
    evaluator_help.addArg("--help");
    evaluator_help.setCwd(evaluator_directory.getDirectory());
    evaluator_help.clearEnvironment();
    evaluator_help.expectExitCode(0);
    evaluator_help.expectStdErrEqual("");
    const evaluator_denied = std.Build.Step.Run.create(b, "reject standalone evaluator invocation without live opt-in");
    evaluator_denied.addFileArg(evaluator_binary);
    evaluator_denied.setCwd(evaluator_directory.getDirectory());
    evaluator_denied.clearEnvironment();
    evaluator_denied.expectExitCode(1);
    evaluator_denied.expectStdOutEqual("");
    evaluator_denied.expectStdErrEqual("Invalid arguments; use --help. No API call made.\n");
    const evaluator_smoke = b.step("smoke-rubric-evaluator", "Test standalone evaluator startup without API calls");
    evaluator_smoke.dependOn(&evaluator_help.step);
    evaluator_smoke.dependOn(&evaluator_denied.step);
    _ = evaluator_directory.add("judge.json", "{\"schema\":\"evaluation-config/v1\",\"reasoning_effort\":null,\"temperature\":null,\"timeout_ms\":1000,\"retry_limit\":0,\"retry_delay_ms\":0,\"total_token_budget\":100}");
    for ([_]struct { name: []const u8, model: ?[]const u8, key: ?[]const u8, expected: []const u8 }{
        .{ .name = "reject missing test evaluation model", .model = null, .key = null, .expected = "TEST_EVALUATION_PROVIDER must be openai and TEST_EVALUATION_MODEL must be a nonempty valid model ID. No API call made.\n" },
        .{ .name = "reject production credential as evaluator fallback", .model = "scripted-judge", .key = null, .expected = "TEST_OPENAI_API_KEY is missing. No API call made.\n" },
        .{ .name = "accept test environment then reject unavailable input before any API call", .model = "scripted-judge", .key = "test-only-credential", .expected = "Invalid or unavailable case, rubric, source or specification. No API call made.\n" },
    }) |fixture| {
        const check = std.Build.Step.Run.create(b, fixture.name);
        check.addFileArg(evaluator_binary);
        check.addArgs(&.{ "--case", "missing-case.json", "--spec", "missing-spec.md", "--config", "judge.json", "--output", "missing-output", "--live" });
        check.setCwd(evaluator_directory.getDirectory());
        check.clearEnvironment();
        check.setEnvironmentVariable("OPENAI_API_KEY", "unused-production-credential");
        check.setEnvironmentVariable("TEST_EVALUATION_PROVIDER", "openai");
        if (fixture.model) |model| check.setEnvironmentVariable("TEST_EVALUATION_MODEL", model);
        if (fixture.key) |key| check.setEnvironmentVariable("TEST_OPENAI_API_KEY", key);
        check.expectExitCode(1);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(fixture.expected);
        evaluator_smoke.dependOn(&check.step);
    }
    test_step.dependOn(evaluator_smoke);
    test_step.dependOn(&run_module_tests.step);
    test_step.dependOn(&run_executable_tests.step);
    test_step.dependOn(&run_yaml_safety_tests.step);
    test_step.dependOn(&run_version_policy_tests.step);
    test_step.dependOn(&run_architecture_tests.step);
    const unicode_tests = b.addTest(.{ .root_module = unicode_module });
    const run_unicode_tests = b.addRunArtifact(unicode_tests);
    test_step.dependOn(&run_unicode_tests.step);

    const result_schema_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/model_result_schema_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const result_schema_step = b.step("test-model-result-schema", "Test the closed model result-schema boundary");
    result_schema_step.dependOn(&b.addRunArtifact(result_schema_tests).step);

    const specification_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/specification_contract_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-specification-contract", "Test the closed specification content and editable-view shapes").dependOn(&b.addRunArtifact(specification_tests).step);

    const authority_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/required_authority_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{ .{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module }, .{ .name = "unicode_normalization", .module = unicode_module } },
    }) });
    b.step("test-required-authority", "Test shared required authority, ownership routing and YAML gates").dependOn(&b.addRunArtifact(authority_tests).step);

    const request_preparation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_request_preparation_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const request_preparation_step = b.step("test-model-request-preparation", "Test provider-neutral request construction and binding validation");
    request_preparation_step.dependOn(&b.addRunArtifact(request_preparation_tests).step);

    const request_workflow_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_request_workflow_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module }},
    }) });
    b.step("test-model-request-workflow", "Test native YAML model requests, inference, response handling and accounting").dependOn(&b.addRunArtifact(request_workflow_tests).step);

    const attempt_accounting_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_attempt_accounting_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-model-attempt-accounting", "Test model attempt classification and immutable accounting transitions").dependOn(&b.addRunArtifact(attempt_accounting_tests).step);

    const invocation_validation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/provider_invocation_validation_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const invocation_validation_step = b.step("test-provider-invocation-validation", "Test provider response association and candidate eligibility");
    invocation_validation_step.dependOn(&b.addRunArtifact(invocation_validation_tests).step);

    const model_envelope_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_envelope_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const model_envelope_step = b.step("test-model-envelope", "Test strict model result decoding and retained invocation association");
    model_envelope_step.dependOn(&b.addRunArtifact(model_envelope_tests).step);

    const payload_schema_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_payload_schema_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const payload_schema_step = b.step("test-model-payload-schema", "Test bound model-result schema validation");
    payload_schema_step.dependOn(&b.addRunArtifact(payload_schema_tests).step);

    const invoke_model_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/invoke_model_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const invoke_model_step = b.step("test-invoke-model", "Test single-call provider invocation and outcome propagation");
    invoke_model_step.dependOn(&b.addRunArtifact(invoke_model_tests).step);

    const count_model_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/count_model_input_tokens_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    const count_model_step = b.step("test-count-model-input-tokens", "Test optional single-call token counting and outcome propagation");
    count_model_step.dependOn(&b.addRunArtifact(count_model_tests).step);

    const provider_conformance_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/provider_conformance_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-provider-conformance", "Test shared fake and production Bedrock contracts without AWS calls").dependOn(&b.addRunArtifact(provider_conformance_tests).step);

    const count_validation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_token_count_validation_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-model-token-count-validation", "Test exact count observation association and outcome preservation").dependOn(&b.addRunArtifact(count_validation_tests).step);

    const reference_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_preflight_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const reference_step = b.step("test-reference-preflight", "Test Specify arguments and reference selector contracts");
    reference_step.dependOn(&b.addRunArtifact(reference_tests).step);
    reference_step.dependOn(&run_unicode_tests.step);

    const ingestion_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_ingestion_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const ingestion_step = b.step("test-reference-ingestion", "Test read-only Markdown reference evidence");
    ingestion_step.dependOn(&b.addRunArtifact(ingestion_tests).step);

    const evidence_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_evidence_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const evidence_step = b.step("test-reference-evidence", "Test reference identities chunks and citation boundaries");
    evidence_step.dependOn(&b.addRunArtifact(evidence_tests).step);

    const extraction_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_extraction_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const extraction_step = b.step("test-reference-extraction", "Test closed reference claim candidates and complete chunk accounting");
    extraction_step.dependOn(&b.addRunArtifact(extraction_tests).step);

    const reconciliation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_reconciliation_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const reconciliation_step = b.step("test-reference-reconciliation", "Test hierarchical reference reconciliation and blocking conflicts");
    reconciliation_step.dependOn(&b.addRunArtifact(reconciliation_tests).step);

    const reference_model_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/reference_model_input_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    b.step("test-reference-model-input", "Test engine-owned reference model packets and exact response membership").dependOn(&b.addRunArtifact(reference_model_tests).step);

    const specification_generation_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/specification_generation_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    b.step("test-specification-generation", "Test reference-grounded specification units and engine-owned IDs").dependOn(&b.addRunArtifact(specification_generation_tests).step);

    const candidate_json_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/model_candidate_json_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-model-candidate-json", "Test compact model wire contracts and workflow schema examples").dependOn(&b.addRunArtifact(candidate_json_tests).step);

    const structured_token_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/structured_token_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const structured_token_step = b.step("test-structured-tokens", "Test exact-value extraction classification and claim accounting");
    structured_token_step.dependOn(&b.addRunArtifact(structured_token_tests).step);

    const path_token_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/path_token_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const path_token_step = b.step("test-path-tokens", "Test shared naming-policy compilation and inert path-token detection");
    path_token_step.dependOn(&b.addRunArtifact(path_token_tests).step);

    const typed_text_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/typed_text_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const typed_text_step = b.step("test-typed-text", "Test source-backed display literals and shared extraction text validation");
    typed_text_step.dependOn(&b.addRunArtifact(typed_text_tests).step);

    const feature_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/feature_directory_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const feature_step = b.step("test-feature-directory", "Test explicit config-root-relative feature directories");
    feature_step.dependOn(&b.addRunArtifact(feature_tests).step);
    feature_step.dependOn(&run_unicode_tests.step);

    const clarification_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/clarification_inputs_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    const clarification_step = b.step("test-clarification-inputs", "Test fixed artifact paths and read-only clarification inputs");
    clarification_step.dependOn(&b.addRunArtifact(clarification_tests).step);

    const atomic_execution_step = b.step("test-atomic-execution", "Test execution isolation, provider lifecycle, authorization and logging cleanup");
    for ([_][]const u8{
        "src/provider_operation_lifecycle_test.zig",
        "src/provider_authorization_test.zig",
        "src/feature_log_runtime_test.zig",
        "src/workflow_execution_test.zig",
        "src/workflow_token_accounting_test.zig",
    }) |source| {
        const tests = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
        }) });
        atomic_execution_step.dependOn(&b.addRunArtifact(tests).step);
    }

    const smoke_command = packaging_smoke.add(b, executable);
    const smoke_step = b.step("smoke", "Test the packaged executable in a clean directory");
    smoke_step.dependOn(&smoke_command.step);

    const lint_command = b.addSystemCommand(&.{
        b.graph.zig_exe,
        "fmt",
        "--check",
        "--ast-check",
    });
    lint_command.setName("lint Zig source");
    lint_command.addFileArg(b.path("build.zig"));
    lint_command.addFileArg(b.path("build.zig.zon"));
    lint_command.addFileArg(b.path("harness.zig"));
    lint_command.addDirectoryArg(b.path("build"));
    lint_command.addDirectoryArg(b.path("src"));
    lint_command.addDirectoryArg(b.path("test"));

    const lint_step = b.step("lint", "Check Zig formatting and AST validity");
    lint_step.dependOn(&lint_command.step);

    const verify_step = b.step("verify", "Run all repository verification");
    verify_step.dependOn(lint_step);
    verify_step.dependOn(test_step);
    verify_step.dependOn(smoke_step);
}
