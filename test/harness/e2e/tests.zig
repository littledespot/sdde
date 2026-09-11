const std = @import("std");
const c = @import("contracts.zig");
const fixture = @import("fixture.zig");
const oracle = @import("oracle.zig");
const run_directory = @import("run_directory.zig");
const artifacts = @import("../../../src/domain/workflow_artifact_registry.zig");
const expected = [_]c.Artifact{ .specification, .reference_context, .clarification_state, .workflow_state };
const selected: c.Case = .{
    .schema = "spec-e2e-case/v1",
    .id = "one-reference",
    .workflow_id = "spec-generation",
    .feature = "chosen",
    .reference = "first",
    .config = "config.json",
    .provider_script = "script.json",
    .expected_specification = "expected.md",
    .directories = &.{"empty"},
    .files = &.{.{ .source = "source.md", .destination = "references/first/source.md" }},
    .expected_artifacts = &expected,
};

test "E2E command selects exactly one case and rejects suite and live arguments" {
    const parse = @import("cli.zig").parse;
    try std.testing.expectEqualStrings("case.json", try parse(&.{ "--case", "case.json" }));
    for ([_][]const []const u8{ &.{}, &.{"case.json"}, &.{ "--case", "one.json", "--case", "two.json" }, &.{ "--case", "case.json", "--live" }, &.{ "--suite", "suite.json" }, &.{ "--case", "../case.json" }, &.{ "--case", "/case.json" } }) |arguments| {
        if (parse(arguments)) |_| return error.AcceptedInvalidE2EArguments else |err| switch (err) {
            error.InvalidArguments, error.InvalidEvaluationContract => {},
            else => return err,
        }
    }
}

test "E2E case is closed and cannot preseed arbitrary destination collisions" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const valid = try std.json.Stringify.valueAlloc(a, selected, .{});
    _ = try c.parse(a, valid);
    for ([_][2][]const u8{
        .{ "\"spec-e2e-case/v1\"", "\"spec-e2e-case/v2\"" },
        .{ "\"id\":", "\"unknown\":true,\"id\":" },
        .{ "\"id\":", "\"id\":\"duplicate\",\"id\":" },
        .{ "references/first/source.md", "../spec.md" },
        .{ "references/first/source.md", ".sddtoolkit.json" },
        .{ "source.md\",\"destination", "/source.md\",\"destination" },
        .{ "\"reference_context\"", "\"specification\"" },
    }) |change| {
        const invalid = try std.mem.replaceOwned(u8, a, valid, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, valid, invalid));
        if (c.parse(a, invalid)) |_| return error.AcceptedInvalidE2ECase else |err| switch (err) {
            error.InvalidE2ECase, error.InvalidEvaluationContract => {},
            else => return err,
        }
    }
    var collision = selected;
    collision.files = &.{
        .{ .source = "one.md", .destination = "refs/Source.md" },
        .{ .source = "two.md", .destination = "refs/source.md/child" },
    };
    try std.testing.expectError(error.InvalidE2ECase, c.parse(a, try std.json.Stringify.valueAlloc(a, collision, .{})));
}

test "one dated E2E directory retains one isolated project per invocation" {
    const io = std.testing.io;
    var parent = std.testing.tmpDir(.{});
    defer parent.cleanup();
    const first = try run_directory.Run.create(io, parent.dir);
    defer first.close(io);
    const second = try run_directory.Run.create(io, parent.dir);
    defer second.close(io);
    try std.testing.expect(!std.mem.eql(u8, &first.name, &second.name));
    try first.project.writeFile(io, .{ .sub_path = "spec.md", .data = "first" });
    try std.testing.expectError(error.FileNotFound, second.project.access(io, "spec.md", .{}));
    try std.testing.expectError(error.FileNotFound, first.dir.access(io, "case-00", .{}));
    const name = run_directory.directoryName("2026-09-10T09:08:07Z".*, @splat(0x11));
    try std.testing.expectEqualStrings("2026-09-10T09-08-07Z-11111111111111111111111111111111", &name);
    const concurrent = run_directory.directoryName("2026-09-10T09:08:07Z".*, @splat(0x22));
    try std.testing.expect(!std.mem.eql(u8, &name, &concurrent));
}

test "fixture copy preserves declared reference bytes and rejects preseeded output and aliases" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var repository = std.testing.tmpDir(.{});
    defer repository.cleanup();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    try repository.dir.writeFile(io, .{ .sub_path = "config.json", .data = "declared config" });
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "The library renews a loan.\n" });
    try repository.dir.writeFile(io, .{ .sub_path = "script.json", .data = @embedFile("fixtures/library-script.json") });
    try repository.dir.writeFile(io, .{ .sub_path = "expected.md", .data = @embedFile("fixtures/library-spec.md") });
    const captured = try fixture.capture(io, a, repository.dir, selected);
    try fixture.materialize(io, project.dir, captured);
    const copy = try project.dir.readFileAlloc(io, "references/first/source.md", a, .limited(1024));
    try std.testing.expectEqualStrings("The library renews a loan.\n", copy);
    try fixture.verifySources(io, a, repository.dir, captured);
    try fixture.validateOutputs(captured, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, a);
    var forged = captured;
    forged.files = &.{.{ .mapping = .{ .source = "source.md", .destination = "outputs/chosen/spec.md" }, .bytes = "stale" }};
    try std.testing.expectError(error.FixtureContainsWorkflowOutput, fixture.validateOutputs(forged, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, a));
    try repository.dir.writeFile(io, .{ .sub_path = "source.md", .data = "changed" });
    try std.testing.expectError(error.FixtureChanged, fixture.verifySources(io, a, repository.dir, captured));
    try repository.dir.symLink(io, "source.md", "alias.md", .{});
    var aliased = selected;
    aliased.files = &.{.{ .source = "alias.md", .destination = "references/first/source.md" }};
    try std.testing.expectError(error.InputUnavailable, fixture.capture(io, a, repository.dir, aliased));
}

fn resolve(a: std.mem.Allocator) !artifacts.FeaturePaths {
    const feature = try @import("../../../src/domain/feature_directory.zig").validate(a, .{ .bytes = "chosen" }, .{ .specs = "outputs", .archive = "archive" });
    return artifacts.resolveFeaturePaths(a, .{ .specs = "outputs", .archive = "archive", .workflows = "engine" }, feature);
}

test "E2E oracle requires actual publication and every expected file" {
    const io = std.testing.io;
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var project = std.testing.tmpDir(.{});
    defer project.cleanup();
    const paths = try resolve(a);
    try std.testing.expectEqual(.publication_missing, (try oracle.inspect(io, a, project.dir, .ok, .not_observed, &expected, paths)).status);
    try std.testing.expectEqual(.artifact_missing, (try oracle.inspect(io, a, project.dir, .ok, .confirmed, &expected, paths)).status);
    inline for (expected) |artifact| {
        const path = paths.get(@field(artifacts.Artifact, @tagName(artifact))).project_relative;
        try project.dir.createDirPath(io, std.fs.path.dirname(path).?);
        try project.dir.writeFile(io, .{ .sub_path = path, .data = "published bytes\n" });
    }
    try std.testing.expectEqual(.publication_missing, (try oracle.inspect(io, a, project.dir, .ok, .not_observed, &expected, paths)).status);
    const passed = try oracle.inspect(io, a, project.dir, .ok, .confirmed, &expected, paths);
    try std.testing.expectEqual(.passed, passed.status);
    try std.testing.expectEqualStrings("outputs/chosen/spec.md", passed.specification.?);
    for ([_]@import("../../../src/domain/workflow.zig").OutcomeTag{ .failed, .invalid, .blocked, .cancelled, .needs_user, .more }) |outcome| {
        const result = try oracle.inspect(io, a, project.dir, outcome, .confirmed, &expected, paths);
        try std.testing.expectEqual(.workflow_failed, result.status);
        try std.testing.expect(result.specification == null);
    }
    try project.dir.deleteFile(io, paths.get(.workflow_state).project_relative);
    const missing = try oracle.inspect(io, a, project.dir, .ok, .confirmed, &expected, paths);
    try std.testing.expectEqual(.artifact_missing, missing.status);
    try std.testing.expectEqual(.workflow_state, missing.missing_artifact.?);
    try std.testing.expect(missing.specification == null);
}

test "ordinary publication persists canonical evidence and reruns replace views with monotonic IDs" {
    const io = std.testing.io;
    const state = @import("../../../src/domain/specification_state.zig");
    for (0..2) |example| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const case_bytes = try std.Io.Dir.cwd().readFileAlloc(io, "test/e2e/wf-001-hello-world/node-vitest/workflow.case.json", a, .limited(1_048_576));
        var choice = try c.parse(a, case_bytes);
        if (example == 1) {
            choice.provider_script = "test/harness/e2e/fixtures/library-script.json";
            choice.expected_specification = "test/harness/e2e/fixtures/library-spec.md";
        }
        const captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        if (example == 1) {
            choice.workflow_id = "library-reference";
            choice.feature = "Loans/Café";
            const definition = try project.dir.readFileAlloc(io, ".sddtoolkit/workflows/spec.workflow.yaml", a, .limited(1_048_576));
            try project.dir.writeFile(io, .{ .sub_path = ".sddtoolkit/workflows/spec.workflow.yaml", .data = try std.mem.replaceOwned(u8, a, definition, "id: spec-generation\n", "id: library-reference\n") });
            try project.dir.writeFile(io, .{ .sub_path = "references/hello-world/stories.md", .data = captured.script.extractions[0].source });
            try project.dir.writeFile(io, .{ .sub_path = "references/hello-world/confirmation.md", .data = captured.script.extractions[1].source });
        }
        const specification_path = try std.fmt.allocPrint(a, "specs/{s}/spec.md", .{choice.feature});
        const reference_path = try std.fmt.allocPrint(a, "specs/{s}/reference-context.md", .{choice.feature});
        const state_path = try std.fmt.allocPrint(a, ".sddtoolkit/workflows/features/{s}/state/workflow.json", .{choice.feature});
        var previous: ?state.State = null;
        for (0..2) |run_index| {
            var report: c.Report = .{ .started_at_utc = "2026-09-10T00:00:00Z", .status = .harness_error };
            try @import("invoke.zig").run(io, a, project.dir, choice, captured, &report);
            if (report.status != .passed) std.debug.print("publication example {d}, run {d}: {any}\n", .{ example, run_index, report });
            try std.testing.expectEqual(.passed, report.status);
            try std.testing.expectEqual(.passed, report.publication_check);
            try std.testing.expectEqual(.matched, report.fixture_content_check);
            try std.testing.expectEqual(.not_evaluated, report.semantic_quality);
            try std.testing.expectEqualStrings(specification_path, report.specification.?);
            try std.testing.expect(report.model_calls > 0);
            const bytes = try project.dir.readFileAlloc(io, state_path, a, .limited(state.max_bytes));
            const parsed = (try state.parse(a, bytes, .{ .bytes = choice.feature })).state.?;
            try std.testing.expectEqual(run_index + 1, parsed.revision);
            try std.testing.expectEqual(.specified, parsed.stage);
            try std.testing.expect(parsed.review.evidence.len != 0);
            for (parsed.review.evidence) |evidence| try std.testing.expectEqual(.model_assisted, evidence.method);
            const spec_bytes = try project.dir.readFileAlloc(io, specification_path, a, .limited(8_388_608));
            _ = try @import("../../../src/domain/specification_markdown.zig").parse(a, spec_bytes);
            const reference_bytes = try project.dir.readFileAlloc(io, reference_path, a, .limited(8_388_608));
            try std.testing.expectEqualStrings(try @import("../../../src/domain/reference_context.zig").render(a, parsed.reference), reference_bytes);
            const exact = if (example == 0) "Hello, World!" else "Loan renewed!";
            try std.testing.expect(std.mem.indexOf(u8, reference_bytes, exact) != null);
            if (previous) |prior| {
                for (parsed.content.records) |record| try std.testing.expect(record.id.ordinal >= prior.id_ledger.next[@intFromEnum(record.id.kind)]);
                try std.testing.expect(std.mem.indexOf(u8, spec_bytes, "stale user edit") == null);
            }
            previous = parsed;
            if (run_index == 0) {
                try project.dir.writeFile(io, .{ .sub_path = specification_path, .data = "stale user edit\n" ** 100 });
                try project.dir.writeFile(io, .{ .sub_path = reference_path, .data = "stale sidecar\n" ** 100 });
            } else {
                const invalids = [_][]const u8{
                    try std.mem.concat(a, u8, &.{ "{\"unknown\":true,", bytes[1..] }),
                    try std.mem.replaceOwned(u8, a, bytes, "specification-state/v1", "specification-state/v2"),
                };
                for (invalids) |invalid| try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, invalid, .{ .bytes = choice.feature }));
                try std.testing.expectError(error.InvalidSpecificationState, state.parse(a, bytes, .{ .bytes = "foreign-feature" }));
                var bad = parsed;
                for (@import("../../../src/domain/specification.zig").required_record_families) |kind| {
                    var retained: std.ArrayList(@import("../../../src/domain/specification.zig").IdentifiedRecord) = .empty;
                    for (parsed.content.records) |record| if (record.proposal.content != kind) try retained.append(a, record);
                    bad = parsed;
                    bad.content.records = retained.items;
                    try std.testing.expectError(error.InvalidSpecificationState, state.validate(a, bad, parsed.feature));
                }
                bad = parsed;
                bad.id_ledger.next = @splat(1);
                try std.testing.expectError(error.InvalidSpecificationState, state.validate(a, bad, parsed.feature));
                bad = parsed;
                const citations = try a.dupe(@import("../../../src/domain/reference_extraction.zig").Citation, bad.reference.extraction.citations);
                citations[0].value.source_id.ordinal = 999;
                bad.reference.extraction.citations = citations;
                try std.testing.expectError(error.InvalidSpecificationState, state.validate(a, bad, parsed.feature));
                // Invalid persisted input rejects before another model call and
                // never gets reset to a fresh successful state.
                try project.dir.writeFile(io, .{ .sub_path = state_path, .data = invalids[0] });
                report = .{ .started_at_utc = "2026-09-10T00:00:00Z", .status = .harness_error };
                try @import("invoke.zig").run(io, a, project.dir, choice, captured, &report);
                try std.testing.expectEqual(.workflow_failed, report.status);
                try std.testing.expectEqual(@as(usize, 0), report.model_calls);
                try std.testing.expectEqualStrings(spec_bytes, try project.dir.readFileAlloc(io, specification_path, a, .limited(8_388_608)));
            }
        }
        try fixture.verifySources(io, a, .cwd(), captured);
    }
}

test "fixture content comparison rejects omissions changed meaning and noncanonical output" {
    const content = @import("content.zig");
    const codec = @import("../../../src/domain/specification_markdown.zig");
    const spec = @import("../../../src/domain/specification.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for ([_][]const u8{ @embedFile("fixtures/library-spec.md"), @embedFile("../../e2e/wf-001-hello-world/node-vitest/expected-spec.md") }) |expected_bytes| {
        const expected_document = try codec.parse(a, expected_bytes);
        const canonical = try codec.render(a, expected_document);
        try std.testing.expect(try content.matches(a, expected_bytes, canonical));
        for (spec.required_record_families) |kind| {
            var retained: std.ArrayList(spec.CapturedRecord) = .empty;
            for (expected_document.records) |record| if (record.content != kind) try retained.append(a, record);
            var changed = expected_document;
            changed.records = retained.items;
            try std.testing.expect(!try content.matches(a, expected_bytes, try codec.render(a, changed)));
        }
        var changed = expected_document;
        changed.primary_user_story.bytes = "An unrelated activity occurs.";
        try std.testing.expect(!try content.matches(a, expected_bytes, try codec.render(a, changed)));
        try std.testing.expect(!try content.matches(a, expected_bytes, try std.mem.concat(a, u8, &.{ canonical, "\n" })));
        try std.testing.expect(!try content.matches(a, expected_bytes, "arbitrary published bytes"));
        try std.testing.expect(!try content.matches(a, expected_bytes, try std.mem.replaceOwned(u8, a, canonical, "AC-001", "AC")));
    }
}

test "scripted success cannot override changed source or independent expected content" {
    const io = std.testing.io;
    for ([_]enum { source, expected }{ .source, .expected }) |mutation| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const a = arena.allocator();
        const bytes = try std.Io.Dir.cwd().readFileAlloc(io, "test/e2e/wf-001-hello-world/node-vitest/workflow.case.json", a, .limited(1_048_576));
        const choice = try c.parse(a, bytes);
        var captured = try fixture.capture(io, a, .cwd(), choice);
        var project = std.testing.tmpDir(.{});
        defer project.cleanup();
        try fixture.materialize(io, project.dir, captured);
        switch (mutation) {
            .source => captured.script.extractions = &.{.{ .source = "A different source.\n", .claim = "A different behavior." }},
            .expected => captured.expected_bytes = try std.mem.replaceOwned(u8, a, captured.expected_bytes, "Hello, World!", "An unsupported greeting!"),
        }
        var report: c.Report = .{ .started_at_utc = "2026-09-11T00:00:00Z", .status = .harness_error };
        try @import("invoke.zig").run(io, a, project.dir, choice, captured, &report);
        switch (mutation) {
            .source => {
                try std.testing.expectEqual(.workflow_failed, report.status);
                try std.testing.expectEqual(.failed, report.publication_check);
                try std.testing.expectEqual(.not_run, report.fixture_content_check);
                try std.testing.expect(report.specification == null);
                try std.testing.expectError(error.FileNotFound, project.dir.access(io, "specs/hello-world/spec.md", .{}));
            },
            .expected => {
                try std.testing.expectEqual(.content_mismatch, report.status);
                try std.testing.expectEqual(.passed, report.publication_check);
                try std.testing.expectEqual(.mismatched, report.fixture_content_check);
                try std.testing.expectEqual(.ok, report.workflow_outcome.?);
                try std.testing.expect(report.specification != null);
            },
        }
        try std.testing.expectEqual(.not_evaluated, report.semantic_quality);
    }
}

test "authored provider scripts reject unknown fields versions and supplied identities" {
    const script = @import("../../../src/test_fixtures/specification_script.zig");
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bytes = @embedFile("fixtures/library-script.json");
    _ = try script.parse(a, bytes);
    var duplicate = try script.parse(a, bytes);
    duplicate.extractions = &.{ duplicate.extractions[0], duplicate.extractions[0] };
    try std.testing.expectError(error.InvalidSpecificationScript, script.parse(a, try std.json.Stringify.valueAlloc(a, duplicate, .{})));
    for ([_][2][]const u8{
        .{ "specification-script/v1", "specification-script/v2" },
        .{ "\"schema\":", "\"unknown\":true,\"schema\":" },
        .{ "\"schema\":", "\"schema\":\"duplicate\",\"schema\":" },
        .{ "\"id\": null", "\"id\": {\"kind\":\"acceptance_criterion\",\"ordinal\":1}" },
    }) |mutation| {
        if (script.parse(a, try std.mem.replaceOwned(u8, a, bytes, mutation[0], mutation[1]))) |_| return error.AcceptedInvalidProviderScript else |err| switch (err) {
            error.InvalidSpecificationScript, error.InvalidJsonDocument, error.InvalidSpecification => {},
            else => return err,
        }
    }
}
