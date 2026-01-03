const std = @import("std");
const types = @import("types.zig");
const engine = @import("engine.zig");

const Move = types.Move;
pub const MAX_DEPTH = 64;

pub const KillerTable = struct {
    moves: [MAX_DEPTH][2]?Move,

    pub fn init() KillerTable {
        return .{ .moves = [_][2]?Move{[_]?Move{ null, null }} ** 64 };
    }

    pub fn add(self: *KillerTable, move: Move, ply: usize) void {
        if (move.move_type == .Capture) return;

        if (std.meta.eql(self.moves[ply][0], move)) return;

        self.moves[ply][1] = self.moves[ply][0];
        self.moves[ply][0] = move;
    }
};

pub const PAWN_PST = [8][8]i16{
    .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 50, 50, 50, 50, 50, 50, 50, 50 },
    .{ 10, 10, 20, 30, 30, 20, 10, 10 },
    .{ 5, 5, 10, 25, 25, 10, 5, 5 },
    .{ 0, 0, 0, 20, 20, 0, 0, 0 },
    .{ 5, -5, -10, 0, 0, -10, -5, 5 },
    .{ 5, 10, 10, -20, -20, 10, 10, 5 },
    .{ 0, 0, 0, 0, 0, 0, 0, 0 },
};

pub const KNIGHT_PST = [8][8]i16{
    .{ -50, -40, -30, -30, -30, -30, -40, -50 },
    .{ -40, -20, 0, 0, 0, 0, -20, -40 },
    .{ -30, 0, 10, 15, 15, 10, 0, -30 },
    .{ -30, 5, 15, 20, 20, 15, 5, -30 },
    .{ -30, 0, 15, 20, 20, 15, 0, -30 },
    .{ -30, 5, 10, 15, 15, 10, 5, -30 },
    .{ -40, -20, 0, 5, 5, 0, -20, -40 },
    .{ -50, -40, -30, -30, -30, -30, -40, -50 },
};

pub const BISHOP_PST = [8][8]i16{
    .{ -20, -10, -10, -10, -10, -10, -10, -20 },
    .{ -10, 0, 0, 0, 0, 0, 0, -10 },
    .{ -10, 0, 5, 10, 10, 5, 0, -10 },
    .{ -10, 5, 5, 10, 10, 5, 5, -10 },
    .{ -10, 0, 10, 10, 10, 10, 0, -10 },
    .{ -10, 10, 10, 10, 10, 10, 10, -10 },
    .{ -10, 5, 0, 0, 0, 0, 5, -10 },
    .{ -20, -10, -10, -10, -10, -10, -10, -20 },
};

pub const ROOK_PST = [8][8]i16{
    .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    .{ 5, 10, 10, 10, 10, 10, 10, 5 },
    .{ -5, 0, 0, 0, 0, 0, 0, -5 },
    .{ -5, 0, 0, 0, 0, 0, 0, -5 },
    .{ -5, 0, 0, 0, 0, 0, 0, -5 },
    .{ -5, 0, 0, 0, 0, 0, 0, -5 },
    .{ -5, 0, 0, 0, 0, 0, 0, -5 },
    .{ 0, 0, 0, 5, 5, 0, 0, 0 },
};

pub const QUEEN_PST = [8][8]i16{
    .{ -20, -10, -10, -5, -5, -10, -10, -20 },
    .{ -10, 0, 0, 0, 0, 0, 0, -10 },
    .{ -10, 0, 5, 5, 5, 5, 0, -10 },
    .{ -5, 0, 5, 5, 5, 5, 0, -5 },
    .{ 0, 0, 5, 5, 5, 5, 0, -5 },
    .{ -10, 5, 5, 5, 5, 5, 0, -10 },
    .{ -10, 0, 5, 0, 0, 0, 0, -10 },
    .{ -20, -10, -10, -5, -5, -10, -10, -20 },
};

pub const KING_MIDDLE_GAME_PST = [8][8]i16{
    .{ -30, -40, -40, -50, -50, -40, -40, -30 },
    .{ -30, -40, -40, -50, -50, -40, -40, -30 },
    .{ -30, -40, -40, -50, -50, -40, -40, -30 },
    .{ -30, -40, -40, -50, -50, -40, -40, -30 },
    .{ -20, -30, -30, -40, -40, -30, -30, -20 },
    .{ -10, -20, -20, -20, -20, -20, -20, -10 },
    .{ 20, 20, 0, 0, 0, 0, 20, 20 },
    .{ 20, 30, 10, 0, 0, 10, 30, 20 },
};

pub const KING_END_GAME_PST = [8][8]i16{
    .{ -50, -40, -30, -20, -20, -30, -40, -50 },
    .{ -30, -20, -10, 0, 0, -10, -20, -30 },
    .{ -30, -10, 20, 30, 30, 20, -10, -30 },
    .{ -30, -10, 30, 40, 40, 30, -10, -30 },
    .{ -30, -10, 30, 40, 40, 30, -10, -30 },
    .{ -30, -10, 20, 30, 30, 20, -10, -30 },
    .{ -30, -30, 0, 0, 0, 0, -30, -30 },
    .{ -50, -30, -30, -30, -30, -30, -30, -50 },
};

pub const SearchContext = struct {
    killer_table: KillerTable,
    history_table: [2][64][64]i32,
    nodes_searched: u64,
    timer: std.time.Timer,

    pub fn init() SearchContext {
        return .{
            .killer_table = KillerTable.init(),
            .nodes_searched = 0,
            .timer = std.time.Timer.start() catch unreachable,
            .history_table = [_][64][64]i32{[_][64]i32{[_]i32{0} ** 64} ** 64} ** 2,
        };
    }
};

pub fn negamax(game: *engine.Game, context: *SearchContext, depth: u8, ply: u8, alpha: i32, beta: i32) !i32 {
    var alpha_param = alpha;
    if (depth == 0) {
        const multiplier: i32 = if (game.turn == .White) 1 else -1;
        return game.evaluate() * multiplier;
    }

    try game.generateLegalMoves();
    const count = game.move_count;

    if (count == 0) {
        if (game.isInCheck()) {
            return -400000 + @as(i32, ply);
        } else {
            return 0;
        }
    }

    // Copy to local stack (to avoid recursion corruption)
    var moves: [218]types.Move = undefined;
    @memcpy(moves[0..count], game.moves[0..count]);

    var scores: [256]i32 = undefined;
    for (moves[0..count], 0..count) |move, i| {
        scores[i] = scoreMove(context, move, ply);
    }

    for (0..count) |i| {
        // Find the highest score from the REMAINING moves
        var best_idx = i;
        for (i + 1..count) |j| {
            if (scores[j] > scores[best_idx]) {
                best_idx = j;
            }
        }

        // Swap the best remaining move to the current position
        const temp_m = moves[i];
        moves[i] = moves[best_idx];
        moves[best_idx] = temp_m;

        const temp_s = scores[i];
        scores[i] = scores[best_idx];
        scores[best_idx] = temp_s;

        try game.applyMove(moves[i]);
        try game.switchTurn();

        const score = -try negamax(game, context, depth - 1, ply + 1, -beta, -alpha_param);

        try game.switchTurn();
        game.undoMove(moves[i]);

        if (score >= beta) {
            if (moves[i].move_type != .Capture) {
                context.killer_table.add(moves[i], ply);
            }
            return beta;
        }
        if (score > alpha_param) alpha_param = score;
    }

    return alpha_param;
}

pub fn scoreMove(context: *SearchContext, move: types.Move, ply: usize) i32 {
    if (move.move_type == .Capture) {
        const victim_value = if (move.captured_piece) |piece| getPieceValue(piece) else getPieceValue(.Pawn);
        const attacker_value = getPieceValue(move.piece);

        return 10000 + (victim_value * 10) - attacker_value;
    }

    if (move.move_type == .Promotion) {
        return 8000;
    }
    if (context.killer_table.moves[ply][0]) |m1| {
        if (std.meta.eql(move, m1)) return 9000;
    }
    if (context.killer_table.moves[ply][1]) |m2| {
        if (std.meta.eql(move, m2)) return 8000;
    }

    return 0;
}

pub fn getPieceValue(piece: types.PieceType) i32 {
    return switch (piece) {
        .Pawn => 100,
        .Knight => 300,
        .Bishop => 300,
        .Rook => 500,
        .Queen => 900,
        .King => 2000,
    };
}
