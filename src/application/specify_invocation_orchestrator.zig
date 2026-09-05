const children = @import("specify_invocation_child_bindings.zig");

/// Private children implement one atomic invocation contract, not a workflow.
pub fn run(bindings: children.ChildBindings) children.Outcome {
    switch (bindings.parse()) {
        .ok => {},
        .failed => return .failed,
    }
    return bindings.validate();
}

test "parse precedes validation and failure prevents the second child" {
    const std = @import("std");
    const Spy = struct {
        calls: usize = 0,
        fail_parse: bool,
        fn parse(context: *anyopaque) children.Outcome {
            const self: *@This() = @ptrCast(@alignCast(context));
            std.debug.assert(self.calls == 0);
            self.calls += 1;
            return if (self.fail_parse) .failed else .ok;
        }
        fn validate(context: *anyopaque) children.Outcome {
            const self: *@This() = @ptrCast(@alignCast(context));
            std.debug.assert(self.calls == 1);
            self.calls += 1;
            return .ok;
        }
    };
    for ([_]bool{ false, true }) |fail| {
        var spy: Spy = .{ .fail_parse = fail };
        const result = run(.{ .context = &spy, .parse_fn = Spy.parse, .validate_fn = Spy.validate });
        try std.testing.expectEqual(if (fail) children.Outcome.failed else .ok, result);
        try std.testing.expectEqual(@as(usize, if (fail) 1 else 2), spy.calls);
    }
}
