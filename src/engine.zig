const std = @import("std");
const types = @import("types.zig");
const evaluations = @import("evaluation.zig");

const MoveType = types.MoveType;

const Color = types.Color;
const Piece = types.Piece;
const Move = types.Move;
const PieceType = types.PieceType;
const CastlingRights = types.CastlingRights;
const GameStatus = types.GameStatus;

const Vec2 = struct { row: i8, col: i8 };

const king_dirs = [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = 0 }, .{ .row = 1, .col = -1 }, .{ .row = 0, .col = -1 }, .{ .row = 0, .col = 1 }, .{ .row = -1, .col = -1 }, .{ .row = -1, .col = 1 }, .{ .row = -1, .col = 0 } };
const knight_dirs = [_]Vec2{ .{ .row = 2, .col = 1 }, .{ .row = 2, .col = -1 }, .{ .row = -2, .col = 1 }, .{ .row = -2, .col = -1 }, .{ .row = 1, .col = 2 }, .{ .row = 1, .col = -2 }, .{ .row = -1, .col = 2 }, .{ .row = -1, .col = -2 } };
const rook_dirs = [_]Vec2{ .{ .row = 1, .col = 0 }, .{ .row = -1, .col = 0 }, .{ .row = 0, .col = 1 }, .{ .row = 0, .col = -1 } };
const bishop_dirs = [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = -1 }, .{ .row = -1, .col = 1 }, .{ .row = -1, .col = -1 } };
const queen_dirs = rook_dirs ++ bishop_dirs;

pub const GenMode = enum {
    All,
    CapturesOnly,
};

pub const HistoryEntry = struct {
    move: Move,
    captured_piece: ?Piece,
    old_castling_rights: CastlingRights,
    old_en_passant_pos: ?[2]u8,
    old_king_pos: [2]u8,
};

pub const Game = struct {
    board: [8][8]?Piece,
    turn: Color,
    castlingRights: CastlingRights,
    en_passant_pos: ?[2]u8,
    white_king_pos: [2]u8,
    black_king_pos: [2]u8,

    allocator: std.mem.Allocator,
    history: std.ArrayList(HistoryEntry),

    status: GameStatus = .ongoing,
    material_score: i32 = 0,

    pub fn init(allocator: std.mem.Allocator, fen: []const u8) !Game {
        var self = Game{
            .allocator = allocator,
            .board = undefined,
            .turn = .White,
            .en_passant_pos = null,
            .white_king_pos = .{ 0, 4 },
            .black_king_pos = .{ 7, 4 },
            .history = try std.ArrayList(HistoryEntry).initCapacity(allocator, 100),
            .castlingRights = .{ .white_king_side = true, .white_queen_side = true, .black_king_side = true, .black_queen_side = true },
        };
        try self.loadFen(fen);
        self.material_score = self.getFullEvaluation();

        return self;
    }

    pub fn deinit(self: *Game) void {
        self.history.deinit(self.allocator);
    }

    pub fn loadFen(self: *Game, fen: []const u8) !void {
        var iter = std.mem.splitScalar(u8, fen, ' ');
        self.board = [_][8]?Piece{[_]?Piece{null} ** 8} ** 8;
        const board_str = iter.next() orelse return error.InvalidFen;

        var row: usize = 0;
        var col: usize = 0;
        var fen_idx: usize = 0;

        while (fen_idx < board_str.len and row < 8) : (fen_idx += 1) {
            const char = board_str[fen_idx];
            if (char == ' ') break;
            if (char == '/') {
                row += 1;
                col = 0;
                continue;
            }
            if (char >= '0' and char <= '8') {
                col += char - '0';
            } else {
                const piece_type: PieceType = switch (std.ascii.toLower(char)) {
                    'p' => .Pawn,
                    'n' => .Knight,
                    'b' => .Bishop,
                    'r' => .Rook,
                    'q' => .Queen,
                    'k' => .King,
                    else => unreachable,
                };
                const color: Color = if (std.ascii.isUpper(char)) .White else .Black;
                self.board[row][col] = Piece{ .type = piece_type, .color = color };

                if (piece_type == .King) {
                    if (color == .White) self.white_king_pos = .{ @intCast(row), @intCast(col) } else self.black_king_pos = .{ @intCast(row), @intCast(col) };
                }
                col += 1;
            }
        }

        if (iter.next()) |turn_str| {
            self.turn = if (turn_str[0] == 'w') .White else .Black;
        }

        // castling rights
        if (iter.next()) |castle_str| {
            self.castlingRights = CastlingRights{ .white_king_side = false, .white_queen_side = false, .black_king_side = false, .black_queen_side = false };
            for (castle_str) |c| {
                switch (c) {
                    'K' => self.castlingRights.white_king_side = true,
                    'Q' => self.castlingRights.white_queen_side = true,
                    'k' => self.castlingRights.black_king_side = true,
                    'q' => self.castlingRights.black_queen_side = true,
                    '-' => break,
                    else => {},
                }
            }
        }

        // En passant pos
        if (iter.next()) |ep_str| {
            if (ep_str[0] == '-') {
                self.en_passant_pos = null;
            } else {
                self.en_passant_pos = .{
                    ep_str[0] - 'a',
                    8 - (ep_str[1] - '0'),
                };
            }
        }
    }

    pub fn updateStatus(self: *Game, count: usize) void {
        if (count == 0) {
            if (self.isInCheck()) {
                self.status = if (self.turn == .White) .black_wins else .white_wins;
            } else {
                self.status = .draw;
            }
        }
    }

    pub fn reset(self: *Game) void {
        self.board = [_][8]?Piece{[_]?Piece{null} ** 8} ** 8;
        self.turn = .White;
        self.status = .ongoing;
        self.castlingRights = CastlingRights{ .white_king_side = true, .white_queen_side = true, .black_king_side = true, .black_queen_side = true };
        self.en_passant_pos = null;
        self.history.clearRetainingCapacity();
    }

    pub fn switchTurn(self: *Game) void {
        self.turn = if (self.turn == .White) .Black else .White;
    }

    pub fn opponent(self: *Game) Color {
        return if (self.turn == .White) .Black else .White;
    }

    pub fn applyMove(self: *Game, move: Move) !void {
        const score_multiplier: i32 = if (self.turn == .White) 1 else -1;
        const piece = self.board[move.from[0]][move.from[1]];
        var captured: ?Piece = null;
        if (move.move_type == .EnPassant) {
            captured = self.board[move.from[0]][move.to[1]]; // Capture the pawn behind
            self.board[move.from[0]][move.to[1]] = null;
            // add the captured pst value
            self.material_score += (evaluations.getPstValue(captured.?, move.from[0], move.to[1]) + evaluations.getPieceValue(.Pawn)) * score_multiplier;
        } else {
            captured = self.board[move.to[0]][move.to[1]];
            if (captured) |p| {
                self.material_score += (evaluations.getPstValue(p, move.from[0], move.to[1]) + evaluations.getPieceValue(p.type)) * score_multiplier;
            }
        }

        // move the piece to the new square and add the pst value
        self.board[move.to[0]][move.to[1]] = piece;
        self.material_score += (evaluations.getPstValue(piece.?, move.to[0], move.to[1]) + evaluations.getPieceValue(piece.?.type)) * score_multiplier;

        // remove it from the old one and subtract the pst value
        self.board[move.from[0]][move.from[1]] = null;
        self.material_score -= (evaluations.getPstValue(piece.?, move.from[0], move.from[1]) + evaluations.getPieceValue(piece.?.type)) * score_multiplier;

        const entry = HistoryEntry{
            .move = move,
            .captured_piece = captured,
            .old_castling_rights = self.castlingRights,
            .old_en_passant_pos = self.en_passant_pos,
            .old_king_pos = if (self.turn == .White) self.white_king_pos else self.black_king_pos,
        };

        // Update King Position
        if (piece.?.type == .King) {
            if (self.turn == .White) self.white_king_pos = move.to else self.black_king_pos = move.to;
        }

        // Handle Castling moves (moving the rook)
        if (move.move_type == .Castling) {
            const row = move.to[0];
            if (move.to[1] == 6) { // King Side
                self.board[row][5] = self.board[row][7];
                self.board[row][7] = null;
            } else if (move.to[1] == 2) { // Queen Side
                self.board[row][3] = self.board[row][0];
                self.board[row][0] = null;
            }
        }

        // Handle Promotion
        if (move.move_type == .Promotion) {
            self.board[move.to[0]][move.to[1]] = Piece{ .type = move.promotion_piece.?, .color = self.turn };
        }

        // Update En Passant position
        if (move.move_type == .DoublePawnPush) {
            const ep_row = if (self.turn == .White) move.to[0] + 1 else move.to[0] - 1;
            self.en_passant_pos = .{ @intCast(ep_row), move.to[1] };
        } else {
            self.en_passant_pos = null;
        }

        self.updateCastlingRights(move);
        try self.history.append(self.allocator, entry);
    }

    pub fn undoMove(self: *Game, move: Move) void {
        const score_multiplier: i32 = if (self.turn == .White) 1 else -1;
        const entry = self.history.pop();

        // Move piece back
        if (move.piece == .King and self.turn == .Black) {}
        const moved_piece_type = if (move.move_type == .Promotion) .Pawn else move.piece;
        const moved_piece = Piece{ .type = moved_piece_type, .color = self.turn };
        self.board[move.from[0]][move.from[1]] = moved_piece;
        self.material_score += (evaluations.getPstValue(moved_piece, move.from[0], move.from[1]) + evaluations.getPieceValue(moved_piece_type)) * score_multiplier;

        // Clear destination (unless captured there)
        self.board[move.to[0]][move.to[1]] = null;
        self.material_score -= (evaluations.getPstValue(moved_piece, move.to[0], move.to[1]) + evaluations.getPieceValue(moved_piece_type)) * score_multiplier;

        // Restore captured piece
        if (move.move_type == .EnPassant) {
            // Restore pawn at the EP position
            self.board[move.from[0]][move.to[1]] = entry.?.captured_piece;
            self.material_score -= (evaluations.getPstValue(entry.?.captured_piece.?, move.from[0], move.to[1]) + evaluations.getPieceValue(.Pawn)) * score_multiplier;
        } else if (entry.?.captured_piece) |cap| {
            self.board[move.to[0]][move.to[1]] = cap;
            self.material_score -= (evaluations.getPstValue(cap, move.from[0], move.to[1]) + evaluations.getPieceValue(cap.type)) * score_multiplier;
        }

        // Revert Castling Rooks
        if (move.move_type == .Castling) {
            const row = move.to[0];
            if (move.to[1] == 6) { // King Side
                self.board[row][7] = self.board[row][5];
                self.board[row][5] = null;
            } else if (move.to[1] == 2) { // Queen Side
                self.board[row][0] = self.board[row][3];
                self.board[row][3] = null;
            }
        }

        // Restore State
        self.castlingRights = entry.?.old_castling_rights;
        self.en_passant_pos = entry.?.old_en_passant_pos;
        if (self.turn == .White) self.white_king_pos = entry.?.old_king_pos else self.black_king_pos = entry.?.old_king_pos;
    }

    fn updateCastlingRights(self: *Game, move: Move) void {
        const row = move.from[0];
        const col = move.from[1];

        if (move.move_type == .Castling) {
            if (self.turn == .White) {
                self.castlingRights.white_king_side = false;
                self.castlingRights.white_queen_side = false;
            } else {
                self.castlingRights.black_king_side = false;
                self.castlingRights.black_queen_side = false;
            }
            return;
        }

        // King moves
        if (self.board[move.to[0]][move.to[1]]) |piece| {
            if (piece.type == .King) {
                if (self.turn == .White) {
                    self.castlingRights.white_king_side = false;
                    self.castlingRights.white_queen_side = false;
                } else {
                    self.castlingRights.black_king_side = false;
                    self.castlingRights.black_queen_side = false;
                }
            }
        }

        // If Rook moves or is captured
        if (row == 0 and col == 0) self.castlingRights.black_queen_side = false;
        if (row == 0 and col == 7) self.castlingRights.black_king_side = false;
        if (row == 7 and col == 0) self.castlingRights.white_queen_side = false;
        if (row == 7 and col == 7) self.castlingRights.white_king_side = false;
    }

    // Move Generator functions
    pub fn generateLegalMoves(self: *Game, buffer: []Move, mode: GenMode) usize {
        var total: usize = 0;
        for (0..8) |r| {
            for (0..8) |c| {
                if (self.board[r][c]) |piece| {
                    if (piece.color == self.turn) {
                        switch (piece.type) {
                            .Pawn => self.getPawnMoves(r, c, buffer[0..], &total, mode),
                            .King => self.getKingMoves(r, c, buffer[0..], &total, mode),
                            .Knight => self.genKnightMoves(r, c, buffer[0..], &total, mode),
                            .Bishop => self.genSliderMoves(r, c, &bishop_dirs, .Bishop, buffer[0..], &total, mode),
                            .Rook => self.genSliderMoves(r, c, &rook_dirs, .Rook, buffer[0..], &total, mode),
                            .Queen => self.genSliderMoves(r, c, &queen_dirs, .Queen, buffer[0..], &total, mode),
                        }
                    }
                }
            }
        }
        return total;
    }

    fn isLegalMove(self: *Game, move: Move) !bool {
        try self.applyMove(move);
        const in_check = self.isInCheck();
        self.undoMove(move);

        if (in_check) return false;
        return true;
    }

    fn addMove(self: *Game, move: Move, buffer: []Move, count: *usize, mode: GenMode) void {
        const isLegal = self.isLegalMove(move) catch false;
        if (isLegal and (mode == .All or move.move_type == .Capture)) {
            buffer[count.*] = move;
            count.* += 1;
        }
    }

    fn isInBounds(r: i8, c: i8) bool {
        return r >= 0 and r < 8 and c >= 0 and c < 8;
    }

    fn getPawnMoves(self: *Game, row: usize, col: usize, buffer: []Move, count: *usize, mode: GenMode) void {
        const isWhite = self.turn == .White;
        const row_offset: i8 = if (isWhite) -1 else 1;
        var r: i8 = @intCast(row);
        const c: i8 = @intCast(col);
        r += row_offset;

        const start_row: u8 = if (isWhite) 6 else 1;
        const promotion_row: u8 = if (isWhite) 0 else 7;

        if (!isInBounds(r, c)) return;

        // Normal
        if (self.board[@intCast(r)][@intCast(c)] == null) {
            if (r == promotion_row) {
                self.addPromotionMoves(row, col, @intCast(r), @intCast(c), null, buffer, count, mode);
            } else {
                self.addMove(Move{ .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Normal, .piece = .Pawn }, buffer, count, mode);
                // Double Push
                if (row == start_row and self.board[@intCast(r + row_offset)][@intCast(c)] == null) {
                    self.addMove(Move{ .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r + row_offset), @intCast(c) }, .piece = .Pawn, .move_type = .DoublePawnPush }, buffer, count, mode);
                }
            }
        }

        // Captures
        const capture_cols = [_]i8{ c - 1, c + 1 };
        for (capture_cols) |cc| {
            if (isInBounds(r, cc)) {
                // Normal Capture
                if (self.board[@intCast(r)][@intCast(cc)]) |target| {
                    if (target.color != self.turn) {
                        if (r == promotion_row) {
                            self.addPromotionMoves(row, col, @intCast(r), @intCast(cc), target.type, buffer, count, mode);
                        } else {
                            self.addMove(Move{ .piece = .Pawn, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(cc) }, .move_type = .Capture, .captured_piece = target.type }, buffer, count, mode);
                        }
                    }
                }
                // En Passant
                if (self.en_passant_pos) |ep| {
                    if (ep[0] == r and ep[1] == cc) {
                        self.addMove(Move{ .piece = .Pawn, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(cc) }, .move_type = .EnPassant }, buffer, count, mode);
                    }
                }
            }
        }
    }

    fn addPromotionMoves(self: *Game, fr: usize, fc: usize, tr: u8, tc: u8, captured_piece: ?PieceType, buffer: []Move, count: *usize, mode: GenMode) void {
        const pieces = [_]PieceType{ .Queen, .Knight, .Rook, .Bishop };
        for (pieces) |p| {
            self.addMove(Move{ .from = .{ @intCast(fr), @intCast(fc) }, .to = .{ tr, tc }, .piece = .Pawn, .move_type = .Promotion, .promotion_piece = p, .captured_piece = captured_piece }, buffer, count, mode);
        }
    }

    fn genKnightMoves(self: *Game, row: usize, col: usize, buffer: []Move, count: *usize, mode: GenMode) void {
        for (knight_dirs) |dir| {
            const r = @as(i8, @intCast(row)) + dir.row;
            const c = @as(i8, @intCast(col)) + dir.col;
            if (isInBounds(r, c)) {
                const target = self.board[@intCast(r)][@intCast(c)];
                if (target) |nonull_target| {
                    if (nonull_target.color != self.turn) {
                        self.addMove(Move{ .piece = .Knight, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Capture, .captured_piece = nonull_target.type }, buffer, count, mode);
                    }
                } else {
                    self.addMove(Move{ .piece = .Knight, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Normal }, buffer, count, mode);
                }
            }
        }
    }

    fn getKingMoves(self: *Game, row: usize, col: usize, buffer: []Move, count: *usize, mode: GenMode) void {
        for (king_dirs) |dir| {
            const r = @as(i8, @intCast(row)) + dir.row;
            const c = @as(i8, @intCast(col)) + dir.col;
            if (isInBounds(r, c)) {
                const target = self.board[@intCast(r)][@intCast(c)];
                if (target) |nonull_target| {
                    if (nonull_target.color != self.turn) {
                        self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Capture, .captured_piece = nonull_target.type }, buffer, count, mode);
                    }
                } else {
                    self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Normal }, buffer, count, mode);
                }
            }
        }

        // Castling
        if (self.turn == .White) {
            if (self.castlingRights.white_king_side and self.board[7][5] == null and self.board[7][6] == null) {
                if (!self.isSquareAttacked(.{ 7, 4 }, .Black) and !self.isSquareAttacked(.{ 7, 5 }, .Black) and !self.isSquareAttacked(.{ 7, 6 }, .Black)) {
                    self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ 7, 6 }, .move_type = .Castling }, buffer, count, mode);
                }
            }
            if (self.castlingRights.white_queen_side and self.board[7][1] == null and self.board[7][2] == null and self.board[7][3] == null) {
                if (!self.isSquareAttacked(.{ 7, 4 }, .Black) and !self.isSquareAttacked(.{ 7, 3 }, .Black) and !self.isSquareAttacked(.{ 7, 2 }, .Black)) {
                    self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ 7, 2 }, .move_type = .Castling }, buffer, count, mode);
                }
            }
        } else {
            if (self.castlingRights.black_king_side and self.board[0][5] == null and self.board[0][6] == null) {
                if (!self.isSquareAttacked(.{ 0, 4 }, .White) and !self.isSquareAttacked(.{ 0, 5 }, .White) and !self.isSquareAttacked(.{ 0, 6 }, .White)) {
                    self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ 0, 6 }, .move_type = .Castling }, buffer, count, mode);
                }
            }
            if (self.castlingRights.black_queen_side and self.board[0][1] == null and self.board[0][2] == null and self.board[0][3] == null) {
                if (!self.isSquareAttacked(.{ 0, 4 }, .White) and !self.isSquareAttacked(.{ 0, 3 }, .White) and !self.isSquareAttacked(.{ 0, 2 }, .White)) {
                    self.addMove(Move{ .piece = .King, .from = .{ @intCast(row), @intCast(col) }, .to = .{ 0, 2 }, .move_type = .Castling }, buffer, count, mode);
                }
            }
        }
    }

    fn genSliderMoves(self: *Game, row: usize, col: usize, dirs: []const Vec2, piece_type: PieceType, buffer: []Move, count: *usize, mode: GenMode) void {
        for (dirs) |dir| {
            var r = @as(i8, @intCast(row));
            var c = @as(i8, @intCast(col));
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;

                const target = self.board[@intCast(r)][@intCast(c)];
                if (target) |piece| {
                    if (piece.color != self.turn) {
                        self.addMove(Move{ .piece = piece_type, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Capture, .captured_piece = piece.type }, buffer, count, mode);
                    }
                    break;
                }
                self.addMove(Move{ .piece = piece_type, .from = .{ @intCast(row), @intCast(col) }, .to = .{ @intCast(r), @intCast(c) }, .move_type = .Normal }, buffer, count, mode);
            }
        }
    }

    pub fn isSquareAttacked(self: *Game, target: [2]u8, attacker: Color) bool {
        const pawn_dir: i8 = if (attacker == .White) 1 else -1;

        const r_pawn = @as(i8, @intCast(target[0])) + pawn_dir;
        if (r_pawn >= 0 and r_pawn < 8) {
            if (target[1] > 0) {
                if (self.board[@intCast(r_pawn)][target[1] - 1]) |p| {
                    if (p.color == attacker and p.type == .Pawn) return true;
                }
            }
            if (target[1] < 7) {
                if (self.board[@intCast(r_pawn)][target[1] + 1]) |p| {
                    if (p.color == attacker and p.type == .Pawn) return true;
                }
            }
        }

        for (knight_dirs) |dir| {
            const r = @as(i8, @intCast(target[0])) + dir.row;
            const c = @as(i8, @intCast(target[1])) + dir.col;
            if (isInBounds(r, c)) {
                if (self.board[@intCast(r)][@intCast(c)]) |p| {
                    if (p.color == attacker and p.type == .Knight) return true;
                }
            }
        }

        for (rook_dirs) |dir| {
            var r = @as(i8, @intCast(target[0]));
            var c = @as(i8, @intCast(target[1]));
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;
                if (self.board[@intCast(r)][@intCast(c)]) |p| {
                    if (p.color == attacker and (p.type == .Rook or p.type == .Queen)) return true;
                    break;
                }
            }
        }

        for (bishop_dirs) |dir| {
            var r = @as(i8, @intCast(target[0]));
            var c = @as(i8, @intCast(target[1]));
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;
                if (self.board[@intCast(r)][@intCast(c)]) |p| {
                    if (p.color == attacker and (p.type == .Bishop or p.type == .Queen)) return true;
                    break;
                }
            }
        }

        for (king_dirs) |dir| {
            const r = @as(i8, @intCast(target[0])) + dir.row;
            const c = @as(i8, @intCast(target[1])) + dir.col;
            if (isInBounds(r, c)) {
                if (self.board[@intCast(r)][@intCast(c)]) |p| {
                    if (p.color == attacker and p.type == .King) return true;
                }
            }
        }

        return false;
    }

    pub fn isInCheck(self: *Game) bool {
        const king_pos = if (self.turn == .White) self.white_king_pos else self.black_king_pos;
        return self.isSquareAttacked(king_pos, self.opponent());
    }

    // Evaluations
    pub fn getBestMove(self: *Game) !Move {
        var best_move: Move = undefined;
        var best_score: i32 = -500000;
        var alpha: i32 = -500000;
        const beta: i32 = 500000;
        var searchContext = evaluations.SearchContext.init();

        var root_moves: [218]Move = undefined;
        const count = self.generateLegalMoves(&root_moves, .All);

        for (root_moves[0..count]) |move| {
            try self.applyMove(move);
            self.switchTurn();

            const score: i32 = -try evaluations.negamax(self, &searchContext, 4, 1, -beta, -alpha);

            self.switchTurn();
            self.undoMove(move);

            if (score > best_score) {
                best_score = score;
                best_move = move;
            }
            if (score > alpha) alpha = score;
        }
        return best_move;
    }

    pub fn getGameStage(self: *Game) types.GameStage {
        if (self.history.items.len < 15) {
            return .Opening;
        } else if (self.history.items.len < 40) {
            return .Midgame;
        } else {
            return .Endgame;
        }
    }

    pub fn evaluate(self: *Game) i32 {
        return if (self.turn == .White) self.material_score else -self.material_score;
    }

    pub fn getFullEvaluation(self: *Game) i32 {
        var score: i32 = 0;

        for (self.board, 0..) |row, row_idx| {
            for (row, 0..) |piece, col_idx| {
                if (piece) |p| {
                    const pst_value = evaluations.getPstValue(p, @intCast(row_idx), @intCast(col_idx));
                    if (p.color == .White) {
                        score += evaluations.getPieceValue(p.type) + pst_value;
                    } else {
                        score -= evaluations.getPieceValue(p.type) + pst_value;
                    }
                }
            }
        }
        return score;
    }
};
