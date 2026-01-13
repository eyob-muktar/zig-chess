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
    var alpha_mutable = alpha;
    if (depth == 0) return try quiescenceSearch(game, alpha, beta);

    var moves: [218]types.Move = undefined;
    const count = game.generateLegalMoves(&moves, .All);

    if (count == 0) {
        if (game.isInCheck()) {
            return -400000 + @as(i32, ply);
        } else {
            return 0;
        }
    }

    var scores: [218]i32 = undefined;
    for (moves[0..count], 0..count) |move, i| {
        scores[i] = scoreMove(context, move, ply);
    }

    for (0..count) |i| {
        // find the highest score from the reamaining moves
        var best_idx = i;
        for (i + 1..count) |j| {
            if (scores[j] > scores[best_idx]) {
                best_idx = j;
            }
        }

        // swap the best remaining move to the current position
        const temp_m = moves[i];
        moves[i] = moves[best_idx];
        moves[best_idx] = temp_m;

        const temp_s = scores[i];
        scores[i] = scores[best_idx];
        scores[best_idx] = temp_s;

        try game.applyMove(moves[i], false);
        game.switchTurn();

        const score = -try negamax(game, context, depth - 1, ply + 1, -beta, -alpha_mutable);

        game.switchTurn();
        game.undoMove(moves[i], false);

        if (score >= beta) {
            if (moves[i].move_type != .Capture) {
                context.killer_table.add(moves[i], ply);
            }
            return beta;
        }
        if (score > alpha_mutable) alpha_mutable = score;
    }

    return alpha_mutable;
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

fn sortCaptures(moves: []types.Move) void {
    for (0..moves.len) |i| {
        var best_idx = i;
        var best_score: i32 = -1;

        for (i..moves.len) |j| {
            const move = moves[j];
            const victim_value = if (move.captured_piece) |piece| getPieceValue(piece) else getPieceValue(.Pawn);
            const attacker_value = getPieceValue(move.piece);

            const score = (victim_value * 10) - attacker_value;

            if (score > best_score) {
                best_score = score;
                best_idx = j;
            }
        }

        // swap best move to front
        const temp = moves[i];
        moves[i] = moves[best_idx];
        moves[best_idx] = temp;
    }
}

fn quiescenceSearch(game: *engine.Game, alpha: i32, beta: i32) !i32 {
    var alpha_mutable = alpha;
    const static_eval: i32 = game.evaluate();

    if (static_eval >= beta) return beta;
    if (static_eval > alpha_mutable) alpha_mutable = static_eval;

    var captures: [64]types.Move = undefined;
    const count = game.generateLegalMoves(&captures, .CapturesOnly);

    sortCaptures(captures[0..count]);

    for (captures[0..count]) |move| {
        try game.applyMove(move, false);
        game.switchTurn();

        const score = -try quiescenceSearch(game, -beta, -alpha_mutable);

        game.switchTurn();
        game.undoMove(move, false);

        if (score >= beta) return beta;
        if (score > alpha_mutable) alpha_mutable = score;
    }

    return alpha_mutable;
}

pub fn getPstValue(piece: types.Piece, row: u8, col: u8) i32 {
    const pst_row = if (piece.color == .Black) 7 - row else row;
    const value = switch (piece.type) {
        .Pawn => PAWN_PST[pst_row][col],
        .Knight => KNIGHT_PST[pst_row][col],
        .Bishop => BISHOP_PST[pst_row][col],
        .Rook => ROOK_PST[pst_row][col],
        .Queen => QUEEN_PST[pst_row][col],
        .King => KING_MIDDLE_GAME_PST[pst_row][col],
    };

    return value;
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
