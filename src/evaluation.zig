const std = @import("std");
const types = @import("types.zig");
const engine = @import("engine.zig");

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

pub fn negamax(game: *engine.Game, depth: u8, alpha: i32, beta: i32) !i32 {
    var alpha_param = alpha;
    if (depth == 0) {
        const multiplier: i32 = if (game.turn == .White) 1 else -1;
        return game.evaluate() * multiplier;
    }

    var best_score: i32 = -500000;

    _ = try game.generateLegalMoves();
    if (game.move_count == 0) {
        if (game.isInCheck()) {
            return -400000 + @as(i32, depth);
        } else {
            // Stalemate: Return 0 (Draw)
            return 0;
        }
    }

    // Copy to local stack (to avoid recursion corruption)
    var root_moves: [218]types.Move = undefined;
    @memcpy(root_moves[0..game.move_count], game.moves[0..game.move_count]);

    for (root_moves[0..game.move_count]) |move| {
        try game.applyMove(move);
        try game.switchTurn();

        const score = -try negamax(game, depth - 1, -beta, -alpha_param);

        try game.switchTurn();
        game.undoMove(move);

        if (score > best_score) {
            best_score = score;
            if (score > alpha_param) alpha_param = score;
        }
        if (score >= beta) return best_score;
    }

    return best_score;
}
