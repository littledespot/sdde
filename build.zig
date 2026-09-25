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
    b.step("test-engine", "Test the engine without harness-specific cases").dependOn(&run_module_tests.step);

    const executable_tests = b.addTest(.{
        .root_module = executable.root_module,
    });
    const run_executable_tests = b.addRunArtifact(executable_tests);

    const yaml_safety_tests = b.addTest(.{
        .root_module = bounded_yaml_syntax_module,
    });
    const run_yaml_safety_tests = b.addRunArtifact(yaml_safety_tests);

    const architecture_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/architecture_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_architecture_tests = b.addRunArtifact(architecture_tests);
    run_architecture_tests.setCwd(b.path("."));
    b.step("test-architecture", "Test repository dependency and authority boundaries").dependOn(&run_architecture_tests.step);

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
    b.step("evaluate-spec", "Grade a supplied specification through OpenAI or Bedrock (explicit --live required)").dependOn(&run_evaluator.step);
    b.step("build-rubric-evaluator", "Build the development-only evaluator without an API call").dependOn(&evaluator_exe.step);
    b.step("test-rubric-evaluator", "Test development-only rubric evaluation").dependOn(&run_evaluator_tests.step);
    const e2e_module = b.createModule(.{
        .root_source_file = b.path("e2e.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module },
            .{ .name = "unicode_normalization", .module = unicode_module },
        },
    });
    const provenance_module = b.createModule(.{ .root_source_file = b.path("build/provenance.zig"), .target = b.graph.host, .optimize = optimize });
    const provenance_tool = b.addExecutable(.{ .name = "capture-build-provenance", .root_module = provenance_module });
    const provenance = b.addRunArtifact(provenance_tool);
    provenance.setCwd(b.path("."));
    provenance.has_side_effects = true;
    const provenance_file = provenance.addOutputFileArg("build-provenance.json");
    e2e_module.addAnonymousImport("build_provenance", .{ .root_source_file = provenance_file });
    const all_tests_module = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module },
            .{ .name = "unicode_normalization", .module = unicode_module },
        },
    });
    all_tests_module.addAnonymousImport("build_provenance", .{ .root_source_file = provenance_file });
    const all_tests = b.addRunArtifact(b.addTest(.{ .name = "repository-tests", .root_module = all_tests_module }));
    all_tests.setCwd(b.path("."));
    test_step.dependOn(&all_tests.step);
    const e2e_tests = b.addTest(.{ .root_module = e2e_module });
    const run_e2e_tests = b.addRunArtifact(e2e_tests);
    b.step("test-e2e-harness", "Test single-case E2E fixture and publication checks").dependOn(&run_e2e_tests.step);
    const launcher_tests = b.addSystemCommand(&.{"sh"});
    launcher_tests.addFileArg(b.path("test/harness/e2e/launcher_test.sh"));
    launcher_tests.addFileArg(b.path("scripts/e2e-spec.sh"));
    b.step("test-e2e-launcher", "Test local E2E environment setup and argument forwarding without API calls").dependOn(&launcher_tests.step);
    test_step.dependOn(&launcher_tests.step);
    const e2e_executable = b.addExecutable(.{ .name = "sdde-e2e-spec", .root_module = e2e_module });
    const run_e2e = b.addRunArtifact(e2e_executable);
    run_e2e.has_side_effects = true;
    if (b.args) |args| run_e2e.addArgs(args);
    b.step("e2e-spec", "Manually generate and grade one selected case").dependOn(&run_e2e.step);
    b.step("build-e2e-harness", "Build the live E2E harness without an API call").dependOn(&e2e_executable.step);
    const e2e_directory = b.addTempFiles();
    const e2e_offline = offlineExecutable(b, e2e_executable);
    const e2e_binary = e2e_directory.addCopyFile(e2e_offline.getEmittedBin(), e2e_offline.out_filename);
    const e2e_help = std.Build.Step.Run.create(b, "run standalone E2E help without development assets or credentials");
    e2e_help.addFileArg(e2e_binary);
    e2e_help.addArg("--help");
    e2e_help.setCwd(e2e_directory.getDirectory());
    e2e_help.clearEnvironment();
    e2e_help.expectExitCode(0);
    e2e_help.expectStdErrEqual("");
    const e2e_denied = std.Build.Step.Run.create(b, "reject standalone E2E invocation without explicit case selection");
    e2e_denied.addFileArg(e2e_binary);
    e2e_denied.setCwd(e2e_directory.getDirectory());
    e2e_denied.clearEnvironment();
    e2e_denied.expectExitCode(1);
    e2e_denied.expectStdOutEqual("");
    e2e_denied.expectStdErrEqual("Select exactly one E2E case with --case; use --help.\n");
    const e2e_smoke = b.step("smoke-e2e-harness", "Test standalone E2E startup without API calls");
    e2e_smoke.dependOn(&e2e_executable.step);
    e2e_smoke.dependOn(&e2e_help.step);
    e2e_smoke.dependOn(&e2e_denied.step);
    const e2e_extra_case = std.Build.Step.Run.create(b, "reject standalone E2E invocation with multiple cases");
    e2e_extra_case.addFileArg(e2e_binary);
    e2e_extra_case.addArgs(&.{ "--case", "one.json", "--case", "two.json" });
    e2e_extra_case.setCwd(e2e_directory.getDirectory());
    e2e_extra_case.clearEnvironment();
    e2e_extra_case.expectExitCode(1);
    e2e_extra_case.expectStdOutEqual("");
    e2e_extra_case.expectStdErrEqual("Select exactly one E2E case with --case; use --help.\n");
    e2e_smoke.dependOn(&e2e_extra_case.step);
    test_step.dependOn(e2e_smoke);
    const evaluator_directory = b.addTempFiles();
    const evaluator_offline = offlineExecutable(b, evaluator_exe);
    const evaluator_binary = evaluator_directory.addCopyFile(evaluator_offline.getEmittedBin(), evaluator_offline.out_filename);
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
    evaluator_smoke.dependOn(&evaluator_exe.step);
    evaluator_smoke.dependOn(&evaluator_help.step);
    evaluator_smoke.dependOn(&evaluator_denied.step);
    _ = evaluator_directory.add("judge.json", "{\"schema\":\"evaluation-config/v1\",\"reasoning_effort\":null,\"temperature\":null,\"timeout_ms\":1000,\"retry_limit\":0,\"retry_delay_ms\":0,\"total_token_budget\":100}");
    for ([_]struct { name: []const u8, provider: []const u8 = "openai", region: ?[]const u8 = null, model: ?[]const u8, key: ?[]const u8, key_name: []const u8 = "TEST_OPENAI_API_KEY", expected: []const u8 }{
        .{ .name = "reject missing test evaluation model", .model = null, .key = null, .expected = "Invalid TEST_EVALUATION_PROVIDER, TEST_EVALUATION_MODEL or TEST_EVALUATION_REGION. No API call made.\n" },
        .{ .name = "reject production credential as evaluator fallback", .model = "scripted-judge", .key = null, .expected = "TEST_OPENAI_API_KEY is missing. No API call made.\n" },
        .{ .name = "accept test environment then reject unavailable input before any API call", .model = "scripted-judge", .key = "test-only-credential", .expected = "Invalid or unavailable case, rubric, source or specification. No API call made.\n" },
        .{ .name = "reject Bedrock evaluator without an explicit region", .provider = "bedrock", .model = "openai.gpt-oss-20b-1:0", .key = null, .expected = "Invalid TEST_EVALUATION_PROVIDER, TEST_EVALUATION_MODEL or TEST_EVALUATION_REGION. No API call made.\n" },
        .{ .name = "reject production Bedrock credential as evaluator fallback", .provider = "bedrock", .region = "ap-southeast-2", .model = "openai.gpt-oss-20b-1:0", .key = null, .expected = "TEST_AWS_BEARER_TOKEN_BEDROCK is missing. No API call made.\n" },
        .{ .name = "reject unregistered Bedrock evaluation model", .provider = "bedrock", .region = "ap-southeast-2", .model = "unregistered-model", .key = null, .expected = "Invalid evaluator configuration. No API call made.\n" },
        .{ .name = "accept Bedrock test environment then reject unavailable input before any API call", .provider = "bedrock", .region = "ap-southeast-2", .model = "openai.gpt-oss-20b-1:0", .key_name = "TEST_AWS_BEARER_TOKEN_BEDROCK", .key = "test-only-credential", .expected = "Invalid or unavailable case, rubric, source or specification. No API call made.\n" },
    }) |fixture| {
        const check = std.Build.Step.Run.create(b, fixture.name);
        check.addFileArg(evaluator_binary);
        check.addArgs(&.{ "--case", "missing-case.json", "--spec", "missing-spec.md", "--config", "judge.json", "--output", "missing-output", "--live" });
        check.setCwd(evaluator_directory.getDirectory());
        check.clearEnvironment();
        check.setEnvironmentVariable("OPENAI_API_KEY", "unused-production-credential");
        check.setEnvironmentVariable("AWS_BEARER_TOKEN_BEDROCK", "unused-production-credential");
        check.setEnvironmentVariable("TEST_EVALUATION_PROVIDER", fixture.provider);
        if (fixture.region) |region| check.setEnvironmentVariable("TEST_EVALUATION_REGION", region);
        if (fixture.model) |model| check.setEnvironmentVariable("TEST_EVALUATION_MODEL", model);
        if (fixture.key) |key| check.setEnvironmentVariable(fixture.key_name, key);
        check.expectExitCode(1);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(fixture.expected);
        evaluator_smoke.dependOn(&check.step);
    }
    test_step.dependOn(evaluator_smoke);
    test_step.dependOn(&run_executable_tests.step);
    test_step.dependOn(&run_yaml_safety_tests.step);
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

    const repair_retry_tests = b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/workflow_repair_retry_test.zig"),
        .target = target,
        .optimize = optimize,
    }) }));
    b.step("test-workflow-repair-retry", "Test validated repair progress and bounded recurrence").dependOn(&repair_retry_tests.step);

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

    const native_http_tests = b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/adapters/provider/native_model_http.zig"),
        .target = target,
        .optimize = optimize,
    }) }));
    b.step("test-no-live-model-calls", "Prove native model connections are disabled in test executables").dependOn(&native_http_tests.step);
    const isolation_fixture = b.addTempFiles();
    const isolation_build = isolation_fixture.addCopyFile(b.path("test/build/live_step_isolation.zig"), "build.zig");
    _ = isolation_fixture.addCopyFile(b.path("build/live_step_isolation.zig"), "live_step_isolation.zig");
    const isolation_tests = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--build-file" });
    isolation_tests.addFileArg(isolation_build);
    isolation_tests.addArgs(&.{ "test", "--cache-dir" });
    isolation_tests.addArg(b.cache_root.path orelse ".zig-cache");
    b.step("test-build-isolation", "Reject direct and transitive live harness dependencies from automated steps").dependOn(&isolation_tests.step);
    test_step.dependOn(&isolation_tests.step);

    const registration_fixture = b.addTempFiles();
    const registration_build = registration_fixture.addCopyFile(b.path("test/build/test_registration.zig"), "build.zig");
    _ = registration_fixture.addCopyFile(b.path("build/test_registration.zig"), "test_registration.zig");
    const registration_tests = b.addSystemCommand(&.{ b.graph.zig_exe, "build", "--build-file" });
    registration_tests.addFileArg(registration_build);
    registration_tests.addArgs(&.{ "test", "--cache-dir" });
    registration_tests.addArg(b.cache_root.path orelse ".zig-cache");
    b.step("test-build-registration", "Reject extra or missing full-suite test executions").dependOn(&registration_tests.step);
    test_step.dependOn(&registration_tests.step);

    const timing_tests = b.addRunArtifact(b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/test_fixtures/scenario_timing.zig"),
        .target = target,
        .optimize = optimize,
    }) }));
    b.step("test-scenario-timing", "Test scenario cost reporting and incomplete-run accounting").dependOn(&timing_tests.step);

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

    const principle_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/principle_registry_test.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
    }) });
    b.step("test-principle-registry", "Test canonical principle capture and configured selection").dependOn(&b.addRunArtifact(principle_tests).step);

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
    b.step("test-model-candidate-json", "Test compact model wire contracts against independent schema cases").dependOn(&b.addRunArtifact(candidate_json_tests).step);

    const model_logging_step = b.step("test-model-logging", "Test complete model exchange capture and credential redaction");
    for ([_][]const u8{
        "src/model_log_redaction_test.zig",
        "src/model_exchange_capture_test.zig",
        "src/request_debugger_test.zig",
        "src/feature_log_layout_test.zig",
    }) |source| {
        const tests = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "unicode_normalization", .module = unicode_module }},
        }) });
        model_logging_step.dependOn(&b.addRunArtifact(tests).step);
    }

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

    const graph_step = b.step("test-workflow-graph", "Test workflow compilation, graph bounds and runner execution");
    const operation_registry_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/workflow_operation_registry_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-workflow-operation-registry", "Test current operation registry schemas, bindings and authority").dependOn(&b.addRunArtifact(operation_registry_tests).step);
    for ([_][]const u8{ "src/workflow_definition_test.zig", "src/workflow_registry_test.zig", "src/workflow_json_composition_test.zig" }) |source| {
        const graph_tests = b.addTest(.{ .root_module = b.createModule(.{
            .root_source_file = b.path(source),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "bounded_yaml_syntax", .module = bounded_yaml_syntax_module }},
        }) });
        graph_step.dependOn(&b.addRunArtifact(graph_tests).step);
    }

    const atomic_execution_step = b.step("test-atomic-execution", "Test execution isolation, provider lifecycle, authorization and logging cleanup");
    const envelope_tests = b.addTest(.{ .root_module = b.createModule(.{
        .root_source_file = b.path("src/pipeline_data_test.zig"),
        .target = target,
        .optimize = optimize,
    }) });
    b.step("test-pipeline-envelope", "Test pipeline value ownership and origin metadata").dependOn(&b.addRunArtifact(envelope_tests).step);
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
        const run_tests = b.addRunArtifact(tests);
        atomic_execution_step.dependOn(&run_tests.step);
        if (std.mem.eql(u8, source, "src/feature_log_runtime_test.zig"))
            b.step("test-feature-log-runtime", "Test feature log serialization, rotation and failures").dependOn(&run_tests.step);
        if (std.mem.eql(u8, source, "src/workflow_execution_test.zig")) graph_step.dependOn(&run_tests.step);
    }

    const smoke_command = packaging_smoke.add(b, offlineExecutable(b, executable));
    const smoke_step = b.step("smoke", "Test the packaged executable in a clean directory");
    smoke_step.dependOn(&smoke_command.step);
    smoke_step.dependOn(&executable.step);
    const network_probe = b.addExecutable(.{ .name = "model-network-probe", .root_module = b.createModule(.{
        .root_source_file = b.path("test/packaging/model_network_probe.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "native_model_http", .module = b.createModule(.{
            .root_source_file = b.path("src/adapters/provider/native_model_http.zig"),
            .target = target,
            .optimize = optimize,
        }) }},
    }) });
    const run_network_probe = b.addRunArtifact(offlineExecutable(b, network_probe));
    run_network_probe.clearEnvironment();
    run_network_probe.expectExitCode(0);
    b.step("smoke-no-live-model-calls", "Prove ordinary automated subprocesses cannot open model connections").dependOn(&run_network_probe.step);
    smoke_step.dependOn(&run_network_probe.step);

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
    lint_command.addFileArg(b.path("e2e.zig"));
    lint_command.addFileArg(b.path("tests.zig"));
    lint_command.addDirectoryArg(b.path("build"));
    lint_command.addDirectoryArg(b.path("src"));
    lint_command.addDirectoryArg(b.path("test"));

    const lint_step = b.step("lint", "Check Zig formatting and AST validity");
    lint_step.dependOn(&lint_command.step);

    const verify_step = b.step("verify", "Run all repository verification");
    verify_step.dependOn(lint_step);
    verify_step.dependOn(test_step);
    verify_step.dependOn(smoke_step);
    @import("build/test_registration.zig").check(b.allocator, verify_step, &.{
        all_tests, run_executable_tests, run_yaml_safety_tests, run_unicode_tests,
    }) catch |err| std.debug.panic("full-suite test registration failed: {s}", .{@errorName(err)});
    // Live execution is reachable only from the explicitly selected manual
    // commands. Check transitive dependencies, including every targeted suite.
    for (b.top_level_steps.values()) |entry| {
        const name = entry.step.name;
        if (std.mem.eql(u8, name, "test") or std.mem.eql(u8, name, "verify") or
            std.mem.eql(u8, name, "smoke") or std.mem.startsWith(u8, name, "test-") or
            std.mem.startsWith(u8, name, "smoke-"))
        {
            @import("build/live_step_isolation.zig").check(b.allocator, &entry.step, &.{ &run_e2e.step, &run_evaluator.step }) catch |err|
                std.debug.panic("automated step {s} violates manual-only model execution: {s}", .{ name, @errorName(err) });
        }
    }
}

fn offlineExecutable(b: *std.Build, application: *std.Build.Step.Compile) *std.Build.Step.Compile {
    return b.addExecutable(.{ .name = application.name, .root_module = b.createModule(.{
        .root_source_file = b.path("test/packaging/offline.zig"),
        .target = application.root_module.resolved_target,
        .optimize = application.root_module.optimize,
        .imports = &.{.{ .name = "application", .module = application.root_module }},
    }) });
}
