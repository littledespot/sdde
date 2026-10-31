const std = @import("std");
const schema = @import("domain/model_result_schema.zig");
const parser = @import("adapters/parsers/model_result_schemas.zig");
const compilation = @import("domain/workflow_compilation.zig");

test {
    _ = @import("json_composition_test.zig");
    _ = @import("json_composition_runtime_test.zig");
}

const replacement =
    \\{"type":"object","properties":{"replacement":{"type":"string","maxLength":256}},"required":["replacement"],"additionalProperties":false}
;
const variants =
    \\{"oneOf":[
    \\{"type":"object","properties":{"kind":{"const":"content"},"answer":{"type":"string","minLength":1,"maxLength":64}},"required":["kind","answer"],"additionalProperties":false},
    \\{"type":"object","properties":{"kind":{"const":"clarification_needed"},"question":{"type":"string","maxLength":128}},"required":["kind","question"],"additionalProperties":false}]}
;

const selectionChoices =
    \\{"$defs":{"review":{"type":"object","properties":{"source_ids":{"type":"array","maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2048}},"claim_id":{"type":"integer","minimum":1,"maximum":2048}},"required":["source_ids","claim_id"],"additionalProperties":false},"selection":{"type":"object","properties":{"source_ids":{"type":"array","maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2048}}},"required":["source_ids"],"additionalProperties":false},"nested":{"type":"object","properties":{"records":{"type":"array","maxItems":3,"items":{"type":"object","properties":{"handles":{"type":"array","minItems":1,"maxItems":2,"items":{"type":"integer","minimum":1,"maximum":2048}}},"required":["handles"],"additionalProperties":false}}},"required":["records"],"additionalProperties":false}},"$ref":"#/$defs/review"}
;

fn expectSelection(a: std.mem.Allocator, selected: *const schema.Schema, bytes: []const u8, accepted: bool) !void {
    const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
    const check = @import("domain/model_payload_schema.zig");
    try std.testing.expectEqual(accepted, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), selected.root()) == null);
    // The exact schema sent to the provider admits the same candidate locally.
    const wire = try compile(a, selected.modelBytes());
    try std.testing.expectEqual(accepted, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), wire.root()) == null);
}

test "untagged ID collections and scalar choices bind distinct namespaces and preserve bounds" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = (try compile(a, selectionChoices)).select(.{ .bytes = "review" }).?;
    const choices: []const schema.IntegerChoice = &.{
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "review" }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "claim_id" }} }, .definition = .{ .bytes = "review" }, .allowed = &.{4} },
    };
    const narrowed = try schema.restrict(std.testing.allocator, original, &.{}, choices);
    defer narrowed.release();
    try expectSelection(a, narrowed.selected(), "{\"source_ids\":[1],\"claim_id\":4}", true);
    try expectSelection(a, narrowed.selected(), "{\"source_ids\":[],\"claim_id\":4}", true);
    for ([_][]const u8{ "{\"source_ids\":[4],\"claim_id\":4}", "{\"source_ids\":[1],\"claim_id\":1}", "{\"source_ids\":[1,1,1],\"claim_id\":4}" }) |bad| try expectSelection(a, narrowed.selected(), bad, false);
    try expectSelection(a, original, "{\"source_ids\":[4],\"claim_id\":1}", true);
    const only_source = try schema.restrict(std.testing.allocator, original, &.{}, choices[0..1]);
    defer only_source.release();
    try expectSelection(a, only_source.selected(), "{\"source_ids\":[1],\"claim_id\":999}", true);
}

test "integer collection choices preserve required minima and empty optional parent semantics" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try compile(a, selectionChoices);
    const optional = try schema.restrict(std.testing.allocator, original.select(.{ .bytes = "selection" }).?, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = &.{} }});
    defer optional.release();
    try expectSelection(a, optional.selected(), "{\"source_ids\":[]}", true);
    try expectSelection(a, optional.selected(), "{\"source_ids\":[1]}", false);
    const nested = original.select(.{ .bytes = "nested" }).?;
    const path: []const schema.ChoiceStep = &.{ .{ .property = "records" }, .{ .items = {} }, .{ .property = "handles" } };
    const populated = try schema.restrict(std.testing.allocator, nested, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 2, 7 } }});
    defer populated.release();
    try expectSelection(a, populated.selected(), "{\"records\":[{\"handles\":[2,7]}]}", true);
    try expectSelection(a, populated.selected(), "{\"records\":[{\"handles\":[]}]}", false);
    try expectSelection(a, populated.selected(), "{\"records\":[{\"handles\":[4]}]}", false);
    const empty = try schema.restrict(std.testing.allocator, nested, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{} }});
    defer empty.release();
    try expectSelection(a, empty.selected(), "{\"records\":[]}", true);
    try expectSelection(a, empty.selected(), "{\"records\":[{\"handles\":[2]}]}", false);
    const required = try schema.project(a, nested, schema.findProperty(nested.root().object, "records").?.schema.array.items);
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, required, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "handles" }} }, .allowed = &.{} }}));
}

test "native unique subsets derive collection cardinality without restricting overlapping groups" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resource = try compile(a, selectionChoices);
    const nested = resource.select(.{ .bytes = "nested" }).?;
    const path: []const schema.ChoiceStep = &.{ .{ .property = "records" }, .{ .items = {} }, .{ .property = "handles" } };
    const one: schema.IntegerChoice = .{ .target = .{ .path = path }, .allowed = &.{7}, .collection = .unique_subset };
    const selected = try schema.restrict(std.testing.allocator, nested, &.{}, &.{one});
    defer selected.release();
    try expectSelection(a, selected.selected(), "{\"records\":[{\"handles\":[7]},{\"handles\":[7]}]}", true);
    try expectSelection(a, selected.selected(), "{\"records\":[{\"handles\":[7,7]}]}", false);
    try expectSelection(a, selected.selected(), "{\"records\":[{\"handles\":[]}]}", false);
    try expectSelection(a, selected.selected(), "{\"records\":[{\"handles\":[2]}]}", false);
    const handles = schema.findProperty(schema.findProperty(selected.selected().root().object, "records").?.schema.array.items.object, "handles").?.schema;
    try std.testing.expectEqual(@as(u32, 1), handles.array.maximum);
    // Uniqueness is an existing native-owner obligation. The closed schema
    // profile does not claim to enforce duplicates within the derived bound.
    const two = try schema.restrict(std.testing.allocator, nested, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 2, 7 }, .collection = .unique_subset }});
    defer two.release();
    try expectSelection(a, two.selected(), "{\"records\":[{\"handles\":[2,7]},{\"handles\":[7]}]}", true);
    try expectSelection(a, two.selected(), "{\"records\":[{\"handles\":[2,2]}]}", true);
    try std.testing.expect(std.mem.indexOf(u8, two.selected().modelBytes(), "uniqueItems") == null);
    const larger = try schema.restrict(std.testing.allocator, nested, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 2, 7, 9 }, .collection = .unique_subset }});
    defer larger.release();
    try expectSelection(a, larger.selected(), "{\"records\":[{\"handles\":[2,7,9]}]}", false);
    // Opt-in subset facts never alter another owner's sequence semantics.
    var sequence = one;
    sequence.collection = .sequence;
    const repeated = try schema.restrict(std.testing.allocator, nested, &.{}, &.{sequence});
    defer repeated.release();
    try expectSelection(a, repeated.selected(), "{\"records\":[{\"handles\":[7,7]}]}", true);
    var none = one;
    none.allowed = &.{};
    const empty = try schema.restrict(std.testing.allocator, nested, &.{}, &.{none});
    defer empty.release();
    try expectSelection(a, empty.selected(), "{\"records\":[]}", true);
    try expectSelection(a, empty.selected(), "{\"records\":[{\"handles\":[7]}]}", false);
    const optional = resource.select(.{ .bytes = "selection" }).?;
    const optional_empty = try schema.restrict(std.testing.allocator, optional, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = &.{}, .collection = .unique_subset }});
    defer optional_empty.release();
    try expectSelection(a, optional_empty.selected(), "{\"source_ids\":[]}", true);
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, resource, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "claim_id" }} }, .allowed = &.{7}, .collection = .unique_subset }}));
    const required = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":2,\"maxItems\":4,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}}"));
    for ([_][]const i64{ &.{}, &.{7} }) |ids| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, required, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = ids, .collection = .unique_subset }}));
}

test "exact members admit one item per allowed key and reject partial repeated or foreign assignments" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const check = @import("domain/model_payload_schema.zig");
    const resource = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10},\"note\":{\"type\":\"string\",\"maxLength\":20}},\"required\":[\"ordinal\",\"note\"],\"additionalProperties\":false}}"));
    const path: []const schema.ChoiceStep = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "ordinal" } };
    const exact = try schema.restrict(std.testing.allocator, resource, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .collection = .exact_members }});
    defer exact.release();
    // Any order of the complete member set is admitted, by native and wire schemas alike.
    try expectSelection(a, exact.selected(), "{\"value\":[{\"ordinal\":5,\"note\":\"b\"},{\"ordinal\":3,\"note\":\"a\"}]}", true);
    // Count and foreign members are visible to the provider schema too.
    try expectSelection(a, exact.selected(), "{\"value\":[{\"ordinal\":3,\"note\":\"a\"}]}", false);
    try expectSelection(a, exact.selected(), "{\"value\":[]}", false);
    try expectSelection(a, exact.selected(), "{\"value\":[{\"ordinal\":3,\"note\":\"a\"},{\"ordinal\":5,\"note\":\"b\"},{\"ordinal\":5,\"note\":\"c\"}]}", false);
    try expectSelection(a, exact.selected(), "{\"value\":[{\"ordinal\":3,\"note\":\"a\"},{\"ordinal\":4,\"note\":\"b\"}]}", false);
    const Reason = check.Rejection;
    for ([_]struct { bytes: []const u8, reason: Reason }{
        .{ .bytes = "{\"value\":[{\"ordinal\":3,\"note\":\"a\"}]}", .reason = .array_length },
        .{ .bytes = "{\"value\":[{\"ordinal\":3,\"note\":\"a\"},{\"ordinal\":4,\"note\":\"b\"}]}", .reason = .enum_mismatch },
        .{ .bytes = "{\"value\":[{\"ordinal\":3,\"note\":\"a\"},{\"ordinal\":3,\"note\":\"b\"}]}", .reason = .duplicate_member },
    }) |case| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, case.bytes, .{ .parse_numbers = false });
        try std.testing.expectEqual(case.reason, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), exact.selected().root()).?.reason);
    }
    // Uniqueness is native: the provider schema sees only the exact item count.
    const repeated = try std.json.parseFromSlice(std.json.Value, a, "{\"value\":[{\"ordinal\":3,\"note\":\"a\"},{\"ordinal\":3,\"note\":\"b\"}]}", .{ .parse_numbers = false });
    const wire = try compile(a, exact.selected().modelBytes());
    try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&repeated.value), wire.root()) == null);
    const array = schema.findProperty(exact.selected().root().object, "value").?.schema.array;
    try std.testing.expectEqual(@as(u32, 2), array.minimum);
    try std.testing.expectEqual(@as(u32, 2), array.maximum);
    try std.testing.expectEqualStrings("ordinal", array.members.?.property);
    try std.testing.expectEqualSlices(i64, &.{ 3, 5 }, array.members.?.values);
    try std.testing.expect(std.mem.indexOf(u8, exact.selected().modelBytes(), "uniqueItems") == null);
    // The selector must name an integer property of array items, with members.
    for ([_]schema.IntegerChoice{
        .{ .target = .{ .path = path }, .allowed = &.{}, .collection = .exact_members },
        .{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{3}, .collection = .exact_members },
        .{ .target = .{ .tagged = .{ .kind = "value", .field = "ordinal" } }, .allowed = &.{3}, .collection = .exact_members },
        .{ .target = .{ .path = path }, .allowed = &.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11 }, .collection = .exact_members },
    }) |invalid| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, resource, &.{}, &.{invalid}));
}

test "exact members require a required scalar key in the validated schema" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path: []const schema.ChoiceStep = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "ordinal" } };
    const members: []const schema.IntegerChoice = &.{.{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .collection = .exact_members }};
    // A nullable, optional or collection-valued key cannot identify one member per item.
    for ([_][]const u8{
        "{\"oneOf\":[{\"type\":\"null\"},{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}]}",
        "{\"type\":\"array\",\"maxItems\":3,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}}",
    }) |key| {
        const items = try std.mem.concat(a, u8, &.{ "{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":", key, "},\"required\":[\"ordinal\"],\"additionalProperties\":false}}" });
        try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, try compile(a, try fieldSchema(a, items)), &.{}, members));
    }
    const optional = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[],\"additionalProperties\":false}}"));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, optional, &.{}, members));
    // A member count outside the canonical item bounds is not a narrowing.
    const bounded = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":3,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[\"ordinal\"],\"additionalProperties\":false}}"));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, bounded, &.{}, members));
    // Membership must constrain the selected schema itself: a projection-only
    // or other-definition match would leave admission unconstrained.
    const tagged = try compile(a,
        \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"keep"},"value":{"type":"array","minItems":1,"maxItems":10,"items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":1,"maximum":10}},"required":["ordinal"],"additionalProperties":false}}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"drop"}},"required":["kind"],"additionalProperties":false}]}
    );
    const dropped = try schema.project(a, tagged, tagged.root().one_of[1]);
    const sequence = try schema.restrict(std.testing.allocator, dropped, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 3, 5 } }});
    sequence.release();
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, dropped, &.{}, members));
    const review = (try compile(a, selectionChoices)).select(.{ .bytes = "review" }).?;
    const nested: []const schema.ChoiceStep = &.{ .{ .property = "records" }, .{ .items = {} }, .{ .property = "handles" } };
    const foreign = try schema.restrict(std.testing.allocator, review, &.{}, &.{.{ .target = .{ .path = nested }, .definition = .{ .bytes = "nested" }, .allowed = &.{1} }});
    foreign.release();
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, review, &.{}, &.{.{ .target = .{ .path = nested }, .definition = .{ .bytes = "nested" }, .allowed = &.{1}, .collection = .exact_members }}));
    // Every root alternative carrying the selector must be constrained; an
    // alternative where the key does not match would escape membership.
    const alternatives = try compile(a,
        \\{"oneOf":[{"type":"object","properties":{"kind":{"const":"keep"},"value":{"type":"array","minItems":1,"maxItems":10,"items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":1,"maximum":10}},"required":["ordinal"],"additionalProperties":false}}},"required":["kind","value"],"additionalProperties":false},{"type":"object","properties":{"kind":{"const":"other"},"value":{"type":"array","maxItems":10,"items":{"type":"integer","minimum":1,"maximum":10}}},"required":["kind","value"],"additionalProperties":false}]}
    );
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, alternatives, &.{}, members));
    const kept = try schema.project(a, alternatives, alternatives.root().one_of[0]);
    const exact = try schema.restrict(std.testing.allocator, kept, &.{}, members);
    exact.release();
    // A second choice on an exact-members key would leave no admissible
    // response, whether it names the selected definition explicitly or not.
    const definitions = try compile(a,
        \\{"$defs":{"assignment":{"type":"object","properties":{"value":{"type":"array","minItems":1,"maxItems":10,"items":{"type":"object","properties":{"ordinal":{"type":"integer","minimum":1,"maximum":10}},"required":["ordinal"],"additionalProperties":false}}},"required":["value"],"additionalProperties":false}},"$ref":"#/$defs/assignment"}
    );
    const assignment = definitions.select(.{ .bytes = "assignment" }).?;
    const named: schema.DefinitionId = .{ .bytes = "assignment" };
    for ([_][2]schema.IntegerChoice{
        .{ .{ .target = .{ .path = path }, .definition = named, .allowed = &.{ 3, 5 }, .collection = .exact_members }, .{ .target = .{ .path = path }, .allowed = &.{3} } },
        .{ .{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .collection = .exact_members }, .{ .target = .{ .path = path }, .definition = named, .allowed = &.{3} } },
    }) |stacked| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, assignment, &.{}, &stacked));
    const single = try schema.restrict(std.testing.allocator, assignment, &.{}, &.{.{ .target = .{ .path = path }, .definition = named, .allowed = &.{ 3, 5 }, .collection = .exact_members }});
    single.release();
    // An optional member array could be omitted, and an outer array would repeat or
    // omit the set; neither is one complete assignment.
    const optional_array = try compile(a, "{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[\"ordinal\"],\"additionalProperties\":false}}},\"required\":[],\"additionalProperties\":false}");
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, optional_array, &.{}, members));
    const grouped = try compile(a, "{\"type\":\"object\",\"properties\":{\"groups\":{\"type\":\"array\",\"maxItems\":4,\"items\":{\"type\":\"object\",\"properties\":{\"value\":{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[\"ordinal\"],\"additionalProperties\":false}}},\"required\":[\"value\"],\"additionalProperties\":false}}},\"required\":[\"groups\"],\"additionalProperties\":false}");
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, grouped, &.{}, &.{.{ .target = .{ .path = &.{ .{ .property = "groups" }, .items, .{ .property = "value" }, .items, .{ .property = "ordinal" } } }, .allowed = &.{ 3, 5 }, .collection = .exact_members }}));
    // A tagged choice on the same key, in either order, leaves no admissible set.
    const tagged_items = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"keep\"},\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[\"kind\",\"ordinal\"],\"additionalProperties\":false}}"));
    const tagged_key: schema.IntegerChoice = .{ .target = .{ .tagged = .{ .kind = "keep", .field = "ordinal" } }, .allowed = &.{3} };
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, tagged_items, &.{}, &.{ members[0], tagged_key }));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, tagged_items, &.{}, &.{ tagged_key, members[0] }));
    const tagged_exact = try schema.restrict(std.testing.allocator, tagged_items, &.{}, members);
    tagged_exact.release();
    // Normalization is narrow: the same path under another carried definition is
    // a different target and remains admitted beside the selected one.
    const carried = try schema.restrict(std.testing.allocator, review, &.{}, &.{
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "selection" }, .allowed = &.{2} },
    });
    carried.release();
}

test "recorded exact members reconstruct native admission from provider schema bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const check = @import("domain/model_payload_schema.zig");
    const resource = try compile(a, try fieldSchema(a, "{\"type\":\"array\",\"minItems\":1,\"maxItems\":10,\"items\":{\"type\":\"object\",\"properties\":{\"ordinal\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}},\"required\":[\"ordinal\"],\"additionalProperties\":false}}"));
    const path: []const schema.ChoiceStep = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "ordinal" } };
    const exact = try schema.restrict(std.testing.allocator, resource, &.{}, &.{
        .{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .collection = .exact_members },
    });
    defer exact.release();
    try std.testing.expectEqual(@as(usize, 0), resource.memberChoices().len);
    try std.testing.expectEqual(@as(usize, 1), exact.selected().memberChoices().len);
    try std.testing.expectEqualSlices(i64, &.{ 3, 5 }, exact.selected().memberChoices()[0].allowed);
    try std.testing.expectEqualStrings("ordinal", exact.selected().memberChoices()[0].path[2].property);
    // Clones keep both the native node restriction and its record.
    const cloned = try exact.selected().clone(a);
    try std.testing.expectEqualDeep(exact.selected().memberChoices(), cloned.memberChoices());
    try std.testing.expect(schema.findProperty(cloned.root().object, "value").?.schema.array.members != null);
    // Replay compiles provider bytes, which cannot express membership, then
    // reapplies the record to recover admission's exact validation schema.
    const repeated = try std.json.parseFromSlice(std.json.Value, a, "{\"value\":[{\"ordinal\":3},{\"ordinal\":3}]}", .{ .parse_numbers = false });
    const wire = try compile(a, exact.selected().modelBytes());
    try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&repeated.value), wire.root()) == null);
    const restored = try schema.restrictRecorded(std.testing.allocator, wire, exact.selected().memberChoices(), &.{}, &.{});
    defer restored.release();
    try std.testing.expectEqual(check.Rejection.duplicate_member, check.validateValue(@import("domain/model_envelope.zig").value(&repeated.value), restored.selected().root()).?.reason);
    try expectSelection(a, restored.selected(), "{\"value\":[{\"ordinal\":5},{\"ordinal\":3}]}", true);
    // A record that does not fit the captured schema is rejected, not ignored.
    for ([_]schema.MemberChoice{
        .{ .path = path, .allowed = &.{ 3, 5, 7 } },
        .{ .path = path, .allowed = &.{ 3, 9 } },
        .{ .path = &.{ .{ .property = "other" }, .{ .items = {} }, .{ .property = "ordinal" } }, .allowed = &.{ 3, 5 } },
    }) |invalid| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrictRecorded(std.testing.allocator, wire, &.{invalid}, &.{}, &.{}));
    // ADR 0046: a native-count set leaves the canonical bounds in the wire bytes;
    // replay restores admission's membership over those bounds, unchanged.
    const native = try schema.restrict(std.testing.allocator, resource, &.{}, &.{
        .{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .collection = .exact_members, .member_count = .native },
    });
    defer native.release();
    const open_wire = try compile(a, native.selected().modelBytes());
    try std.testing.expectEqual(@as(u32, 10), schema.findProperty(open_wire.root().object, "value").?.schema.array.maximum);
    const reopened = try schema.restrictRecorded(std.testing.allocator, open_wire, native.selected().memberChoices(), &.{}, &.{});
    defer reopened.release();
    try std.testing.expectEqualStrings(native.selected().modelBytes(), reopened.selected().modelBytes());
    for ([_]struct { bytes: []const u8, reason: ?check.Rejection }{
        .{ .bytes = "{\"value\":[{\"ordinal\":3}]}", .reason = .missing_member },
        .{ .bytes = "{\"value\":[{\"ordinal\":3},{\"ordinal\":3}]}", .reason = .duplicate_member },
        .{ .bytes = "{\"value\":[{\"ordinal\":5},{\"ordinal\":3}]}", .reason = null },
    }) |case| {
        const answer = try std.json.parseFromSlice(std.json.Value, a, case.bytes, .{ .parse_numbers = false });
        const live = check.validateValue(@import("domain/model_envelope.zig").value(&answer.value), native.selected().root());
        const replayed = check.validateValue(@import("domain/model_envelope.zig").value(&answer.value), reopened.selected().root());
        if (case.reason) |reason| {
            try std.testing.expectEqual(reason, live.?.reason);
            try std.testing.expectEqual(reason, replayed.?.reason);
            try std.testing.expectEqual(live.?.member, replayed.?.member);
        } else try std.testing.expect(live == null and replayed == null);
    }
}

test "nullable terminal integer choices preserve absence and narrow only authorized values" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const ids = "{\"oneOf\":[{\"type\":\"null\"},{\"type\":\"array\",\"maxItems\":3,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}}]}";
    const original = try compile(a, try fieldSchema(a, ids));
    const narrowed = try schema.restrict(std.testing.allocator, original, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{ 3, 8 }, .collection = .unique_subset }});
    defer narrowed.release();
    for ([_][]const u8{ "{\"value\":null}", "{\"value\":[]}", "{\"value\":[3,8]}" }) |good| try expectSelection(a, narrowed.selected(), good, true);
    for ([_][]const u8{ "{\"value\":[1]}", "{\"value\":[3,8,3]}", "{\"value\":{\"kind\":\"unknown\"}}", "{\"value\":null,\"extra\":3}" }) |bad| try expectSelection(a, narrowed.selected(), bad, false);
    try expectSelection(a, original, "{\"value\":[1]}", true);
    const empty = try schema.restrict(std.testing.allocator, original, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{} }});
    defer empty.release();
    try expectSelection(a, empty.selected(), "{\"value\":null}", true);
    try expectSelection(a, empty.selected(), "{\"value\":[]}", true);
    try expectSelection(a, empty.selected(), "{\"value\":[3]}", false);
    const scalar = try compile(a, try fieldSchema(a, "{\"oneOf\":[{\"const\":null},{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}]}"));
    const selected_scalar = try schema.restrict(std.testing.allocator, scalar, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{8} }});
    defer selected_scalar.release();
    try expectSelection(a, selected_scalar.selected(), "{\"value\":null}", true);
    try expectSelection(a, selected_scalar.selected(), "{\"value\":8}", true);
    try expectSelection(a, selected_scalar.selected(), "{\"value\":3}", false);
    // Null is never a substitute for a missing or nonnumeric selector target.
    for ([_][]const u8{ "{\"type\":\"null\"}", "{\"oneOf\":[{\"type\":\"null\"},{\"type\":\"string\",\"maxLength\":8}]}" }) |wrong| {
        const closed = try compile(a, try fieldSchema(a, wrong));
        try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, closed, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{8} }}));
    }

    // The source-finding correction has two independent source selections;
    // its nullable gap selection uses this same generic terminal projection.
    const support = try compile(a, try std.Io.Dir.cwd().readFileAlloc(std.testing.io, "design/workflows/spec/support.schema.json", a, .unlimited));
    const invalid_selection = support.select(.{ .bytes = "invalid_selection" }).?;
    const repaired = try schema.restrict(std.testing.allocator, invalid_selection, &.{}, &.{
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "invalid_selection" }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "authority_gap_source_ids" }} }, .definition = .{ .bytes = "invalid_selection" }, .allowed = &.{2} },
    });
    defer repaired.release();
    for ([_][]const u8{ "{\"source_ids\":[1],\"authority_gap_source_ids\":null}", "{\"source_ids\":[1],\"authority_gap_source_ids\":[]}", "{\"source_ids\":[1],\"authority_gap_source_ids\":[2]}" }) |good| try expectSelection(a, repaired.selected(), good, true);
    for ([_][]const u8{ "{\"source_ids\":[2],\"authority_gap_source_ids\":[2]}", "{\"source_ids\":[1],\"authority_gap_source_ids\":[1]}", "{\"source_ids\":[],\"authority_gap_source_ids\":null}", "{\"source_ids\":[1],\"authority_gap_source_ids\":[999]}", "{\"source_ids\":[1],\"authority_gap_source_ids\":null,\"kind\":\"supported\"}" }) |bad| try expectSelection(a, repaired.selected(), bad, false);
}

test "unique collection metadata survives packet projections and tagged selection" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(uniqueCollectionPacket, .{});
}

fn uniqueCollectionPacket(allocator: std.mem.Allocator) !void {
    const packets = @import("domain/model_input_packet.zig");
    const base = try packets.create(allocator, "{}", .workflow_step, .initial_generation, null);
    defer packets.release(base);
    const selected = try packets.withIntegerChoices(allocator, base, &.{.{ .target = .{ .tagged = .{ .kind = "selection", .field = "handles" } }, .allowed = &.{ 3, 8 }, .collection = .unique_subset }});
    defer packets.release(selected);
    const contextual = try packets.withContext(struct { description: []const u8 }, allocator, selected, "assignment", .{ .description = "MOCK native selection" });
    defer packets.release(contextual);
    try std.testing.expectEqualDeep(selected.integerChoices(), contextual.integerChoices());
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resource = try compile(a,
        \\{"type":"object","properties":{"value":{"type":"object","properties":{"kind":{"const":"selection"},"handles":{"type":"array","minItems":1,"maxItems":8,"items":{"type":"integer","minimum":1,"maximum":10}}},"required":["kind","handles"],"additionalProperties":false}},"required":["value"],"additionalProperties":false}
    );
    const narrowed = try schema.restrict(allocator, resource, contextual.excludedVariants(), contextual.integerChoices());
    defer narrowed.release();
    try expectSelection(a, narrowed.selected(), "{\"value\":{\"kind\":\"selection\",\"handles\":[3,8]}}", true);
    try expectSelection(a, narrowed.selected(), "{\"value\":{\"kind\":\"selection\",\"handles\":[3,8,3]}}", false);
}

test "ID restrictions validate definition and selected part association before omitting sibling locations" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(selectedIdChoices, .{});
}

fn selectedIdChoices(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resource = try compile(a, selectionChoices);
    const initial = resource.select(.{ .bytes = "review" }).?;
    const choices: []const schema.IntegerChoice = &.{
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "review" }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "selection" }, .allowed = &.{2} },
    };
    const selected = try schema.restrict(allocator, initial, &.{}, choices);
    defer selected.release();
    try expectSelection(a, selected.selected(), "{\"source_ids\":[1],\"claim_id\":2}", true);
    try expectSelection(a, selected.selected(), "{\"source_ids\":[2],\"claim_id\":2}", false);
    const part = try compile(a, "{\"type\":\"object\",\"properties\":{\"claim_id\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":2048}},\"required\":[\"claim_id\"],\"additionalProperties\":false}");
    const projected = try schema.project(a, initial, part.root());
    const cloned = try projected.clone(a);
    const sibling = try schema.restrict(allocator, cloned, &.{}, choices);
    defer sibling.release();
    try expectSelection(a, sibling.selected(), "{\"claim_id\":4}", true);
    const repair = try schema.restrict(allocator, resource.select(.{ .bytes = "selection" }).?, &.{}, choices);
    defer repair.release();
    try expectSelection(a, repair.selected(), "{\"source_ids\":[2]}", true);
    for ([_]schema.IntegerChoice{
        .{ .target = .{ .path = &.{.{ .property = "missing" }} }, .definition = .{ .bytes = "selection" }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .definition = .{ .bytes = "unknown" }, .allowed = &.{1} },
        .{ .target = .{ .path = &.{.{ .property = "missing" }} }, .allowed = &.{1} },
    }) |bad| {
        if (schema.restrict(allocator, cloned, &.{}, &.{bad})) |unexpected| {
            unexpected.release();
            return error.TestUnexpectedResult;
        } else |err| if (err != error.InvalidModelResultSchema) return err;
    }
}

test "ID choice declarations reject duplicate locations values bounds wrong shapes and oversized sets" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try compile(a, selectionChoices);
    var too_many: [schema.max_choices + 1]i64 = undefined;
    for (&too_many, 1..) |*value, index| value.* = @intCast(index);
    const at_bound = try schema.restrict(std.testing.allocator, original, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = too_many[0..schema.max_choices] }});
    defer at_bound.release();
    for ([_][]const i64{ &.{ 1, 1 }, &.{0}, &.{2049}, &too_many }) |bad| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, original, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = bad }}));
    const same: schema.IntegerChoice = .{ .target = .{ .path = &.{.{ .property = "source_ids" }} }, .allowed = &.{1} };
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, original, &.{}, &.{ same, same }));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, original, &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "claim_id" }} }, .allowed = &.{} }}));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, try compile(a, replacement), &.{}, &.{.{ .target = .{ .path = &.{.{ .property = "replacement" }} }, .allowed = &.{1} }}));
}

fn compile(allocator: std.mem.Allocator, bytes: []const u8) schema.Error!*const schema.Schema {
    var adapter: parser.Adapter = .{};
    return adapter.compiler().compile(allocator, bytes);
}

fn fieldSchema(allocator: std.mem.Allocator, field: []const u8) ![]const u8 {
    return std.mem.concat(allocator, u8, &.{ "{\"type\":\"object\",\"properties\":{\"value\":", field, "},\"required\":[\"value\"],\"additionalProperties\":false}" });
}

test "compact singleton schema compiles candidate fields without execution metadata" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), replacement);
    try std.testing.expectEqualStrings(replacement, compiled.bytes());
    const properties = compiled.root().object;
    try std.testing.expectEqual(@as(usize, 1), properties.len);
    try std.testing.expectEqualStrings("replacement", properties[0].name);
    try std.testing.expect(properties[0].required);
    try std.testing.expectEqual(@as(u32, 0), properties[0].schema.string.minimum);
    try std.testing.expectEqual(@as(u32, 256), properties[0].schema.string.maximum);
    try std.testing.expect(schema.findProperty(properties, "kind") == null);
}

test "oneOf compiles disjoint closed variants and retains domain selections" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), variants);
    try std.testing.expectEqual(@as(usize, 2), compiled.root().one_of.len);
    const content = compiled.root().one_of[0].object;
    try std.testing.expectEqualStrings("content", schema.findProperty(content, "kind").?.schema.constant.string);
    const nested = try compile(arena.allocator(), try fieldSchema(arena.allocator(), variants));
    try std.testing.expectEqual(@as(usize, 2), nested.root().object[0].schema.one_of.len);

    const group = try compile(arena.allocator(),
        \\{"type":"object","properties":{"replacementsByTargetId":{"type":"object","properties":{"target-a":{"type":"string","maxLength":64},"target-b":{"enum":["yes","no"]}},"required":["target-a","target-b"],"additionalProperties":false}},"required":["replacementsByTargetId"],"additionalProperties":false}
    );
    const targets = group.root().object[0].schema.object;
    try std.testing.expectEqual(@as(usize, 2), targets.len);
    try std.testing.expect(schema.findProperty(targets, "target-a").?.required);
    try std.testing.expect(schema.findProperty(targets, "target-b").?.required);
}

test "integer choice restrictions bind tagged fields without restricting unrelated integer support" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\{"type":"object","properties":{"value":{"type":"array","maxItems":2,"items":{"oneOf":[{"type":"string","maxLength":20},{"type":"object","properties":{"kind":{"const":"exact_copy"},"claim_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","claim_id"],"additionalProperties":false}]}},"support":{"type":"array","maxItems":2,"items":{"type":"integer","minimum":1,"maximum":100}}},"required":["value","support"],"additionalProperties":false}
    ;
    const complete = try compile(a, source);
    const selected = try schema.restrict(std.testing.allocator, complete, &.{}, &.{.{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{ 2, 7 } }});
    defer selected.release();
    const value = schema.findProperty(selected.selected().root().object, "value").?.schema;
    const exact = schema.findProperty(value.array.items.one_of[1].object, "claim_id").?.schema;
    try std.testing.expectEqualDeep(&[_]i64{ 2, 7 }, exact.integer_enumeration);
    try std.testing.expect(schema.findProperty(selected.selected().root().object, "support").?.schema.array.items.* == .integer);
    const validator = @import("domain/model_payload_schema.zig");
    try std.testing.expect(validator.validateValue(.{ .number = "2e0" }, exact) == null);
    try std.testing.expectEqual(.enum_mismatch, validator.validateValue(.{ .number = "1" }, exact).?.reason);
    var adapter: parser.Adapter = .{};
    for (std.enums.values(@import("domain/model_schema_projection.zig").Profile)) |profile| {
        const projection = try @import("domain/model_schema_projection.zig").render(a, selected.selected(), profile);
        if (profile == .complete) {
            const restored = try adapter.compiler().compileSelected(a, projection);
            try std.testing.expectEqualDeep(selected.selected().root().*, restored.root().*);
        } else try std.testing.expect(std.mem.indexOf(u8, projection, "\"enum\":[2,7]") != null);
    }
    for ([_]schema.IntegerChoice{
        .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "other" } }, .allowed = &.{2} },
        .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{101} },
        .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{} },
    }) |bad| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, complete, &.{}, &.{bad}));
    // A retained packet may carry text choices into a provenance-only repair.
    // With no text selector in that selected schema, there is nothing to narrow.
    const provenance_only = try compile(a, "{\"type\":\"object\",\"properties\":{\"claim_ids\":{\"type\":\"array\",\"maxItems\":2,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":100}}},\"required\":[\"claim_ids\"],\"additionalProperties\":false}");
    const no_text = try schema.restrict(std.testing.allocator, provenance_only, &.{}, &.{.{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{2} }});
    defer no_text.release();
    try std.testing.expectEqualDeep(provenance_only.root().*, no_text.selected().root().*);
}

test "derived integer choice sets accept 1024 values and reject larger sets" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\{"type":"object","properties":{"value":{"type":"object","properties":{"kind":{"const":"selected"},"id":{"type":"integer","minimum":1,"maximum":2000}},"required":["kind","id"],"additionalProperties":false}},"required":["value"],"additionalProperties":false}
    ;
    const complete = try compile(a, source);
    for ([_]usize{ 1024, 1025 }) |count| {
        const ids = try a.alloc(i64, count);
        for (ids, 0..) |*id, index| id.* = @intCast(index + 1);
        const choices = &[_]schema.IntegerChoice{.{ .target = .{ .tagged = .{ .kind = "selected", .field = "id" } }, .allowed = ids }};
        if (count > schema.max_choices) {
            try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, complete, &.{}, choices));
        } else {
            const selected = try schema.restrict(std.testing.allocator, complete, &.{}, choices);
            defer selected.release();
            const id = schema.findProperty(schema.findProperty(selected.selected().root().object, "value").?.schema.object, "id").?.schema;
            try std.testing.expectEqual(count, id.integer_enumeration.len);
            var adapter: parser.Adapter = .{};
            const restored = try adapter.compiler().compileSelected(a, selected.selected().modelBytes());
            try std.testing.expectEqualDeep(selected.selected().root().*, restored.root().*);
        }
    }
}

test "bounded scalar collection and optional property shapes are supported" {
    const accepted = [_][]const u8{
        "{\"type\":\"string\",\"maxLength\":0}",
        "{\"type\":\"integer\",\"minimum\":-9223372036854775808,\"maximum\":9223372036854775807}",
        "{\"type\":\"boolean\"}",
        "{\"type\":\"null\"}",
        "{\"const\":true}",
        "{\"const\":null}",
        "{\"const\":7}",
        "{\"const\":\"Unicode \\u00e9\"}",
        "{\"enum\":[\"one\",\"two\"]}",
        "{\"enum\":[1,2]}",
        "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"},\"minItems\":0,\"maxItems\":4}",
        "{\"type\":\"object\",\"properties\":{\"optional\":{\"type\":\"boolean\"}},\"required\":[],\"additionalProperties\":false}",
    };
    for (accepted) |field| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const compiled = try compile(arena.allocator(), try fieldSchema(arena.allocator(), field));
        const cloned = try compiled.clone(arena.allocator());
        try std.testing.expectEqualStrings(compiled.bytes(), cloned.bytes());
        const transported = try compile(arena.allocator(), cloned.modelBytes());
        try std.testing.expectEqualDeep(compiled.root().*, transported.root().*);
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // These are ordinary schema-declared business fields, not runtime authority.
    _ = try compile(arena.allocator(),
        \\{"type":"object","properties":{"status":{"enum":["new","old"]},"requestId":{"type":"string","maxLength":32}},"required":["status","requestId"],"additionalProperties":false}
    );
}

test "schema transport rejects malformed duplicate trailing and legacy envelope documents" {
    const rejected = [_][]const u8{
        "",                                                                                                                                             "{",                        "{}",                                  "true",                                                    "[]",                                        "\xff",                                            "\xef\xbb\xbf" ++ replacement,
        replacement ++ " {}",                                                                                                                           replacement ++ " trailing", "```json\n" ++ replacement ++ "\n```", "{\"schemaVersion\":\"model-envelope/v1\",\"result\":{}}", "{\"type\":\"object\",\"type\":\"object\"}", "{\"type\":\"object\",\"t\\u0079pe\":\"object\"}", "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false,\"$schema\":\"other\"}",
        "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"boolean\"},\"x\":{\"type\":\"null\"}},\"required\":[],\"additionalProperties\":false}",
    };
    for (rejected) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    _ = try compile(arena.allocator(), " \t\r\n" ++ replacement ++ "\n");
}

test "unknown contradictory unbounded and unsupported schema fields reject at any depth" {
    const rejected = [_][]const u8{
        "{}",                                                                                                      "true",                                                                                              "[]",                                                                                                                            "{\"type\":\"number\",\"minimum\":0,\"maximum\":1}",
        "{\"type\":[\"string\",\"null\"]}",                                                                        "{\"$ref\":\"https://example.invalid/schema\"}",                                                     "{\"type\":\"string\"}",                                                                                                         "{\"type\":\"string\",\"maxLength\":-1}",
        "{\"type\":\"string\",\"maxLength\":4294967296}",                                                          "{\"type\":\"string\",\"maxLength\":2.0}",                                                           "{\"type\":\"string\",\"minLength\":3,\"maxLength\":2}",                                                                         "{\"type\":\"string\",\"maxLength\":2,\"pattern\":\".*\"}",
        "{\"type\":\"boolean\",\"default\":true}",                                                                 "{\"type\":\"null\",\"nullable\":true}",                                                             "{\"type\":\"integer\",\"minimum\":0}",                                                                                          "{\"type\":\"integer\",\"minimum\":1,\"maximum\":0}",
        "{\"type\":\"integer\",\"minimum\":0,\"maximum\":9223372036854775808}",                                    "{\"type\":\"integer\",\"minimum\":0,\"maximum\":1e9999}",                                           "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"}}",                                                                         "{\"type\":\"array\",\"maxItems\":2}",
        "{\"type\":\"array\",\"items\":[],\"maxItems\":2}",                                                        "{\"type\":\"array\",\"items\":{\"type\":\"boolean\"},\"minItems\":3,\"maxItems\":2}",               "{\"enum\":[]}",                                                                                                                 "{\"enum\":[\"x\",\"x\"]}",
        "{\"enum\":[\"x\",\"\\u0078\"]}",                                                                          "{\"enum\":[1,\"1\"]}",                                                                              "{\"const\":{}}",                                                                                                                "{\"const\":1.5}",
        "{\"const\":true,\"enum\":[\"yes\"]}",                                                                     "{\"enum\":[\"x\"],\"type\":\"string\"}",                                                            "{\"type\":\"object\"}",                                                                                                         "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":true}",
        "{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":{\"type\":\"boolean\"}}", "{\"type\":\"object\",\"properties\":{},\"required\":[\"missing\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{\"x\":{\"type\":\"boolean\"}},\"required\":[\"x\",\"x\"],\"additionalProperties\":false}", "{\"type\":\"object\",\"properties\":{},\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":[],\"required\":[],\"additionalProperties\":false}",                  "{\"type\":\"object\",\"properties\":{},\"required\":true,\"additionalProperties\":false}",          "{\"anyOf\":[{},{}]}",                                                                                                           "{\"oneOf\":[]}",
        "{\"oneOf\":[{}]}",                                                                                        "{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"boolean\"}]}",                                       "{\"enum\":[1,1]}",                                                                                                              "{\"enum\":[1,2.0]}",
    };
    for (rejected) |field| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), try fieldSchema(arena.allocator(), field)));
    }
}

test "root shape and variant discriminator must be explicit nonredundant and unique" {
    const rejected = [_][]const u8{
        "{\"type\":\"string\",\"maxLength\":64}",
        "{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":\"content\"}},\"required\":[\"kind\"],\"additionalProperties\":false}",
        "{\"type\":\"object\",\"properties\":{\"kind\":{\"enum\":[\"content\"]}},\"required\":[\"kind\"],\"additionalProperties\":false}",
    };
    for (rejected) |bytes| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
    const replacements = [_][2][]const u8{
        .{ "clarification_needed", "content" },
        .{ "\"required\":[\"kind\",\"question\"]", "\"required\":[\"question\"]" },
        .{ "{\"const\":\"content\"}", "{\"enum\":[\"content\",\"other\"]}" },
        .{ "{\"const\":\"content\"}", "{\"const\":0}" },
        .{ "{\"const\":\"content\"}", "{\"const\":\"\"}" },
    };
    for (replacements) |change| {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.mem.replaceOwned(u8, arena.allocator(), variants, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, variants, bytes));
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
}

test "schema compilation respects exact depth and byte guards" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var child: []const u8 = "{\"type\":\"boolean\"}";
    for (0..schema.max_depth - 2) |_| {
        child = try std.mem.concat(allocator, u8, &.{ "{\"type\":\"array\",\"maxItems\":1,\"items\":", child, "}" });
    }
    _ = try compile(allocator, try fieldSchema(allocator, child));
    child = try std.mem.concat(allocator, u8, &.{ "{\"type\":\"array\",\"maxItems\":1,\"items\":", child, "}" });
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try fieldSchema(allocator, child)));

    const padded = try allocator.alloc(u8, schema.max_bytes + 1);
    @memset(padded, ' ');
    @memcpy(padded[0..replacement.len], replacement);
    _ = try compile(allocator, padded[0..schema.max_bytes]);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, padded));
    var nested: std.array_list.Managed(u8) = .init(allocator);
    try nested.appendNTimes('[', schema.max_json_depth + 1);
    try nested.appendNTimes(']', schema.max_json_depth + 1);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, nested.items));
}

test "schema resource cloning owns source properties literals and nested nodes" {
    var original = std.heap.ArenaAllocator.init(std.testing.allocator);
    var copy = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer copy.deinit();
    const bytes = try original.allocator().dupe(u8, variants);
    const source: compilation.CompiledResource = .{
        .id = .{ .bytes = "declared-result" },
        .content = .{ .result_schema = try compile(original.allocator(), bytes) },
    };
    @memset(bytes, 'x');
    try std.testing.expectEqualStrings(variants, source.bytes());
    const cloned = try source.clone(copy.allocator(), null);
    original.deinit();
    try std.testing.expectEqualStrings(variants, cloned.bytes());
    try std.testing.expectEqual(.result_schema, cloned.kind());
    const properties = cloned.content.result_schema.root().one_of[1].object;
    try std.testing.expectEqualStrings("clarification_needed", schema.findProperty(properties, "kind").?.schema.constant.string);
    try std.testing.expectEqual(@as(u32, 128), schema.findProperty(properties, "question").?.schema.string.maximum);
}

test "property enumeration variant and total-node guards accept boundaries and reject excess" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    _ = try compile(allocator, try objectProperties(allocator, schema.max_properties, "{\"type\":\"boolean\"}"));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try objectProperties(allocator, schema.max_properties + 1, "{\"type\":\"boolean\"}")));
    for ([_]usize{ 256, 257, 1024, 1025 }) |count| {
        var buffer: std.array_list.Managed(u8) = .init(allocator);
        try buffer.appendSlice("{\"enum\":[");
        for (0..count) |index| {
            if (index != 0) try buffer.append(',');
            try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"value-{d}\"", .{index}));
        }
        try buffer.appendSlice("]}");
        const bytes = try fieldSchema(allocator, buffer.items);
        var adapter: parser.Adapter = .{};
        if (count <= 1024) {
            const compiled = try compile(allocator, bytes);
            const cloned = try compiled.clone(allocator);
            const projection = @import("domain/model_schema_projection.zig");
            const validation = @import("domain/model_payload_schema.zig");
            for (std.enums.values(projection.Profile)) |profile| {
                const projected = try projection.render(allocator, cloned, profile);
                const restored = try adapter.compiler().compileSelected(allocator, projected);
                try std.testing.expectEqualDeep(compiled.root().*, restored.root().*);
                const choices = restored.root().object[0].schema;
                try std.testing.expectEqual(count, choices.enumeration.len);
                try std.testing.expect(validation.validateValue(.{ .string = "value-0" }, choices) == null);
                const last = try std.fmt.allocPrint(allocator, "value-{d}", .{count - 1});
                try std.testing.expect(validation.validateValue(.{ .string = last }, choices) == null);
                const unavailable = try std.fmt.allocPrint(allocator, "value-{d}", .{count});
                try std.testing.expectEqual(.enum_mismatch, validation.validateValue(.{ .string = unavailable }, choices).?.reason);
            }
        } else {
            try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, bytes));
            try std.testing.expectError(error.InvalidModelResultSchema, adapter.compiler().compileSelected(allocator, bytes));
        }
    }
    for ([_]usize{ schema.max_variants, schema.max_variants + 1 }) |count| {
        var buffer: std.array_list.Managed(u8) = .init(allocator);
        try buffer.appendSlice("{\"oneOf\":[");
        for (0..count) |index| {
            if (index != 0) try buffer.append(',');
            try buffer.appendSlice("{\"type\":\"object\",\"properties\":{\"kind\":{\"const\":");
            try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"variant-{d}\"", .{index}));
            try buffer.appendSlice("}},\"required\":[\"kind\"],\"additionalProperties\":false}");
        }
        try buffer.appendSlice("]}");
        if (count == schema.max_variants) {
            _ = try compile(allocator, buffer.items);
        } else try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, buffer.items));
    }

    const child = try objectProperties(allocator, 15, "{\"type\":\"boolean\"}");
    const smaller_child = try objectProperties(allocator, 14, "{\"type\":\"boolean\"}");
    var buffer: std.array_list.Managed(u8) = .init(allocator);
    try buffer.appendSlice("{\"type\":\"object\",\"properties\":{");
    for (0..256) |index| {
        if (index != 0) try buffer.append(',');
        try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"p{d}\":", .{index}));
        try buffer.appendSlice(if (index == 255) smaller_child else child);
    }
    try buffer.appendSlice("},\"required\":[],\"additionalProperties\":false}");
    // 1 root + 255 * (1 object + 15 leaves) + (1 object + 14 leaves).
    try std.testing.expectEqual(@as(usize, 4096), schema.max_nodes);
    _ = try compile(allocator, buffer.items);
    try std.testing.expectError(error.InvalidModelResultSchema, compile(allocator, try objectProperties(allocator, 256, child)));
}

fn objectProperties(allocator: std.mem.Allocator, count: usize, child: []const u8) ![]const u8 {
    var buffer: std.array_list.Managed(u8) = .init(allocator);
    try buffer.appendSlice("{\"type\":\"object\",\"properties\":{");
    for (0..count) |index| {
        if (index != 0) try buffer.append(',');
        try buffer.appendSlice(try std.fmt.allocPrint(allocator, "\"p{d}\":", .{index}));
        try buffer.appendSlice(child);
    }
    try buffer.appendSlice("},\"required\":[],\"additionalProperties\":false}");
    return buffer.items;
}

test "schema compilation and cloning release every allocation on failure" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(compileAndClone, .{});
}

fn compileAndClone(allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const compiled = try compile(arena.allocator(), variants);
    _ = try compiled.clone(arena.allocator());
    _ = try (try compile(arena.allocator(), referenced)).clone(arena.allocator());
}

const referenced =
    \\{ "$defs": {
    \\  "text": {"type":"string","minLength":1,"maxLength":64},
    \\  "answer": {"type":"object","properties":{"answer":{"$ref":"#/$defs/text"}},"required":["answer"],"additionalProperties":false},
    \\  "replacement": {"type":"object","properties":{"replacement":{"$ref":"#/$defs/text"}},"required":["replacement"],"additionalProperties":false}
    \\}, "$ref": "#/$defs/answer" }
;

test "local definitions retain captured authority and independently owned compact result views" {
    var original: std.heap.ArenaAllocator = .init(std.testing.allocator);
    var destination: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer destination.deinit();
    const compiled = try compile(original.allocator(), referenced);
    const copy = try compiled.clone(destination.allocator());
    original.deinit();
    try std.testing.expectEqualStrings(referenced, copy.bytes());
    try std.testing.expect(copy.modelBytes().len < referenced.len);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "$ref") == null);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "$defs") == null);
    try std.testing.expect(std.mem.indexOf(u8, copy.modelBytes(), "\n") == null);
    try std.testing.expect(copy.select(.{ .bytes = "text" }) == null);
    try std.testing.expect(copy.select(.{ .bytes = "missing" }) == null);
    const selected = copy.select(.{ .bytes = "replacement" }).?;
    try std.testing.expectEqualStrings(referenced, selected.bytes());
    try std.testing.expectEqualStrings("replacement", selected.root().object[0].name);
    try std.testing.expect(schema.findProperty(copy.root().object, "replacement") == null);
    for ([_]*const schema.Schema{ copy, selected }) |view| {
        const reparsed = try compile(destination.allocator(), view.modelBytes());
        try std.testing.expectEqualDeep(view.root().*, reparsed.root().*);
        try std.testing.expectEqualStrings(view.modelBytes(), reparsed.modelBytes());
    }
}

test "local reference validation rejects unknown cyclic remote escaped and unused invalid definitions" {
    const changes = [_][2][]const u8{
        .{ "#/$defs/text", "#/$defs/missing" },
        .{ "#/$defs/text", "#/$defs/answer" },
        .{ "#/$defs/text", "https://example.invalid/text" },
        .{ "#/$defs/text", "other.json#/$defs/text" },
        .{ "#/$defs/text", "#/$defs/te~1xt" },
        .{ "#/$defs/text", "#/$defs/text/properties/x" },
        .{ "{\"$ref\":\"#/$defs/text\"}", "{\"$ref\":\"#/$defs/text\",\"maxLength\":3}" },
        .{ "\"replacement\": {\"type\":\"object\"", "\"replacement\": {\"unknown\":true,\"type\":\"object\"" },
        .{ "\"text\": {\"type\":\"string\"", "\"text\": {\"$defs\":{},\"type\":\"string\"" },
        .{ "\"replacement\": {", "\"bad/name\": {" },
    };
    for (changes) |change| {
        var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
        defer arena.deinit();
        const bytes = try std.mem.replaceOwned(u8, arena.allocator(), referenced, change[0], change[1]);
        try std.testing.expect(!std.mem.eql(u8, bytes, referenced));
        try std.testing.expectError(error.InvalidModelResultSchema, compile(arena.allocator(), bytes));
    }
}

test "reference expansion enforces node and depth bounds after substitution" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const child = try objectProperties(a, 16, "{\"type\":\"boolean\"}");
    const root = try objectProperties(a, 256, "{\"$ref\":\"#/$defs/child\"}");
    const bytes = try std.mem.concat(a, u8, &.{ "{\"$defs\":{\"child\":", child, "},", root[1..] });
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, bytes));
    const bounded_child = try objectProperties(a, 15, "{\"type\":\"boolean\"}");
    const small = try objectProperties(a, 14, "{\"type\":\"boolean\"}");
    const exact_root = try std.mem.replaceOwned(u8, a, root, "\"p255\":{\"$ref\":\"#/$defs/child\"}", "\"p255\":{\"$ref\":\"#/$defs/small\"}");
    // References are source syntax, not extra nodes in the expanded 4096-node tree.
    _ = try compile(a, try std.mem.concat(a, u8, &.{ "{\"$defs\":{\"child\":", bounded_child, ",\"small\":", small, "},", exact_root[1..] }));
    var defs: std.array_list.Managed(u8) = .init(a);
    for (0..schema.max_depth + 1) |index| {
        if (index != 0) try defs.append(',');
        try defs.appendSlice(try std.fmt.allocPrint(a, "\"d{d}\":{{\"$ref\":\"#/$defs/d{d}\"}}", .{ index, index + 1 }));
    }
    try defs.appendSlice(try std.fmt.allocPrint(a, ",\"d{d}\":{s}", .{ schema.max_depth + 1, replacement }));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, try std.mem.concat(a, u8, &.{ "{\"$defs\":{", defs.items, "},\"$ref\":\"#/$defs/d0\"}" })));
}

test "nested type-disjoint alternatives accept but overlapping and nonobject response roots reject" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const disjoint = "{\"oneOf\":[{\"type\":\"boolean\"},{\"type\":\"null\"}]}";
    _ = try compile(a, try fieldSchema(a, disjoint));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, disjoint));
    const prose_composition =
        \\{"oneOf":[{"type":"string","minLength":1,"maxLength":80},{"type":"object","properties":{"fragments":{"type":"array","minItems":1,"maxItems":4,"items":{"type":"string","minLength":1,"maxLength":80}}},"required":["fragments"],"additionalProperties":false}]}
    ;
    const text_schema = try compile(a, try fieldSchema(a, prose_composition));
    try std.testing.expectError(error.InvalidModelResultSchema, compile(a, prose_composition));
    try expectSelection(a, text_schema, "{\"value\":\"MOCK ordinary prose\"}", true);
    try expectSelection(a, text_schema, "{\"value\":{\"fragments\":[\"MOCK composed \",\"prose.\"]}}", true);
    for ([_][]const u8{ "{\"value\":[\"MOCK ambiguous array\"]}", "{\"value\":{\"fragments\":[]}}", "{\"value\":{\"fragments\":[\"MOCK text\"],\"extra\":0}}" }) |bad| try expectSelection(a, text_schema, bad, false);
    const projection = @import("domain/model_schema_projection.zig");
    const outline = try projection.outline(a, text_schema.root());
    const shapes = outline.object.get("fields").?.object.get("value").?.object;
    try std.testing.expect(shapes.get("kind") == null);
    try std.testing.expectEqualStrings("string", shapes.get("types").?.array.items[0].string);
    try std.testing.expectEqualStrings("object", shapes.get("types").?.array.items[1].string);
    const bedrock = (try std.json.parseFromSlice(std.json.Value, a, try projection.render(a, text_schema, .native), .{})).value;
    const alternatives = bedrock.object.get("properties").?.object.get("value").?.object.get("anyOf").?.array.items;
    try std.testing.expectEqual(@as(usize, 2), alternatives.len);
    try std.testing.expectEqualStrings("object", alternatives[1].object.get("type").?.string);
    try std.testing.expect(alternatives[1].object.get("properties").?.object.get("kind") == null);
    try std.testing.expectEqual(false, alternatives[1].object.get("additionalProperties").?.bool);
    for ([_][]const u8{
        "{\"oneOf\":[{\"type\":\"string\",\"maxLength\":8},{\"const\":\"overlap\"}]}",
        "{\"oneOf\":[{\"type\":\"integer\",\"minimum\":0,\"maximum\":9},{\"const\":10}]}",
        "{\"oneOf\":[{\"type\":\"boolean\"},{\"oneOf\":[{\"type\":\"string\",\"maxLength\":8},{\"type\":\"null\"}]}]}",
        "{\"oneOf\":[{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false},{\"type\":\"object\",\"properties\":{},\"required\":[],\"additionalProperties\":false}]}",
    }) |bad| try std.testing.expectError(error.InvalidModelResultSchema, compile(a, try fieldSchema(a, bad)));
}

test "native availability narrows nested alternatives without altering canonical schemas" {
    try @import("test_fixtures/untraced_allocator.zig").checkAllAllocationFailures(restrictChoices, .{});
}

fn restrictChoices(allocator: std.mem.Allocator) !void {
    var arena: std.heap.ArenaAllocator = .init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try compile(a, try fieldSchema(a, variants));
    const narrowed = try schema.restrict(allocator, original, &.{.{ .kind = "clarification_needed" }}, &.{});
    defer narrowed.release();
    try std.testing.expect(narrowed.selected().isRestrictionOf(original));
    try std.testing.expect(!original.isRestrictionOf(narrowed.selected()));
    try std.testing.expectEqualStrings(original.bytes(), narrowed.selected().bytes());
    try std.testing.expect(std.mem.indexOf(u8, original.modelBytes(), "clarification_needed") != null);
    try std.testing.expect(std.mem.indexOf(u8, narrowed.selected().modelBytes(), "clarification_needed") == null);
    const check = @import("domain/model_payload_schema.zig");
    for ([_][]const u8{ "{\"value\":{\"kind\":\"content\",\"answer\":\"Supported\"}}", "{\"value\":{\"kind\":\"clarification_needed\",\"question\":\"Choose\"}}" }, 0..) |bytes, index| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{});
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), original.root()) == null);
        try std.testing.expectEqual(index == 0, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), narrowed.selected().root()) == null);
    }
    if (schema.restrict(allocator, original, &.{ .{ .kind = "content" }, .{ .kind = "clarification_needed" } }, &.{})) |unexpected| {
        unexpected.release();
        return error.TestUnexpectedResult;
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        error.InvalidModelResultSchema => {},
    }
    const different = try compile(a, try fieldSchema(a, variants));
    try std.testing.expect(!narrowed.selected().isRestrictionOf(different));
    const copy = try narrowed.selected().clone(a);
    try std.testing.expectEqualStrings(narrowed.selected().modelBytes(), copy.modelBytes());
}

test "explicit native singleton construction omits only determined tagged fields" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical = try compile(a,
        \\{"type":"object","properties":{"value":{"type":"array","minItems":1,"maxItems":4,"items":{"oneOf":[{"type":"string","maxLength":80},{"type":"object","properties":{"kind":{"const":"exact_copy"},"claim_id":{"type":"integer","minimum":1,"maximum":100}},"required":["kind","claim_id"],"additionalProperties":false}]}},"count":{"type":"integer","minimum":1,"maximum":100}},"required":["value","count"],"additionalProperties":false}
    );
    const single: schema.IntegerChoice = .{ .target = .{ .tagged = .{ .kind = "exact_copy", .field = "claim_id" } }, .allowed = &.{7}, .singleton = .construct };
    const fixed = try schema.restrict(std.testing.allocator, canonical, &.{}, &.{single});
    defer fixed.release();
    try expectSelection(a, fixed.selected(), "{\"value\":[\"MOCK narrative \",{\"kind\":\"exact_copy\"}],\"count\":8}", true);
    for ([_][]const u8{
        "{\"value\":[{\"kind\":\"exact_copy\",\"claim_id\":7}],\"count\":8}",
        "{\"value\":[{\"kind\":\"exact_copy\",\"claim_id\":8}],\"count\":8}",
        "{\"value\":[{\"kind\":\"exact_copy\",\"unexpected\":7}],\"count\":8}",
    }) |bad| try expectSelection(a, fixed.selected(), bad, false);
    // Canonical and ordinary restricted contracts continue to require IDs.
    try expectSelection(a, canonical, "{\"value\":[{\"kind\":\"exact_copy\"}],\"count\":8}", false);
    var selected = single;
    selected.singleton = .select;
    const unchanged = try schema.restrict(std.testing.allocator, canonical, &.{}, &.{selected});
    defer unchanged.release();
    try expectSelection(a, unchanged.selected(), "{\"value\":[{\"kind\":\"exact_copy\",\"claim_id\":7}],\"count\":8}", true);
    selected = single;
    selected.allowed = &.{ 7, 9 };
    const multiple = try schema.restrict(std.testing.allocator, canonical, &.{}, &.{selected});
    defer multiple.release();
    try expectSelection(a, multiple.selected(), "{\"value\":[{\"kind\":\"exact_copy\",\"claim_id\":9}],\"count\":8}", true);
    try expectSelection(a, multiple.selected(), "{\"value\":[{\"kind\":\"exact_copy\"}],\"count\":8}", false);
    try expectSelection(a, multiple.selected(), "{\"value\":[{\"kind\":\"exact_copy\",\"claim_id\":8}],\"count\":8}", false);
    const absent = try schema.restrict(std.testing.allocator, canonical, &.{.{ .kind = "exact_copy" }}, &.{});
    defer absent.release();
    try expectSelection(a, absent.selected(), "{\"value\":[{\"kind\":\"exact_copy\"}],\"count\":8}", false);
    // Native construction is explicit tagged scalar policy, never a blanket
    // omission of all singleton values or optional field/array inference.
    selected = single;
    selected.target = .{ .path = &.{.{ .property = "count" }} };
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, canonical, &.{}, &.{selected}));
    selected = single;
    selected.allowed = &.{101};
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, canonical, &.{}, &.{selected}));
    selected.allowed = &.{ 7, 7 };
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, canonical, &.{}, &.{selected}));
    var adapter: parser.Adapter = .{};
    const captured = try adapter.compiler().compileSelected(a, fixed.selected().modelBytes());
    try expectSelection(a, captured, "{\"value\":[{\"kind\":\"exact_copy\"}],\"count\":8}", true);
}

test "coverage requires every value a covered item names to be named by a covering item" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const check = @import("domain/model_payload_schema.zig");
    const variant = "{{\"type\":\"object\",\"properties\":{{\"kind\":{{\"const\":\"{s}\"}},\"text\":{{\"type\":\"string\",\"maxLength\":20}}}},\"required\":[\"kind\",\"text\"],\"additionalProperties\":false}}";
    const items = try std.fmt.allocPrint(a, "{{\"type\":\"array\",\"minItems\":0,\"maxItems\":10,\"items\":{{\"type\":\"object\",\"properties\":{{\"content\":{{\"oneOf\":[" ++ variant ++ "," ++ variant ++ "," ++ variant ++ "]}},\"ids\":{{\"type\":\"array\",\"minItems\":1,\"maxItems\":5,\"items\":{{\"type\":\"integer\",\"minimum\":1,\"maximum\":10}}}}}},\"required\":[\"content\",\"ids\"],\"additionalProperties\":false}}}}", .{ "rule", "check", "note" });
    const resource = try compile(a, try fieldSchema(a, items));
    const path: []const schema.ChoiceStep = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "ids" } };
    const rule: schema.ItemCoverage = .{ .kind_property = "content", .covered = &.{"rule"}, .covering = &.{"check"} };
    const covered = try schema.restrict(std.testing.allocator, resource, &.{}, &.{.{ .target = .{ .path = path }, .allowed = &.{ 3, 5, 7 }, .collection = .unique_subset, .coverage = rule }});
    defer covered.release();
    const item = "{{\"content\":{{\"kind\":\"{s}\",\"text\":\"t\"}},\"ids\":{s}}}";
    const respond = struct {
        fn of(allocator: std.mem.Allocator, comptime layout: []const u8, args: anytype) ![]const u8 {
            return std.fmt.allocPrint(allocator, "{{\"value\":[" ++ layout ++ "]}}", args);
        }
    }.of;
    // Admitted: every rule value has a check naming it; notes neither need nor give coverage.
    for ([_][]const u8{
        try respond(a, item ++ "," ++ item ++ "," ++ item, .{ "rule", "[3]", "check", "[5,3]", "note", "[7]" }),
        try respond(a, item ++ "," ++ item, .{ "check", "[3]", "note", "[5]" }),
        "{\"value\":[]}",
    }) |bytes| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), covered.selected().root()) == null);
    }
    // Rejected at the uncovered value itself, whatever else covers its siblings.
    for ([_]struct { bytes: []const u8, path: []const u8 }{
        .{ .bytes = try respond(a, item ++ "," ++ item, .{ "rule", "[3,5]", "check", "[3]" }), .path = "/value/0/ids/1" },
        .{ .bytes = try respond(a, item ++ "," ++ item, .{ "rule", "[3]", "note", "[3]" }), .path = "/value/0/ids/0" },
        .{ .bytes = try respond(a, item ++ "," ++ item ++ "," ++ item, .{ "check", "[3]", "rule", "[3]", "rule", "[7]" }), .path = "/value/2/ids/0" },
    }) |case| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, case.bytes, .{ .parse_numbers = false });
        const rejected = check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), covered.selected().root()).?;
        try std.testing.expectEqual(check.Rejection.uncovered_member, rejected.reason);
        try std.testing.expectEqualStrings(case.path, (try rejected.describe(a)).path);
        try std.testing.expectEqualStrings(case.path, (try rejected.describeExpected(a)).path);
        // The rejection carries the compiled rule, so its correction names the covering kinds.
        try std.testing.expectEqualDeep(covered.selected().coverageChoices()[0].coverage, rejected.covering.?);
        // The provider schema can't express coverage; replay restores it from the record.
        const wire = try compile(a, covered.selected().modelBytes());
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), wire.root()) == null);
        const restored = try schema.restrictRecorded(std.testing.allocator, wire, &.{}, covered.selected().coverageChoices(), &.{});
        defer restored.release();
        try std.testing.expectEqual(check.Rejection.uncovered_member, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), restored.selected().root()).?.reason);
    }
    try std.testing.expectEqual(@as(usize, 1), covered.selected().coverageChoices().len);
    const cloned = try covered.selected().clone(a);
    try std.testing.expectEqualDeep(covered.selected().coverageChoices(), cloned.coverageChoices());
    try std.testing.expect(schema.findProperty(cloned.root().object, "value").?.schema.array.coverage != null);
    // The rule must name a subset selector on an item list whose kinds it can see.
    for ([_]schema.IntegerChoice{
        .{ .target = .{ .path = path }, .allowed = &.{ 3, 5 }, .coverage = rule },
        .{ .target = .{ .path = &.{.{ .property = "value" }} }, .allowed = &.{3}, .collection = .unique_subset, .coverage = rule },
        .{ .target = .{ .path = path }, .allowed = &.{3}, .collection = .unique_subset, .coverage = .{ .kind_property = "kinds", .covered = &.{"rule"}, .covering = &.{"check"} } },
        .{ .target = .{ .path = path }, .allowed = &.{3}, .collection = .unique_subset, .coverage = .{ .kind_property = "content", .covered = &.{"ghost"}, .covering = &.{"check"} } },
        .{ .target = .{ .path = path }, .allowed = &.{3}, .collection = .unique_subset, .coverage = .{ .kind_property = "content", .covered = &.{}, .covering = &.{"check"} } },
        .{ .target = .{ .path = path }, .allowed = &.{3}, .collection = .unique_subset, .coverage = .{ .kind_property = "content", .covered = &.{"rule"}, .covering = &.{ "check", "rule" } } },
        .{ .target = .{ .path = path }, .allowed = &.{3}, .collection = .unique_subset, .coverage = .{ .kind_property = "content", .covered = &.{ "rule", "rule" }, .covering = &.{"check"} } },
    }) |invalid| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrict(std.testing.allocator, resource, &.{}, &.{invalid}));
}

test "required items need an item in an array whose sibling takes a listed value" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const check = @import("domain/model_payload_schema.zig");
    const finding = "{\"type\":\"object\",\"properties\":{\"verdict\":{\"enum\":[\"fine\",\"flagged\",\"unsure\"]},\"note\":{\"type\":\"string\",\"maxLength\":20},\"refs\":{\"type\":\"array\",\"minItems\":0,\"maxItems\":5,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":9}},\"extra\":{\"type\":\"array\",\"minItems\":0,\"maxItems\":5,\"items\":{\"type\":\"integer\",\"minimum\":1,\"maximum\":9}}},\"required\":[\"verdict\",\"note\",\"refs\"],\"additionalProperties\":false}";
    const items = try std.fmt.allocPrint(a, "{{\"type\":\"array\",\"minItems\":0,\"maxItems\":10,\"items\":{{\"type\":\"object\",\"properties\":{{\"ordinal\":{{\"type\":\"integer\",\"minimum\":1,\"maximum\":9}},\"value\":{s}}},\"required\":[\"ordinal\",\"value\"],\"additionalProperties\":false}}}}", .{finding});
    const resource = try compile(a, try fieldSchema(a, items));
    const path: []const schema.ChoiceStep = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "value" }, .{ .property = "refs" } };
    const when: schema.RequiredWhen = .{ .property = "verdict", .values = &.{ "flagged", "unsure" } };
    const required = try schema.restrictFieldPolicies(std.testing.allocator, resource, &.{}, &.{}, &.{}, &.{.{ .path = path, .when = when }});
    defer required.release();
    const item = "{{\"ordinal\":1,\"value\":{{\"verdict\":\"{s}\",\"note\":\"n\",\"refs\":{s}}}}}";
    const respond = struct {
        fn of(allocator: std.mem.Allocator, comptime layout: []const u8, args: anytype) ![]const u8 {
            return std.fmt.allocPrint(allocator, "{{\"value\":[" ++ layout ++ "]}}", args);
        }
    }.of;
    // Admitted: a listed value with items, an unlisted value without any, and no findings.
    for ([_][]const u8{
        try respond(a, item ++ "," ++ item, .{ "flagged", "[2]", "unsure", "[3,4]" }),
        try respond(a, item, .{ "fine", "[]" }),
        "{\"value\":[]}",
    }) |bytes| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, bytes, .{ .parse_numbers = false });
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), required.selected().root()) == null);
    }
    // Rejected at the empty array itself.
    for ([_]struct { bytes: []const u8, path: []const u8 }{
        .{ .bytes = try respond(a, item, .{ "unsure", "[]" }), .path = "/value/0/value/refs" },
        .{ .bytes = try respond(a, item ++ "," ++ item, .{ "fine", "[]", "flagged", "[]" }), .path = "/value/1/value/refs" },
    }) |case| {
        const parsed = try std.json.parseFromSlice(std.json.Value, a, case.bytes, .{ .parse_numbers = false });
        const rejected = check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), required.selected().root()).?;
        try std.testing.expectEqual(check.Rejection.missing_required_item, rejected.reason);
        try std.testing.expectEqualStrings(case.path, (try rejected.describe(a)).path);
        try std.testing.expectEqualStrings(case.path, (try rejected.describeExpected(a)).path);
        // The provider schema can't express the rule; replay restores it from the record.
        const wire = try compile(a, required.selected().modelBytes());
        try std.testing.expect(check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), wire.root()) == null);
        const restored = try schema.restrictRecorded(std.testing.allocator, wire, &.{}, &.{}, required.selected().requiredItems());
        defer restored.release();
        try std.testing.expectEqual(check.Rejection.missing_required_item, check.validateValue(@import("domain/model_envelope.zig").value(&parsed.value), restored.selected().root()).?.reason);
    }
    try std.testing.expectEqual(@as(usize, 1), required.selected().requiredItems().len);
    try std.testing.expectEqualDeep(when, required.selected().requiredItems()[0].when);
    const cloned = try required.selected().clone(a);
    try std.testing.expectEqualDeep(required.selected().requiredItems(), cloned.requiredItems());
    const cloned_value = schema.findProperty(schema.findProperty(cloned.root().object, "value").?.schema.array.items.object, "value").?.schema;
    try std.testing.expect(schema.findProperty(cloned_value.object, "refs").?.schema.array.required_when != null);
    // The rule must reach a required array with a required sibling that can take every value.
    for ([_]schema.RequiredItems{
        .{ .path = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "value" }, .{ .property = "missing" } }, .when = when },
        .{ .path = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "value" }, .{ .property = "extra" } }, .when = when },
        .{ .path = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "value" }, .{ .property = "note" } }, .when = when },
        .{ .path = &.{ .{ .property = "value" }, .{ .items = {} }, .{ .property = "value" } }, .when = when },
        .{ .path = &.{ .{ .property = "value" }, .{ .items = {} } }, .when = when },
        .{ .path = &.{}, .when = when },
        .{ .path = path, .when = .{ .property = "verdict", .values = &.{} } },
        .{ .path = path, .when = .{ .property = "verdict", .values = &.{"ghost"} } },
        .{ .path = path, .when = .{ .property = "verdict", .values = &.{ "flagged", "flagged" } } },
        .{ .path = path, .when = .{ .property = "ordinal", .values = &.{"flagged"} } },
        .{ .path = path, .when = .{ .property = "absent", .values = &.{"flagged"} } },
        .{ .path = path, .when = .{ .property = "refs", .values = &.{"flagged"} } },
    }) |invalid| try std.testing.expectError(error.InvalidModelResultSchema, schema.restrictFieldPolicies(std.testing.allocator, resource, &.{}, &.{}, &.{}, &.{invalid}));
    try std.testing.expectError(error.InvalidModelResultSchema, schema.restrictFieldPolicies(std.testing.allocator, resource, &.{}, &.{}, &.{}, &.{ .{ .path = path, .when = when }, .{ .path = path, .when = when } }));
}
