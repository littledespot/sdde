const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const configuration =
        \\{
        \\  "logs": { "level": "debug", "console": false, "promptCapture": [] },
        \\  "models": { "slots": {} },
        \\  "paths": {
        \\    "specs": "requirements/current", "references": "references",
        \\    "specsArchive": "requirements/current/_archive", "workflows": ".sddtoolkit/workflows",
        \\    "toolchainPreset": ".sddtoolkit/toolchainPreset",
        \\    "principles": ".sddtoolkit/principles", "templates": ".sddtoolkit/templates",
        \\    "providers": ".sddproviders.json"
        \\  }
        \\}
    ;
    _ = package_directory.add(".sddtoolkit.json", configuration);
    _ = package_directory.add(".sddtoolkit/workflows/features/.keep", "");
    const hello_workflow =
        \\schema: workflow/v1
        \\id: hello
        \\version: 1
        \\shortcode: HELO
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: run
        \\steps:
        \\  run:
        \\    use: core.noop
        \\    on: { ok: end.ok }
    ;
    _ = package_directory.add(".sddtoolkit/workflows/transactions/hello.workflow.yaml", hello_workflow);
    _ = package_directory.add(".sddtoolkit/workflows/request-ledger.workflow.yaml",
        \\schema: workflow/v1
        \\id: request-ledger
        \\version: 1
        \\shortcode: MREQ
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: initialize
        \\steps:
        \\  initialize:
        \\    use: build-initial-model-request-identity-ledger
        \\    on: { ok: end.ok, failed: end.failed }
    );
    _ = package_directory.add(".sddtoolkit/workflows/toolchain.workflow.yaml", @embedFile("../../src/test_fixtures/toolchain.workflow.yaml"));
    _ = package_directory.add(".sddtoolkit/workflows/preflight.workflow.yaml", @embedFile("../../src/test_fixtures/reference-preflight.workflow.yaml"));
    _ = package_directory.add(".sddtoolkit/workflows/feature-input.workflow.yaml", @embedFile("../../src/test_fixtures/feature-input-preflight.workflow.yaml"));
    _ = package_directory.add(".sddtoolkit/workflows/reference-ingestion.workflow.yaml", @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml"));
    _ = package_directory.addCopyFile(b.path("test/evaluation/wf-001-hello-world/reference/stories.md"), "references/Hello/stories.md");
    _ = package_directory.add("references/Unsupported/story.md", "# Valid sibling\n");
    _ = package_directory.add("references/Unsupported/.hidden.json", "{}");
    const clarification = @import("../../src/test_fixtures/clarification_inputs.zig").closed(b.allocator, "P01", true) catch @panic("allocate packaging clarification fixture");
    _ = package_directory.add(".sddtoolkit/workflows/features/Chosen/Café/state/clarifications.json", clarification.state.?);
    _ = package_directory.add("requirements/current/Chosen/Café/clarify/P01.md", clarification.forms[0].bytes);
    _ = package_directory.add("requirements/current/Orphan/clarify/P01.md", clarification.forms[0].bytes);
    _ = package_directory.add("references/Café/日本語/stories.md", "Hello, World!\n");
    // A hard-coded specs root would select this non-directory and fail.
    _ = package_directory.add("specs/Selected/日本語", "not a directory\n");
    _ = package_directory.add(".sddtoolkit/toolchainPreset/core.toolchain-preset.yaml", "invalid unselected preset");
    _ = package_directory.add(".sddtoolkit/principles/toolchain.yaml", "invalid unselected project layer");

    const valid_command = std.Build.Step.Run.create(b, "run packaged SDDE executable");
    valid_command.addFileArg(packaged_executable);
    valid_command.addArg("hello");
    valid_command.setCwd(package_directory.getDirectory());
    valid_command.clearEnvironment();
    valid_command.expectStdOutEqual("");
    valid_command.expectStdErrEqual("");

    const request_ledger_command = std.Build.Step.Run.create(b, "run packaged YAML request initialization without providers or development assets");
    request_ledger_command.addFileArg(packaged_executable);
    request_ledger_command.addArg("request-ledger");
    request_ledger_command.setCwd(package_directory.getDirectory());
    request_ledger_command.clearEnvironment();
    request_ledger_command.expectStdOutEqual("");
    request_ledger_command.expectStdErrEqual("");

    const unregistered_directory = b.addTempFiles();
    const unregistered_executable = unregistered_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = unregistered_directory.add(".sddtoolkit.json", configuration);
    _ = unregistered_directory.add(".sddtoolkit/workflows/hello.workflow.yaml", hello_workflow);
    _ = unregistered_directory.add(".sddtoolkit/workflows/transactions/unregistered.json", "{}");
    const denied_unregistered = std.Build.Step.Run.create(b, "reject unregistered files beneath an ordinary packaged workflow directory");
    denied_unregistered.addFileArg(unregistered_executable);
    denied_unregistered.addArg("hello");
    denied_unregistered.setCwd(unregistered_directory.getDirectory());
    denied_unregistered.clearEnvironment();
    denied_unregistered.expectExitCode(1);
    denied_unregistered.expectStdOutEqual("");
    denied_unregistered.expectStdErrEqual("WORKFLOW_AUTHORITY_INVENTORY_INVALID\n");

    const missing_request_directory = b.addTempFiles();
    const missing_request_executable = missing_request_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_request_directory.add(".sddtoolkit.json", configuration);
    _ = missing_request_directory.add(".sddtoolkit/workflows/account.workflow.yaml",
        \\schema: workflow/v1
        \\id: account
        \\version: 1
        \\shortcode: ACCT
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: account
        \\steps:
        \\  account: { use: advance-model-attempt-accounting, with: { retry-limit: 0 }, on: { ok: end.ok, failed: end.failed } }
    );
    const denied_accounting = std.Build.Step.Run.create(b, "reject packaged attempt accounting without a prepared request");
    denied_accounting.addFileArg(missing_request_executable);
    denied_accounting.addArg("account");
    denied_accounting.setCwd(missing_request_directory.getDirectory());
    denied_accounting.clearEnvironment();
    denied_accounting.expectExitCode(1);
    denied_accounting.expectStdOutEqual("");
    denied_accounting.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");

    const missing_attempt_directory = b.addTempFiles();
    const missing_attempt_executable = missing_attempt_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_attempt_directory.add(".sddtoolkit.json", configuration);
    _ = missing_attempt_directory.add(".sddtoolkit/workflows/assign.workflow.yaml",
        \\schema: workflow/v1
        \\id: assign
        \\version: 1
        \\shortcode: ASGN
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: assign
        \\steps:
        \\  assign: { use: assign-provider-operation, with: { kind: inference }, on: { ok: end.ok, failed: end.failed } }
    );
    const denied_assignment = std.Build.Step.Run.create(b, "reject packaged provider assignment without prepared request and attempt evidence");
    denied_assignment.addFileArg(missing_attempt_executable);
    denied_assignment.addArg("assign");
    denied_assignment.setCwd(missing_attempt_directory.getDirectory());
    denied_assignment.clearEnvironment();
    denied_assignment.expectExitCode(1);
    denied_assignment.expectStdOutEqual("");
    denied_assignment.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_accounting.step.dependOn(&denied_assignment.step);

    const missing_assignment_directory = b.addTempFiles();
    const missing_assignment_executable = missing_assignment_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_assignment_directory.add(".sddtoolkit.json", configuration);
    _ = missing_assignment_directory.add(".sddtoolkit/workflows/authorize.workflow.yaml",
        \\schema: workflow/v1
        \\id: authorize
        \\version: 1
        \\shortcode: AUTH
        \\invoke: core.empty-invocation
        \\policy: core.model-authorization@1
        \\start: authorize
        \\steps:
        \\  authorize: { use: prepare-provider-operation-authorization, with: { timeout-ms: 1000 }, on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled } }
    );
    const denied_authorization = std.Build.Step.Run.create(b, "reject packaged authorization without an assigned operation");
    denied_authorization.addFileArg(missing_assignment_executable);
    denied_authorization.addArg("authorize");
    denied_authorization.setCwd(missing_assignment_directory.getDirectory());
    denied_authorization.clearEnvironment();
    denied_authorization.expectExitCode(1);
    denied_authorization.expectStdOutEqual("");
    denied_authorization.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_assignment.step.dependOn(&denied_authorization.step);

    const missing_authorization_directory = b.addTempFiles();
    const missing_authorization_executable = missing_authorization_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_authorization_directory.add(".sddtoolkit.json", configuration);
    _ = missing_authorization_directory.add(".sddtoolkit/workflows/advance.workflow.yaml",
        \\schema: workflow/v1
        \\id: advance
        \\version: 1
        \\shortcode: ADVN
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: advance
        \\steps:
        \\  advance: { use: advance-model-request-lifecycle, with: { transition: invoked }, on: { ok: end.ok, failed: end.failed } }
    );
    const denied_request_lifecycle = std.Build.Step.Run.create(b, "reject packaged request invocation without prepared authorization");
    denied_request_lifecycle.addFileArg(missing_authorization_executable);
    denied_request_lifecycle.addArg("advance");
    denied_request_lifecycle.setCwd(missing_authorization_directory.getDirectory());
    denied_request_lifecycle.clearEnvironment();
    denied_request_lifecycle.expectExitCode(1);
    denied_request_lifecycle.expectStdOutEqual("");
    denied_request_lifecycle.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_authorization.step.dependOn(&denied_request_lifecycle.step);

    const missing_invocation_directory = b.addTempFiles();
    const missing_invocation_executable = missing_invocation_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_invocation_directory.add(".sddtoolkit.json", configuration);
    _ = missing_invocation_directory.add(".sddtoolkit/workflows/advance-operation.workflow.yaml",
        \\schema: workflow/v1
        \\id: advance-operation
        \\version: 1
        \\shortcode: AOPR
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: advance
        \\steps:
        \\  advance: { use: advance-provider-operation-lifecycle, with: { transition: invoked }, on: { ok: end.ok, failed: end.failed } }
    );
    const denied_operation_lifecycle = std.Build.Step.Run.create(b, "reject packaged provider invocation without its prepared lease and assigned operation");
    denied_operation_lifecycle.addFileArg(missing_invocation_executable);
    denied_operation_lifecycle.addArg("advance-operation");
    denied_operation_lifecycle.setCwd(missing_invocation_directory.getDirectory());
    denied_operation_lifecycle.clearEnvironment();
    denied_operation_lifecycle.expectExitCode(1);
    denied_operation_lifecycle.expectStdOutEqual("");
    denied_operation_lifecycle.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_request_lifecycle.step.dependOn(&denied_operation_lifecycle.step);

    const missing_call_inputs = b.addTempFiles();
    const call_executable = missing_call_inputs.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = missing_call_inputs.add(".sddtoolkit.json", configuration);
    _ = missing_call_inputs.add(".sddtoolkit/workflows/call.workflow.yaml",
        \\schema: workflow/v1
        \\id: call
        \\version: 1
        \\shortcode: CALL
        \\invoke: core.empty-invocation
        \\policy: core.model-inference@1
        \\start: call
        \\steps:
        \\  call: { use: invoke-model, on: { ok: end.ok, failed: end.failed, cancelled: end.cancelled } }
    );
    const denied_call = std.Build.Step.Run.create(b, "reject packaged model call without retained request invocation and authorization");
    denied_call.addFileArg(call_executable);
    denied_call.addArg("call");
    denied_call.setCwd(missing_call_inputs.getDirectory());
    denied_call.clearEnvironment();
    denied_call.expectExitCode(1);
    denied_call.expectStdOutEqual("");
    denied_call.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_operation_lifecycle.step.dependOn(&denied_call.step);

    const denied_toolchain = std.Build.Step.Run.create(b, "reject invalid toolchain only when selected");
    denied_toolchain.addFileArg(packaged_executable);
    denied_toolchain.addArg("toolchain-check");
    denied_toolchain.setCwd(package_directory.getDirectory());
    denied_toolchain.clearEnvironment();
    denied_toolchain.expectExitCode(1);
    denied_toolchain.expectStdOutEqual("");
    denied_toolchain.expectStdErrEqual("failed\n");

    const toolchain_directory = b.addTempFiles();
    const toolchain_executable = toolchain_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = toolchain_directory.add(".sddtoolkit.json", configuration);
    _ = toolchain_directory.add(".sddtoolkit/workflows/toolchain.workflow.yaml", @embedFile("../../src/test_fixtures/toolchain.workflow.yaml"));
    _ = toolchain_directory.add(".sddtoolkit/principles/toolchain.yaml", "schema: project-toolchain/v1\npresets: [core@1.0.0]\npolicies: []\n");
    _ = toolchain_directory.add(".sddtoolkit/toolchainPreset/core.toolchain-preset.yaml", "schema: toolchain-preset/v1\npackage: core@1.0.0\nlayer: environment\nextends: []\npolicies: []\n");
    const toolchain_command = std.Build.Step.Run.create(b, "run packaged YAML-selected toolchain operations");
    toolchain_command.addFileArg(toolchain_executable);
    toolchain_command.addArg("toolchain-check");
    toolchain_command.setCwd(toolchain_directory.getDirectory());
    toolchain_command.clearEnvironment();
    toolchain_command.expectStdOutEqual("");
    toolchain_command.expectStdErrEqual("");

    _ = toolchain_directory.add(".sddtoolkit/workflows/path-tokens.workflow.yaml", @import("../../src/test_fixtures/path_token_workflow.zig").yaml(b.allocator) catch @panic("build path-token fixture"));
    _ = toolchain_directory.add(".sddtoolkit/workflows/sample.txt", "Use stories.md, spec.md and src/main.zig; https://example.test is inert text.");
    _ = toolchain_directory.add("references/Hello/stories.md", "A simple business requirement.\n");
    const path_token_command = std.Build.Step.Run.create(b, "run packaged shared naming-policy and path-token detector");
    path_token_command.addFileArg(toolchain_executable);
    path_token_command.addArgs(&.{ "reference-ingestion", "--feature", "Lexical/Example", "--reference", "Hello" });
    path_token_command.setCwd(toolchain_directory.getDirectory());
    path_token_command.clearEnvironment();
    path_token_command.expectStdOutEqual("");
    path_token_command.expectStdErrEqual("");

    const literal_yaml = @import("../../src/test_fixtures/reference_text_workflow.zig").yaml(b.allocator) catch @panic("build passive-literal fixture");
    const named_literal_yaml = std.mem.replaceOwned(u8, b.allocator, literal_yaml, "id: reference-ingestion", "id: display-literals") catch @panic("name passive-literal fixture");
    const distinct_literal_yaml = std.mem.replaceOwned(u8, b.allocator, named_literal_yaml, "shortcode: RING", "shortcode: LITR") catch @panic("name passive-literal log scope");
    _ = toolchain_directory.add(".sddtoolkit/workflows/display-literals.workflow.yaml", distinct_literal_yaml);
    const literal_command = std.Build.Step.Run.create(b, "run packaged source-backed passive-literal preparation");
    literal_command.addFileArg(toolchain_executable);
    literal_command.addArgs(&.{ "display-literals", "--feature", "Literal/Example", "--reference", "Hello" });
    literal_command.setCwd(toolchain_directory.getDirectory());
    literal_command.clearEnvironment();
    literal_command.expectStdOutEqual("");
    literal_command.expectStdErrEqual("");

    const missing_config_directory = b.addTempFiles();
    const reference_command = std.Build.Step.Run.create(b, "run packaged config-root-relative feature and Unicode reference preflight");
    reference_command.addFileArg(packaged_executable);
    reference_command.addArgs(&.{ "reference-preflight", "--feature", "Selected/日本語", "--reference", "./Cafe\u{301}/日本語" });
    reference_command.setCwd(package_directory.getDirectory());
    reference_command.clearEnvironment();
    reference_command.expectStdOutEqual("");
    reference_command.expectStdErrEqual("");

    const denied_reference = std.Build.Step.Run.create(b, "reject packaged reference traversal");
    denied_reference.addFileArg(packaged_executable);
    denied_reference.addArgs(&.{ "reference-preflight", "--feature", "Selected/日本語", "--reference", "../references" });
    denied_reference.setCwd(package_directory.getDirectory());
    denied_reference.clearEnvironment();
    denied_reference.expectExitCode(1);
    denied_reference.expectStdOutEqual("");
    denied_reference.expectStdErrEqual("failed\n");
    const executable_without_config = missing_config_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const missing_config_command = std.Build.Step.Run.create(
        b,
        "reject packaged SDDE invocation without target config",
    );
    missing_config_command.step.dependOn(&valid_command.step);
    missing_config_command.step.dependOn(&request_ledger_command.step);
    missing_config_command.step.dependOn(&denied_unregistered.step);
    missing_config_command.step.dependOn(&denied_accounting.step);
    missing_config_command.step.dependOn(&denied_toolchain.step);
    missing_config_command.step.dependOn(&toolchain_command.step);
    missing_config_command.step.dependOn(&path_token_command.step);
    missing_config_command.step.dependOn(&literal_command.step);
    missing_config_command.step.dependOn(&reference_command.step);
    missing_config_command.step.dependOn(&denied_reference.step);
    for ([_][2][]const u8{
        .{ "invoke: core.empty-invocation", "invoke: core.empty-invocation@1" },
        .{ "use: core.noop", "use: core.noop@1" },
    }) |change| {
        const directory = b.addTempFiles();
        const packaged = directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
        _ = directory.add(".sddtoolkit.json", configuration);
        const yaml = std.mem.replaceOwned(u8, b.allocator, hello_workflow, change[0], change[1]) catch @panic("allocate retired operation ID fixture");
        _ = directory.add(".sddtoolkit/workflows/hello.workflow.yaml", yaml);
        const rejected = std.Build.Step.Run.create(b, "reject packaged version-suffixed operation IDs without compatibility aliases");
        rejected.addFileArg(packaged);
        rejected.addArg("hello");
        rejected.setCwd(directory.getDirectory());
        rejected.clearEnvironment();
        rejected.expectExitCode(1);
        rejected.expectStdOutEqual("");
        rejected.expectStdErrEqual("WORKFLOW_DEFINITION_SCHEMA_INVALID\n");
        missing_config_command.step.dependOn(&rejected.step);
    }
    for ([_]struct { selector: []const u8, rejected: bool }{
        .{ .selector = "Hello", .rejected = false },
        .{ .selector = "Unsupported", .rejected = true },
    }) |case| {
        const check = std.Build.Step.Run.create(b, "run packaged read-only Markdown reference ingestion");
        check.addFileArg(packaged_executable);
        check.addArgs(&.{ "reference-ingestion", "--feature", "Chosen/Café", "--reference", case.selector });
        check.setCwd(package_directory.getDirectory());
        check.clearEnvironment();
        check.expectExitCode(if (case.rejected) 1 else 0);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(if (case.rejected) "failed\n" else "");
        missing_config_command.step.dependOn(&check.step);
    }
    for ([_]struct { feature: []const u8, rejected: bool }{
        .{ .feature = "Selected/日本語", .rejected = false },
        .{ .feature = "Chosen/Café", .rejected = false },
        .{ .feature = "Orphan", .rejected = true },
    }) |case| {
        const check = std.Build.Step.Run.create(b, "run packaged read-only clarification preflight");
        check.addFileArg(packaged_executable);
        check.addArgs(&.{ "feature-input-preflight", "--feature", case.feature, "--reference", "Café/日本語" });
        check.setCwd(package_directory.getDirectory());
        check.clearEnvironment();
        check.expectExitCode(if (case.rejected) 1 else 0);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(if (case.rejected) "failed\n" else "");
        missing_config_command.step.dependOn(&check.step);
    }
    for ([_][]const []const u8{
        &.{ "reference-preflight", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "../escape", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "_archive/child", "--reference", "Café/日本語" },
    }) |arguments| {
        const rejected = std.Build.Step.Run.create(b, "reject packaged invalid feature selection");
        rejected.addFileArg(packaged_executable);
        rejected.addArgs(arguments);
        rejected.setCwd(package_directory.getDirectory());
        rejected.clearEnvironment();
        rejected.expectExitCode(1);
        rejected.expectStdOutEqual("");
        rejected.expectStdErrEqual("failed\n");
        missing_config_command.step.dependOn(&rejected.step);
    }
    missing_config_command.addFileArg(executable_without_config);
    missing_config_command.addArg("hello");
    missing_config_command.setCwd(missing_config_directory.getDirectory());
    missing_config_command.clearEnvironment();
    missing_config_command.expectExitCode(1);
    missing_config_command.expectStdOutEqual("");
    missing_config_command.expectStdErrEqual("ENGINE_CONFIG_READ_ERROR\n");

    return missing_config_command;
}
