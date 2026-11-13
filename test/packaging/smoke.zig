const std = @import("std");

pub fn add(b: *std.Build, executable: *std.Build.Step.Compile) *std.Build.Step.Run {
    const package_directory = b.addTempFiles();
    const packaged_executable = package_directory.addCopyFile(
        executable.getEmittedBin(),
        executable.out_filename,
    );
    const configuration =
        \\{
        \\  "logs": { "level": "debug", "console": false },
        \\  "workflowTokenBudget": 100000,
        \\  "temperature": 0.1,
        \\  "temperatureRunawayRetry": 1,
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
    _ = package_directory.add(".sddtoolkit/workflows/reference-ingestion.workflow.yaml", @embedFile("../../src/test_fixtures/reference-ingestion.workflow.yaml"));
    _ = package_directory.addCopyFile(b.path("test/e2e/wf-001-hello-world/reference/stories.md"), "references/Hello/stories.md");
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

    _ = package_directory.add("requirements/current/debugger-fixture/.keep", "");
    const debugger_probe = b.addExecutable(.{ .name = "debugger-smoke", .root_module = b.createModule(.{
        .root_source_file = b.path("test/packaging/debugger_smoke.zig"),
        .target = b.graph.host,
        .optimize = .Debug,
    }) });
    const debugger_command = b.addRunArtifact(debugger_probe);
    debugger_command.setName("serve embedded request debugger from packaged executable");
    debugger_command.addFileArg(packaged_executable);
    debugger_command.setCwd(package_directory.getDirectory());
    debugger_command.clearEnvironment();
    debugger_command.expectExitCode(0);
    debugger_command.expectStdOutEqual("");
    debugger_command.expectStdErrEqual("");
    valid_command.step.dependOn(&debugger_command.step);

    _ = package_directory.add(".sddtoolkit/workflows/reused.workflow.yaml",
        \\schema: workflow/v1
        \\id: reused
        \\version: 1
        \\shortcode: REUS
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: first
        \\steps:
        \\  first: {call: empty, on: {ok: second}}
        \\  second: {call: empty, on: {ok: end.ok}}
        \\subgraphs:
        \\  empty:
        \\    start: run
        \\    steps:
        \\      run: {use: core.noop, on: {ok: end.ok}}
    );
    const reused_command = std.Build.Step.Run.create(b, "run packaged local subgraphs without models or external resources");
    reused_command.addFileArg(packaged_executable);
    reused_command.addArg("reused");
    reused_command.setCwd(package_directory.getDirectory());
    reused_command.clearEnvironment();
    reused_command.expectExitCode(0);
    reused_command.expectStdOutEqual("");
    reused_command.expectStdErrEqual("");
    valid_command.step.dependOn(&reused_command.step);

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

    // The request lifecycle is the engine's `request-model` step (ADR 0030): neither an
    // operation of the removed lifecycle nor one of its stages is a selectable operation.
    // Each packaged case below is rejected as an unknown operation, not for missing inputs.
    const removed_id_directory = b.addTempFiles();
    const removed_id_executable = removed_id_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = removed_id_directory.add(".sddtoolkit.json", configuration);
    _ = removed_id_directory.add(".sddtoolkit/workflows/account.workflow.yaml",
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
    const denied_removed_id = std.Build.Step.Run.create(b, "reject a packaged operation of the removed request lifecycle as an unknown operation");
    denied_removed_id.addFileArg(removed_id_executable);
    denied_removed_id.addArg("account");
    denied_removed_id.setCwd(removed_id_directory.getDirectory());
    denied_removed_id.clearEnvironment();
    denied_removed_id.expectExitCode(1);
    denied_removed_id.expectStdOutEqual("");
    denied_removed_id.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");

    const stage_id_directory = b.addTempFiles();
    const stage_id_executable = stage_id_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = stage_id_directory.add(".sddtoolkit.json", configuration);
    _ = stage_id_directory.add(".sddtoolkit/workflows/stage.workflow.yaml",
        \\schema: workflow/v1
        \\id: stage
        \\version: 1
        \\shortcode: STGE
        \\invoke: core.empty-invocation
        \\policy: core.capability-free@1
        \\start: stage
        \\steps:
        \\  stage: { use: advance-attempt, with: { retry-limit: 0 }, on: { ok: end.ok, failed: end.failed } }
    );
    const denied_stage_id = std.Build.Step.Run.create(b, "reject a packaged request stage id as an unknown operation");
    denied_stage_id.addFileArg(stage_id_executable);
    denied_stage_id.addArg("stage");
    denied_stage_id.setCwd(stage_id_directory.getDirectory());
    denied_stage_id.clearEnvironment();
    denied_stage_id.expectExitCode(1);
    denied_stage_id.expectStdOutEqual("");
    denied_stage_id.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    denied_removed_id.step.dependOn(&denied_stage_id.step);

    for ([_][2][]const u8{
        .{ "build-specification-authority-requirements", "ok: end.ok, blocked: end.blocked" },
        .{ "build-required-authority-ledger", "ok: end.ok, blocked: end.blocked" },
        .{ "parse-required-authority-observations", "ok: end.ok, blocked: end.blocked" },
        .{ "reconcile-required-authorities", "ok: end.ok, needs-user: end.needs-user, blocked: end.blocked" },
        .{ "validate-required-authority-reconciliation", "ok: end.ok, needs-user: end.needs-user, blocked: end.blocked" },
    }) |contract| {
        const project = b.addTempFiles();
        const binary = project.addCopyFile(executable.getEmittedBin(), executable.out_filename);
        _ = project.add(".sddtoolkit.json", configuration);
        _ = project.add(".sddtoolkit/workflows/authority.workflow.yaml", b.fmt(
            "schema: workflow/v1\nid: authority\nversion: 1\nshortcode: AUTH\ninvoke: core.empty-invocation\npolicy: core.capability-free@1\nstart: check\nsteps:\n  check: {{ use: {s}, on: {{{s}}} }}\n",
            .{ contract[0], contract[1] },
        ));
        const denied = std.Build.Step.Run.create(b, b.fmt("reject packaged {s} without current authority inputs", .{contract[0]}));
        denied.addFileArg(binary);
        denied.addArg("authority");
        denied.setCwd(project.getDirectory());
        denied.clearEnvironment();
        denied.expectExitCode(1);
        denied.expectStdOutEqual("");
        denied.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
        denied_stage_id.step.dependOn(&denied.step);
    }

    const denied_toolchain = std.Build.Step.Run.create(b, "reject invalid toolchain only when selected");
    denied_toolchain.addFileArg(packaged_executable);
    denied_toolchain.addArg("toolchain-check");
    denied_toolchain.setCwd(package_directory.getDirectory());
    denied_toolchain.clearEnvironment();
    denied_toolchain.expectExitCode(1);
    denied_toolchain.expectStdOutEqual("");
    denied_toolchain.expectStdErrEqual("InvalidToolchain\n");

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

    const literal_yaml = @import("../../src/test_fixtures/path_token_workflow.zig").prepared(b.allocator) catch @panic("build passive-literal fixture");
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

    const token_yaml = @import("../../src/test_fixtures/path_token_workflow.zig").prepared(b.allocator) catch @panic("build structured-token fixture");
    const named_token_yaml = std.mem.replaceOwned(u8, b.allocator, token_yaml, "id: reference-ingestion", "id: exact-values") catch @panic("name exact-value fixture");
    const distinct_token_yaml = std.mem.replaceOwned(u8, b.allocator, named_token_yaml, "shortcode: RING", "shortcode: EXAC") catch @panic("name exact-value log scope");
    _ = toolchain_directory.add(".sddtoolkit/workflows/exact-values.workflow.yaml", distinct_token_yaml);
    _ = toolchain_directory.add("references/Exact/requirements.md", "Display `Hello, World!` and retain `Cafe\u{301}`.\n~~~\n`not eligible`\n~~~\n");
    const token_command = std.Build.Step.Run.create(b, "run packaged source-backed exact-value candidate preparation");
    token_command.addFileArg(toolchain_executable);
    token_command.addArgs(&.{ "exact-values", "--feature", "Exact/Example", "--reference", "Exact" });
    token_command.setCwd(toolchain_directory.getDirectory());
    token_command.clearEnvironment();
    token_command.expectExitCode(0);
    token_command.expectStdOutEqual("");
    token_command.expectStdErrEqual("");

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
    denied_reference.expectStdErrEqual("InvalidReferenceSelector\n");
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
    missing_config_command.step.dependOn(&denied_removed_id.step);
    missing_config_command.step.dependOn(&denied_toolchain.step);
    missing_config_command.step.dependOn(&toolchain_command.step);
    missing_config_command.step.dependOn(&path_token_command.step);
    missing_config_command.step.dependOn(&literal_command.step);
    missing_config_command.step.dependOn(&token_command.step);
    missing_config_command.step.dependOn(&reference_command.step);
    missing_config_command.step.dependOn(&denied_reference.step);
    const progress_directory = b.addTempFiles();
    const progress_executable = progress_directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
    _ = progress_directory.add(".sddtoolkit.json", configuration);
    const progress_yaml = std.mem.replaceOwned(u8, b.allocator, hello_workflow, "end.ok", "end.more") catch @panic("allocate invalid terminal fixture");
    _ = progress_directory.add(".sddtoolkit/workflows/hello.workflow.yaml", progress_yaml);
    const denied_progress = std.Build.Step.Run.create(b, "reject packaged progress as workflow completion");
    denied_progress.addFileArg(progress_executable);
    denied_progress.addArg("hello");
    denied_progress.setCwd(progress_directory.getDirectory());
    denied_progress.clearEnvironment();
    denied_progress.expectExitCode(1);
    denied_progress.expectStdOutEqual("");
    denied_progress.expectStdErrEqual("WORKFLOW_GRAPH_COMPILE_INVALID\n");
    missing_config_command.step.dependOn(&denied_progress.step);
    {
        const directory = b.addTempFiles();
        const packaged = directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
        const configured = std.mem.replaceOwned(u8, b.allocator, configuration, "\"slots\": {}", "\"slots\": {\"spec_generation\": {\"provider\":\"aws-bedrock\",\"model\":\"openai.gpt-oss-20b-1:0\"},\"repair\": {\"provider\":\"aws-bedrock\",\"model\":\"openai.gpt-oss-20b-1:0\"}}") catch @panic("allocate generation smoke config");
        _ = directory.add(".sddtoolkit.json", configured);
        _ = directory.add(".sddproviders.json", @embedFile("../../design/examples/.sddproviders.json"));
        _ = directory.addCopyFile(b.path("design/workflows/spec.workflow.yaml"), ".sddtoolkit/workflows/spec.workflow.yaml");
        inline for (.{ "reconciliation", "generation", "support", "links" }) |name| inline for (.{ "prompt.md", "schema.json" }) |extension| {
            _ = directory.addCopyFile(b.path("design/workflows/spec/" ++ name ++ "." ++ extension), ".sddtoolkit/workflows/spec/" ++ name ++ "." ++ extension);
        };
        inline for (.{ "support-loss.prompt.md", "generation.context.json", "entities.prompt.md", "records.prompt.md", "extraction-content.prompt.md", "extraction.context.json", "extraction-classifications.prompt.md", "extraction.composition.json", "extraction.schema.json", "reconciliation-summary.composition.json", "reconciliation-dispositions.prompt.md", "reconciliation-signals.prompt.md", "reconciliation-conflicts.prompt.md", "packet-guidance.json" }) |name| {
            _ = directory.addCopyFile(b.path("design/workflows/spec/" ++ name), ".sddtoolkit/workflows/spec/" ++ name);
        }
        _ = directory.addCopyFile(b.path("design/workflows/spec/protocol.prompt.md"), ".sddtoolkit/workflows/spec/protocol.prompt.md");
        _ = directory.addCopyFile(b.path("design/workflows/spec/repair.prompt.md"), ".sddtoolkit/workflows/spec/repair.prompt.md");
        _ = directory.add(".sddtoolkit/principles/toolchain.yaml", "schema: project-toolchain/v1\npresets: []\npolicies: [project.zig@1]\n");
        _ = directory.addCopyFile(b.path("test/e2e/wf-001-hello-world/reference/stories.md"), "references/Hello/stories.md");
        const check = std.Build.Step.Run.create(b, "load packaged generation YAML and resources without source assets or credentials");
        check.addFileArg(packaged);
        check.addArgs(&.{ "spec-generation", "--feature", "chosen", "--reference", "Hello" });
        check.setCwd(directory.getDirectory());
        check.clearEnvironment();
        // No live call: graph/resource compilation completes before the invalid
        // project toolchain rejects. Provider authorization is checked separately.
        check.expectExitCode(1);
        check.expectStdOutEqual("");
        check.expectStdErrEqual("InvalidToolchain\n");
        missing_config_command.step.dependOn(&check.step);
    }
    // A catalogue entry captured before ADR 0030 records no deadline and is
    // rejected before any request, like an invalid deployment.
    for ([_]enum { valid, invalid_region, missing_deadline }{ .valid, .invalid_region, .missing_deadline }) |variant| {
        const directory = b.addTempFiles();
        const packaged = directory.addCopyFile(executable.getEmittedBin(), executable.out_filename);
        const slots = std.mem.replaceOwned(u8, b.allocator, configuration, "\"slots\": {}", "\"slots\": {\"spec_generation\": {\"provider\":\"aws-bedrock\",\"model\":\"openai.gpt-oss-20b-1:0\"}}") catch @panic("allocate provider smoke config");
        const configured = std.mem.replaceOwned(u8, b.allocator, slots, "\"providers\": \".sddproviders.json\"", "\"providers\": \"config/.sddproviders.json\"") catch @panic("allocate configured provider path");
        _ = directory.add(".sddtoolkit.json", configured);
        // The fixture's model entry carries the provider-operation deadline the
        // fixture has always used; the catalogue, not the YAML, owns it (ADR 0030).
        const shipped_bytes = @embedFile("../../design/examples/.sddproviders.json");
        const provider_bytes = std.mem.replaceOwned(u8, b.allocator, shipped_bytes, "\"requestTimeoutMs\": 180000", "\"requestTimeoutMs\": 60000") catch @panic("allocate fixture deadline");
        if (std.mem.eql(u8, provider_bytes, shipped_bytes)) @panic("provider smoke catalogue lacks the fixture deadline");
        const catalogue = switch (variant) {
            .valid => provider_bytes,
            .invalid_region => std.mem.replaceOwned(u8, b.allocator, provider_bytes, "ap-southeast-2", "xx-invalid-1") catch @panic("allocate invalid deployment"),
            .missing_deadline => std.mem.replaceOwned(u8, b.allocator, provider_bytes, ",\n            \"requestTimeoutMs\": 60000", "") catch @panic("allocate pre-deadline catalogue"),
        };
        if (variant != .valid and std.mem.eql(u8, catalogue, provider_bytes)) @panic("provider smoke variant left the catalogue unchanged");
        _ = directory.add("config/.sddproviders.json", catalogue);
        _ = directory.add(".sddtoolkit/workflows/provider-request.workflow.yaml", @embedFile("fixtures/provider-request/provider-request.workflow.yaml"));
        _ = directory.add(".sddtoolkit/workflows/provider-request.prompt.md", @embedFile("fixtures/provider-request/provider-request.prompt.md"));
        _ = directory.add(".sddtoolkit/workflows/provider-request.input.txt", @embedFile("fixtures/provider-request/provider-request.input.txt"));
        _ = directory.add(".sddtoolkit/workflows/provider-request.schema.json", @embedFile("fixtures/provider-request/provider-request.schema.json"));
        const check = std.Build.Step.Run.create(b, "run packaged external Bedrock catalogue without credentials or network");
        check.addFileArg(packaged);
        check.addArg("provider-request");
        check.setCwd(directory.getDirectory());
        check.clearEnvironment();
        check.expectExitCode(1);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(if (variant == .valid) "failed\n" else "LLM_PROVIDER_REGISTRY_INVALID\n");
        missing_config_command.step.dependOn(&check.step);
    }
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
        check.expectStdErrEqual(if (case.rejected) "InvalidReferenceAccounting\n" else "");
        missing_config_command.step.dependOn(&check.step);
    }
    for ([_]struct { feature: []const u8, rejected: bool }{
        .{ .feature = "Selected/日本語", .rejected = false },
        .{ .feature = "Chosen/Café", .rejected = false },
        .{ .feature = "Orphan", .rejected = true },
    }) |case| {
        const check = std.Build.Step.Run.create(b, "run packaged read-only clarification preflight");
        check.addFileArg(packaged_executable);
        check.addArgs(&.{ "reference-preflight", "--feature", case.feature, "--reference", "Café/日本語" });
        check.setCwd(package_directory.getDirectory());
        check.clearEnvironment();
        check.expectExitCode(if (case.rejected) 1 else 0);
        check.expectStdOutEqual("");
        check.expectStdErrEqual(if (case.rejected) "InvalidClarificationInput\n" else "");
        missing_config_command.step.dependOn(&check.step);
    }
    for ([_][]const []const u8{
        &.{ "reference-preflight", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "../escape", "--reference", "Café/日本語" },
        &.{ "reference-preflight", "--feature", "_archive/child", "--reference", "Café/日本語" },
    }, 0..) |arguments, index| {
        const rejected = std.Build.Step.Run.create(b, "reject packaged invalid feature selection");
        rejected.addFileArg(packaged_executable);
        rejected.addArgs(arguments);
        rejected.setCwd(package_directory.getDirectory());
        rejected.clearEnvironment();
        rejected.expectExitCode(1);
        rejected.expectStdOutEqual("");
        rejected.expectStdErrEqual(if (index == 0) "InvalidSpecifyArguments\n" else "InvalidFeatureDirectory\n");
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
