const std = @import("std");
const types = @import("types.zig");
const engine = @import("engine.zig");
const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

// Helper to print board if a test fails
fn printBoard(game: *engine.Game) void {
    std.debug.print("\n", .{});
    var row: usize = 0;
    while (row < 8) : (row += 1) {
        var col: usize = 0;
        while (col < 8) : (col += 1) {
            const p = game.board[row][col];
            if (p) |piece| {
                const char: u8 = switch (piece.type) {
                    .Pawn => 'P',
                    .Knight => 'N',
                    .Bishop => 'B',
                    .Rook => 'R',
                    .Queen => 'Q',
                    .King => 'K',
                };
                if (piece.color == .White) {
                    std.debug.print("{c} ", .{char});
                } else {
                    // Lowercase for black
                    std.debug.print("{c} ", .{std.ascii.toLower(char)});
                }
            } else {
                std.debug.print(". ", .{});
            }
        }
        std.debug.print("\n", .{});
    }
}

test "FEN Loading and Turn Switching" {
    const allocator = std.testing.allocator;
    // Standard Start Position
    var game = try engine.Game.init(allocator, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    defer game.deinit();

    // White should start
    try expect(game.turn == .White);

    // Check Black King position (Row 0, Col 4)
    // std.debug.print("{any}\n", .{game.board});
    try expect(game.board[0][4] != null);
    try expect(game.board[0][4].?.type == .King);
    try expect(game.board[0][4].?.color == .Black);

    // Check Black King position (Row 7, Col 4)
    try expect(game.board[7][4] != null);
    try expect(game.board[7][4].?.type == .King);

    // Switch turn
    game.switchTurn();
    try expect(game.turn == .Black);
}

test "Pawn Movement (Single, Double, Capture)" {
    const allocator = std.testing.allocator;
    var game = try engine.Game.init(allocator, "4k3/8/8/8/8/3p4/4P3/4K3 w - - 0 1");
    defer game.deinit();

    game.turn = .White;
    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    var found_single = false;
    var found_double = false;
    var found_capture = false;

    for (moves[0..count]) |m| {
        if (m.from[0] == 6 and m.from[1] == 4) {
            if (m.to[0] == 5 and m.to[1] == 4) found_single = true;
            if (m.to[0] == 4 and m.to[1] == 4) found_double = true;
            if (m.to[0] == 5 and m.to[1] == 3) found_capture = true;
        }
    }

    try expect(found_single);
    try expect(found_double);
    try expect(found_capture);
}

test "Apply and Undo Move" {
    const allocator = std.testing.allocator;
    var game = try engine.Game.init(allocator, "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1");
    defer game.deinit();

    const start_fen_hash = game.turn; // Simple state check

    // Move Black Pawn E2 (1,4) to E4 (3,4)
    const move = types.Move{
        .from = .{ 1, 4 },
        .to = .{ 3, 4 },
        .move_type = .DoublePawnPush,
        .piece = .Pawn,
    };

    try game.applyMove(move);

    // Verify Board State Changed
    try expect(game.board[1][4] == null);
    try expect(game.board[3][4] != null);
    try expect(game.board[3][4].?.type == .Pawn);
    try expect(game.en_passant_pos != null); // Should set EP target

    // Undo
    game.undoMove(move);

    // Verify Board State Restored
    try expect(game.board[1][4] != null);
    try expect(game.board[3][4] == null);
    try expect(game.en_passant_pos == null); // Restored to null
    try expect(game.turn == start_fen_hash);
}

test "Check Detection and Illegal Moves" {
    const allocator = std.testing.allocator;
    // King at E1 (0,4), Enemy Rook at E8 (7,4).
    // King cannot move to E2 (1,4) because of Rook.
    var game = try engine.Game.init(allocator, "4r1k1/8/8/8/8/8/8/4K3 w - - 0 1");
    defer game.deinit();

    game.turn = .White;
    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    // King moves:
    // D1 (7,3) - Safe
    // F1 (7,5) - Safe
    // D2 (6,3) - Safe
    // E2 (6,4) - ILLEGAL (File E is attacked by Rook)
    // F2 (6,5) - Safe

    for (moves[0..count]) |m| {
        if (m.from[0] == 0 and m.from[1] == 4) {
            // Assert we NEVER generate a move to (1,4)
            const is_e2 = (m.to[0] == 6 and m.to[1] == 4);
            try expect(!is_e2);
        }
    }
}

test "Castling Rights" {
    const allocator = std.testing.allocator;
    // White King E1, Rook H1. Path clear.
    var game = try engine.Game.init(allocator, "4k3/8/8/8/8/8/8/4K2R w K - 0 1");
    defer game.deinit();

    // Verify setup
    try expect(game.board[7][4] != null);
    try expect(game.board[7][7] != null);
    try expect(game.castlingRights.white_king_side == true);

    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    var can_castle = false;
    for (moves[0..count]) |m| {
        if (m.move_type == .Castling and m.to[1] == 6) {
            can_castle = true;
        }
    }
    try expect(can_castle);
}

// Perft Test
const PerftResults = struct {
    nodes: u64 = 0,
    captures: u64 = 0,
    en_passants: u64 = 0,
    castles: u64 = 0,
    promotions: u64 = 0,

    pub fn add(self: *PerftResults, other: PerftResults) void {
        self.nodes += other.nodes;
        self.captures += other.captures;
        self.en_passants += other.en_passants;
        self.castles += other.castles;
        self.promotions += other.promotions;
    }
};

fn perft(game: *engine.Game, depth: u32) !PerftResults {
    // Base case: we reached a leaf node
    if (depth == 0) return PerftResults{ .nodes = 1 };

    var total_results = PerftResults{};

    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    for (moves[0..count]) |move| {
        const is_capture = move.move_type == .Capture or move.move_type == .EnPassant;
        const is_ep = move.move_type == .EnPassant;
        const is_castle = move.move_type == .Castling;
        const is_promo = move.move_type == .Promotion;

        try game.applyMove(move);
        game.switchTurn();
        // if (history.captured_piece != null) {
        //     // std.debug.print("Move: {any}\n", .{nonull_history_captured_piece});
        //     is_capture = true;
        // }

        const branch_results = try perft(game, depth - 1);

        // If depth is 1, the "nodes" of the child are actually the stats for THIS move
        if (depth == 1) {
            if (is_capture) total_results.captures += 1;
            if (is_ep) total_results.en_passants += 1;
            if (is_castle) total_results.castles += 1;
            if (is_promo) total_results.promotions += 1;
            total_results.nodes += 1;
        } else {
            total_results.add(branch_results);
        }

        game.switchTurn();
        game.undoMove(move);
    }

    return total_results;
}

pub fn perftDivide(game: *engine.Game, depth: u32) !void {
    if (depth == 0) {
        std.debug.print("Total nodes: 1\n", .{});
        return;
    }

    var total_nodes: u64 = 0;

    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    std.debug.print("\n--- Perft Divide Depth {d} ---\n", .{depth});

    for (moves[0..count]) |move| {
        try game.applyMove(move);
        game.switchTurn();

        const nodes_from_move = try perft(game, depth - 1);

        total_nodes += nodes_from_move.nodes;

        printMove(move);
        std.debug.print(": {d}\n", .{nodes_from_move.nodes});

        game.switchTurn();
        game.undoMove(move);
    }

    std.debug.print("---------------------------\n", .{});
    std.debug.print("Total Nodes at Depth {d}: {d}\n\n", .{ depth, total_nodes });
}

fn printMove(move: types.Move) void {
    const files = "abcdefgh";
    const ranks = "87654321"; // Adjusted for 0-indexed top-down board

    std.debug.print("{c}{c}{c}{c}", .{
        files[move.from[1]],
        ranks[move.from[0]],
        files[move.to[1]],
        ranks[move.to[0]],
    });

    switch (move.move_type) {
        .Promotion => std.debug.print("q", .{}),
        .Capture => std.debug.print("x", .{}),
        .EnPassant => std.debug.print("e", .{}),
        .Castling => std.debug.print("c", .{}),
        else => {},
    }
}

test "Chess Move Generation - Initial Position" {
    const allocator = std.testing.allocator;
    // White King E1, Rook H1. Path clear.
    var game = try engine.Game.init(allocator, "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1");
    defer game.deinit();

    // try perftDivide(&game, 2);

    const result1 = try perft(&game, 1);
    const result2 = try perft(&game, 2);
    const result3 = try perft(&game, 3);
    const result4 = try perft(&game, 4);
    // const result5 = try perft(&game, 5);

    // try expectEqual(14, result1.nodes);
    // try expect(result2.nodes == 191);
    // try expect(result3.nodes == 2812);
    // try expect(result4.nodes == 43238);

    std.debug.print("Depth 1: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result1.nodes, result1.captures, result1.en_passants, result1.castles, result1.promotions });
    std.debug.print("Depth 2: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result2.nodes, result2.captures, result2.en_passants, result2.castles, result2.promotions });
    std.debug.print("Depth 3: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result3.nodes, result3.captures, result3.en_passants, result3.castles, result3.promotions });
    std.debug.print("Depth 4: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result4.nodes, result4.captures, result4.en_passants, result4.castles, result4.promotions });
    // std.debug.print("Depth 4: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result5.nodes, result5.captures, result5.en_passants, result5.castles, result5.promotions });
}
