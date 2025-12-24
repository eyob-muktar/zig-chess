const std = @import("std");
const rl = @import("raylib");

const BLOCKS = 8;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 800;
const BLOCK_SIZE: i32 = SCREEN_WIDTH / BLOCKS;

const initial_board = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";
const test_board = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1";
const test2_board = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq -";
const test3_board = "r2q1rk1/pP1p2pp/Q4n2/bbp1p3/Np6/1B3NBn/pPPP1PPP/R3K2R b KQ - 0 1";

const Color = enum { White, Black };
const PieceType = enum { Pawn, Knight, Bishop, Rook, Queen, King };

const Piece = struct { type: PieceType, color: Color };

const CastlingRights = packed struct(u4) {
    white_king_side: bool,
    white_queen_side: bool,
    black_king_side: bool,
    black_queen_side: bool,
};

const MoveType = enum(u3) {
    Normal,
    Capture,
    DoublePawnPush, // For En Passant tracking
    EnPassant, // Capture where the target isn't on the 'to' square
    Castling,
    Promotion,
};

const Move = struct {
    from: [2]u8,
    to: [2]u8,
    move_type: MoveType,
    promotion_piece: ?PieceType = null,
};

const HistoryEntry = struct {
    move: Move,
    captured_piece: ?Piece,
    old_castling_rights: CastlingRights,
    old_en_passant_pos: ?[2]u8,
    old_king_pos: [2]u8,
    half_move_clock: u32,
};

const PieceAssets = struct {
    textures: [2][6]rl.Texture2D,

    pub fn init() !PieceAssets {
        var pa = PieceAssets{ .textures = undefined };
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.Pawn)] = try loadTextureFromImage("assets/bp.png");
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.Knight)] = try loadTextureFromImage("assets/bn.png");
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.Bishop)] = try loadTextureFromImage("assets/bb.png");
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.Rook)] = try loadTextureFromImage("assets/br.png");
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.Queen)] = try loadTextureFromImage("assets/bq.png");
        pa.textures[@intFromEnum(Color.Black)][@intFromEnum(PieceType.King)] = try loadTextureFromImage("assets/bk.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.Pawn)] = try loadTextureFromImage("assets/wp.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.Knight)] = try loadTextureFromImage("assets/wn.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.Bishop)] = try loadTextureFromImage("assets/wb.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.Rook)] = try loadTextureFromImage("assets/wr.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.Queen)] = try loadTextureFromImage("assets/wq.png");
        pa.textures[@intFromEnum(Color.White)][@intFromEnum(PieceType.King)] = try loadTextureFromImage("assets/wk.png");
        return pa;
    }

    pub fn getTexture(self: PieceAssets, piece: Piece) rl.Texture2D {
        const color_idx = @intFromEnum(piece.color);
        const type_idx = @intFromEnum(piece.type);
        return self.textures[color_idx][type_idx];
    }

    pub fn deinit(self: *PieceAssets) void {
        for (0..2) |color_idx| {
            for (0..6) |type_idx| {
                rl.unloadTexture(self.textures[color_idx][type_idx]);
            }
        }
    }
};

const Vec2 = struct { row: i8, col: i8 };

const king_dirs = [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = 0 }, .{ .row = 1, .col = -1 }, .{ .row = 0, .col = -1 }, .{ .row = 0, .col = 1 }, .{ .row = -1, .col = -1 }, .{ .row = -1, .col = 1 }, .{ .row = -1, .col = 0 } };
const knight_dirs = [_]Vec2{ .{ .row = 2, .col = 1 }, .{ .row = 2, .col = -1 }, .{ .row = -2, .col = 1 }, .{ .row = -2, .col = -1 }, .{ .row = 1, .col = 2 }, .{ .row = 1, .col = -2 }, .{ .row = -1, .col = 2 }, .{ .row = -1, .col = -2 } };
const rook_dirs = [_]Vec2{ .{ .row = 1, .col = 0 }, .{ .row = -1, .col = 0 }, .{ .row = 0, .col = 1 }, .{ .row = 0, .col = -1 } };
const bishop_dirs = [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = -1 }, .{ .row = -1, .col = 1 }, .{ .row = -1, .col = -1 } };
const queen_dirs = rook_dirs ++ bishop_dirs;

fn isInBounds(row: i8, col: i8) bool {
    return row >= 0 and row < 8 and col >= 0 and col < 8;
}

fn buildInitialBoard() [8][8]?Piece {
    var init_board: [8][8]?Piece = [1][8]?Piece{[_]?Piece{null} ** 8} ** 8;
    const back_row = [_]PieceType{ .Rook, .Knight, .Bishop, .Queen, .King, .Bishop, .Knight, .Rook };

    for (back_row, 0..) |p_type, col| {
        init_board[0][col] = Piece{ .type = p_type, .color = .White };
        init_board[7][col] = Piece{ .type = p_type, .color = .Black };
    }

    for (0..8) |col| {
        init_board[1][col] = Piece{ .type = .Pawn, .color = .White };
        init_board[6][col] = Piece{ .type = .Pawn, .color = .Black };
    }
    return init_board;
}

const GameState = struct {
    board: [8][8]?Piece,
    selectedSquare: ?[2]u8,
    turn: Color,
    moveInProgress: bool,
    promotionInProgress: bool,
    allLegalMoves: [218]Move,
    allLegalMoveCount: u8,
    castlingRights: CastlingRights,
    allocator: std.mem.Allocator,
    history: std.ArrayList(HistoryEntry),
    en_passant_pos: ?[2]u8,
    black_king_pos: [2]u8,
    white_king_pos: [2]u8,

    fn init(allocator: std.mem.Allocator, fen: []const u8) !GameState {
        var game_state = GameState{
            .allocator = allocator,
            .board = buildInitialBoard(),
            .selectedSquare = null,
            .turn = Color.White,
            .moveInProgress = false,
            .promotionInProgress = false,
            .allLegalMoves = [_]Move{undefined} ** 218,
            .allLegalMoveCount = 0,
            .history = try std.ArrayList(HistoryEntry).initCapacity(allocator, 100),
            .castlingRights = CastlingRights{ .white_king_side = true, .white_queen_side = true, .black_king_side = true, .black_queen_side = true },
            .en_passant_pos = null,
            .black_king_pos = [2]u8{ 7, 4 },
            .white_king_pos = [2]u8{ 0, 4 },
        };
        try game_state.loadFen(fen);
        try game_state.calculateAllLegalMoves();
        return game_state;
    }

    fn deinit(self: *GameState) void {
        self.history.deinit(self.allocator);
    }

    fn loadFen(self: *GameState, fen: []const u8) !void {
        var iter = std.mem.splitScalar(u8, fen, ' ');

        // board
        const board_str = iter.next() orelse return error.InvalidFen;
        self.buildBoardFromFen(board_str);

        // turn
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
                // Convert "e3" string to your Vec2 coordinate
                self.en_passant_pos = .{
                    ep_str[0] - 'a',
                    8 - (ep_str[1] - '0'),
                };
            }
        }
    }

    fn buildBoardFromFen(self: *GameState, fen: []const u8) void {
        // initiate the board with all null
        var board: [8][8]?Piece = [_][8]?Piece{[_]?Piece{null} ** 8} ** 8;
        var row: u8 = 7;
        var col: u8 = 0;
        for (fen) |char| {
            if (char == '/') {
                row -= 1;
                col = 0;
                continue;
            }
            if (char >= '0' and char <= '9') {
                col += char - '0';
                continue;
            }

            const piece = switch (char) {
                'p' => Piece{ .type = .Pawn, .color = .Black },
                'P' => Piece{ .type = .Pawn, .color = .White },
                'r' => Piece{ .type = .Rook, .color = .Black },
                'R' => Piece{ .type = .Rook, .color = .White },
                'n' => Piece{ .type = .Knight, .color = .Black },
                'N' => Piece{ .type = .Knight, .color = .White },
                'b' => Piece{ .type = .Bishop, .color = .Black },
                'B' => Piece{ .type = .Bishop, .color = .White },
                'q' => Piece{ .type = .Queen, .color = .Black },
                'Q' => Piece{ .type = .Queen, .color = .White },
                'k' => Piece{ .type = .King, .color = .Black },
                'K' => Piece{ .type = .King, .color = .White },
                else => null,
            };

            if (piece) |p| {
                board[row][col] = p;
                if (p.type == .King) {
                    if (p.color == .White) {
                        self.white_king_pos = .{ row, col };
                    } else {
                        self.black_king_pos = .{ row, col };
                    }
                }
                col += 1;
            }
        }

        self.board = board;
    }
    fn switchTurn(self: *GameState) !void {
        self.turn = if (self.turn == Color.White) Color.Black else Color.White;
        self.moveInProgress = false;
        self.selectedSquare = null;
        try self.calculateAllLegalMoves();
    }

    fn applyMove(self: *GameState, move: Move) !HistoryEntry {
        var target = self.board[move.to[0]][move.to[1]];
        if (move.move_type == .EnPassant) {
            target = self.board[move.from[0]][move.to[1]];
            self.board[move.from[0]][move.to[1]] = null;
        }
        const king_pos_to_save = if (self.turn == .White) self.white_king_pos else self.black_king_pos;

        const piece = self.board[move.from[0]][move.from[1]];
        // update king positions
        if (piece) |nonull_piece| {
            if (nonull_piece.type == .King) {
                if (nonull_piece.color == .White) self.white_king_pos = move.to else self.black_king_pos = move.to;
            }
        }
        // handle castling
        if (move.move_type == .Castling) {
            if (move.to[1] == 6) {
                // king side castling
                self.board[move.to[0]][5] = self.board[move.to[0]][7];
                self.board[move.to[0]][7] = null;
            } else if (move.to[1] == 2) {
                // queen side castling
                self.board[move.to[0]][3] = self.board[move.to[0]][0];
                self.board[move.to[0]][0] = null;
            }
        }
        self.board[move.to[0]][move.to[1]] = self.board[move.from[0]][move.from[1]];
        self.board[move.from[0]][move.from[1]] = null;

        // handle promotion
        if (move.move_type == .Promotion) {
            if (move.promotion_piece) |nonull_promotion_piece| {
                self.board[move.to[0]][move.to[1]] = Piece{ .type = nonull_promotion_piece, .color = self.turn };
            }
        }

        const history_entry = HistoryEntry{
            .move = move,
            .captured_piece = target,
            .old_castling_rights = self.castlingRights,
            .half_move_clock = 0,
            .old_en_passant_pos = self.en_passant_pos,
            .old_king_pos = king_pos_to_save,
        };

        // update en passant position
        if (move.move_type == .DoublePawnPush) {
            self.en_passant_pos = if (self.turn == Color.White) .{ move.to[0] - 1, move.to[1] } else .{ move.to[0] + 1, move.to[1] };
        } else {
            self.en_passant_pos = null;
        }

        try self.history.append(self.allocator, history_entry);
        self.updateCastlingRights(move);
        return history_entry;
    }

    fn undoMove(self: *GameState, move: Move) !void {
        const history_entry = self.history.pop();
        if (history_entry) |entry| {
            self.board[move.from[0]][move.from[1]] = self.board[move.to[0]][move.to[1]];
            if (move.move_type == .EnPassant) {
                self.board[move.to[0]][move.to[1]] = null;
                self.board[move.from[0]][move.to[1]] = entry.captured_piece;
            } else if (move.move_type == .Castling) {
                self.board[move.to[0]][move.to[1]] = null;
                if (move.to[1] == 6) {
                    // king side castling
                    self.board[move.to[0]][7] = self.board[move.to[0]][5];
                    self.board[move.to[0]][5] = null;
                } else if (move.to[1] == 2) {
                    // queen side castling
                    self.board[move.to[0]][0] = self.board[move.to[0]][3];
                    self.board[move.to[0]][3] = null;
                }
            } else if (move.move_type == .Promotion) {
                self.board[move.to[0]][move.to[1]] = entry.captured_piece;
                self.board[move.from[0]][move.from[1]] = Piece{ .type = .Pawn, .color = self.turn };
            } else {
                self.board[move.to[0]][move.to[1]] = entry.captured_piece;
            }

            // revert king positions
            if (self.turn == .White) {
                self.white_king_pos = entry.old_king_pos;
            } else {
                self.black_king_pos = entry.old_king_pos;
            }

            // revert castling rights & en passant position
            self.castlingRights = entry.old_castling_rights;
            self.en_passant_pos = entry.old_en_passant_pos;
        }
    }

    fn calculateAllLegalMoves(self: *GameState) !void {
        self.allLegalMoveCount = 0;
        self.allLegalMoves = [_]Move{undefined} ** 218;
        for (self.board, 0..) |row, row_idx| {
            for (row, 0..) |col, col_idx| {
                if (col) |piece| {
                    if (piece.color != self.turn) continue;
                    switch (piece.type) {
                        .Pawn => self.getPawnMoves(row_idx, col_idx),
                        .Knight => self.genKnightMoves(row_idx, col_idx),
                        .Bishop => self.genSliderMoves(row_idx, col_idx, &bishop_dirs),
                        .Rook => self.genSliderMoves(row_idx, col_idx, &rook_dirs),
                        .Queen => self.genSliderMoves(row_idx, col_idx, &queen_dirs),
                        .King => self.getKingMoves(row_idx, col_idx),
                    }
                }
            }
        }

        try self.filterAllLegalMoves();
    }

    fn filterAllLegalMoves(self: *GameState) !void {
        const attacker_color = if (self.turn == Color.White) Color.Black else Color.White;
        const king_pos = if (self.turn == Color.White) self.white_king_pos else self.black_king_pos;
        var idx: usize = 0;
        while (idx < self.allLegalMoveCount) {
            const move = self.allLegalMoves[idx];
            _ = try self.applyMove(move);
            var target = king_pos;

            if (move.from[0] == king_pos[0] and move.from[1] == king_pos[1]) {
                target[0] = move.to[0];
                target[1] = move.to[1];
            }

            if (self.isSquareAttacked(target, attacker_color)) {
                self.allLegalMoves[idx] = self.allLegalMoves[self.allLegalMoveCount - 1];
                self.allLegalMoveCount -= 1;
            } else {
                idx += 1;
            }
            try self.undoMove(move);
        }
    }

    fn updateCastlingRights(self: *GameState, move: Move) void {
        const piece = self.board[move.to[0]][move.to[1]];
        if (piece) |p| {
            if (p.type == .King) {
                if (self.turn == Color.White) {
                    self.castlingRights.white_king_side = false;
                    self.castlingRights.white_queen_side = false;
                } else {
                    self.castlingRights.black_king_side = false;
                    self.castlingRights.black_queen_side = false;
                }
            }

            if (p.type == .Rook) {
                const col = move.from[1];
                if (col == 0) {
                    if (self.turn == .White) {
                        self.castlingRights.white_queen_side = false;
                    } else {
                        self.castlingRights.black_queen_side = false;
                    }
                } else if (col == 7) {
                    if (self.turn == .White) {
                        self.castlingRights.white_king_side = false;
                    } else {
                        self.castlingRights.black_king_side = false;
                    }
                }
            }
        }
    }

    fn getKingMoves(self: *GameState, row: usize, col: usize) void {
        for (king_dirs) |dir| {
            var r: i8 = @intCast(row);
            var c: i8 = @intCast(col);
            r += dir.row;
            c += dir.col;
            if (isInBounds(r, c)) {
                if (self.board[@intCast(r)][@intCast(c)] != null) {
                    if (self.board[@intCast(r)][@intCast(c)].?.color == self.turn) continue;
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ @intCast(r), @intCast(c) },
                        .move_type = .Capture,
                    };
                    self.allLegalMoveCount += 1;
                    continue;
                }
                self.allLegalMoves[self.allLegalMoveCount] = Move{
                    .from = .{ @intCast(row), @intCast(col) },
                    .to = .{ @intCast(r), @intCast(c) },
                    .move_type = .Normal,
                };
                self.allLegalMoveCount += 1;
            }
        }

        if (self.turn == .White) {
            if (self.isSquareAttacked(.{ 0, 4 }, .Black)) return;
            if (self.castlingRights.white_king_side and self.board[0][5] == null and self.board[0][6] == null) {
                if (!self.isSquareAttacked(.{ 0, 5 }, .Black) and !self.isSquareAttacked(.{ 0, 6 }, .Black)) {
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ 0, 6 },
                        .move_type = .Castling,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
            if (self.castlingRights.white_queen_side and self.board[0][1] == null and self.board[0][2] == null and self.board[0][3] == null) {
                if (!self.isSquareAttacked(.{ 0, 2 }, .Black) and !self.isSquareAttacked(.{ 0, 3 }, .Black)) {
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ 0, 2 },
                        .move_type = .Castling,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
        } else {
            if (self.isSquareAttacked(.{ 7, 4 }, .White)) return;
            if (self.castlingRights.black_king_side and self.board[7][5] == null and self.board[7][6] == null) {
                if (!self.isSquareAttacked(.{ 7, 5 }, .White) and !self.isSquareAttacked(.{ 7, 6 }, .White)) {
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ 7, 6 },
                        .move_type = .Castling,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
            if (self.castlingRights.black_queen_side and self.board[7][1] == null and self.board[7][2] == null and self.board[7][3] == null) {
                if (!self.isSquareAttacked(.{ 7, 2 }, .White) and !self.isSquareAttacked(.{ 7, 3 }, .White)) {
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ 7, 2 },
                        .move_type = .Castling,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
        }
    }

    fn getPawnMoves(self: *GameState, row: usize, col: usize) void {
        const isWhite = self.turn == Color.White;
        const row_offset: i8 = if (isWhite) 1 else -1;
        var r: i8 = @intCast(row);
        const c: i8 = @intCast(col);
        r += row_offset;

        const start_row: u8 = if (isWhite) 1 else 6;
        const promotion_row: u8 = if (isWhite) 7 else 0;

        if (!isInBounds(r, c)) return;

        // En Passant
        if (self.en_passant_pos) |ep| {
            if (ep[0] == r and (ep[1] == c - 1 or ep[1] == c + 1)) {
                self.allLegalMoves[self.allLegalMoveCount] = Move{
                    .from = .{ @intCast(row), @intCast(col) },
                    .to = .{ ep[0], ep[1] },
                    .move_type = .EnPassant,
                };
                self.allLegalMoveCount += 1;
            }
        }

        if (isInBounds(r, c - 1)) {
            if (self.board[@intCast(r)][col - 1]) |piece| {
                if (piece.color != self.turn) {
                    // Promotion
                    if (r == promotion_row) {
                        var move = Move{
                            .from = .{ @intCast(row), @intCast(col) },
                            .to = .{ @intCast(r), @intCast(col - 1) },
                            .move_type = .Promotion,
                        };
                        move.promotion_piece = .Queen;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Rook;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Bishop;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Knight;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                    } else {
                        // Capture
                        self.allLegalMoves[self.allLegalMoveCount] = Move{
                            .from = .{ @intCast(row), @intCast(col) },
                            .to = .{ @intCast(r), @intCast(col - 1) },
                            .move_type = .Capture,
                        };
                        self.allLegalMoveCount += 1;
                    }
                }
            }
        }

        if (isInBounds(r, c + 1)) {
            if (self.board[@intCast(r)][col + 1]) |piece| {
                if (piece.color != self.turn) {
                    if (r == promotion_row) {
                        // Promotion
                        var move = Move{
                            .from = .{ @intCast(row), @intCast(col) },
                            .to = .{ @intCast(r), @intCast(col + 1) },
                            .move_type = .Promotion,
                        };
                        move.promotion_piece = .Queen;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Rook;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Bishop;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                        move.promotion_piece = .Knight;
                        self.allLegalMoves[self.allLegalMoveCount] = move;
                        self.allLegalMoveCount += 1;
                    } else {
                        // Capture
                        self.allLegalMoves[self.allLegalMoveCount] = Move{
                            .from = .{ @intCast(row), @intCast(col) },
                            .to = .{ @intCast(r), @intCast(col + 1) },
                            .move_type = .Capture,
                        };
                        self.allLegalMoveCount += 1;
                    }
                }
            }
        }

        if (self.board[@intCast(r)][col] != null) return;
        if (r == promotion_row) {
            // Promotion
            var move = Move{
                .from = .{ @intCast(row), @intCast(col) },
                .to = .{ @intCast(r), @intCast(col) },
                .move_type = .Promotion,
            };
            move.promotion_piece = .Queen;
            self.allLegalMoves[self.allLegalMoveCount] = move;
            self.allLegalMoveCount += 1;
            move.promotion_piece = .Rook;
            self.allLegalMoves[self.allLegalMoveCount] = move;
            self.allLegalMoveCount += 1;
            move.promotion_piece = .Bishop;
            self.allLegalMoves[self.allLegalMoveCount] = move;
            self.allLegalMoveCount += 1;
            move.promotion_piece = .Knight;
            self.allLegalMoves[self.allLegalMoveCount] = move;
            self.allLegalMoveCount += 1;
        } else {
            // Normal
            self.allLegalMoves[self.allLegalMoveCount] = Move{
                .from = .{ @intCast(row), @intCast(col) },
                .to = .{ @intCast(r), @intCast(col) },
                .move_type = .Normal,
            };
            self.allLegalMoveCount += 1;
        }

        // Double Push
        if (row == start_row and self.board[@intCast(r + row_offset)][col] == null) {
            self.allLegalMoves[self.allLegalMoveCount] = Move{
                .from = .{ @intCast(row), @intCast(col) },
                .to = .{ @intCast(r + row_offset), @intCast(col) },
                .move_type = .DoublePawnPush,
            };
            self.allLegalMoveCount += 1;
        }
    }

    fn genKnightMoves(self: *GameState, row: usize, col: usize) void {
        for (knight_dirs) |dir| {
            var r: i8 = @intCast(row);
            var c: i8 = @intCast(col);
            r += dir.row;
            c += dir.col;
            if (!isInBounds(r, c)) continue;
            if (self.board[@abs(r)][@abs(c)]) |piece| {
                if (piece.color == self.turn) continue;
                self.allLegalMoves[self.allLegalMoveCount] = Move{
                    .from = .{ @intCast(row), @intCast(col) },
                    .to = .{ @intCast(r), @intCast(c) },
                    .move_type = .Capture,
                };
            } else {
                self.allLegalMoves[self.allLegalMoveCount] = Move{
                    .from = .{ @intCast(row), @intCast(col) },
                    .to = .{ @intCast(r), @intCast(c) },
                    .move_type = .Normal,
                };
            }
            self.allLegalMoveCount += 1;
        }
    }

    fn genSliderMoves(self: *GameState, row: usize, col: usize, dirs: []const Vec2) void {
        for (dirs) |dir| {
            var r: i8 = @intCast(row);
            var c: i8 = @intCast(col);
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;
                if (self.board[@abs(r)][@abs(c)]) |piece| {
                    if (piece.color != self.turn) {
                        self.allLegalMoves[self.allLegalMoveCount] = Move{
                            .from = .{ @intCast(row), @intCast(col) },
                            .to = .{ @intCast(r), @intCast(c) },
                            .move_type = .Capture,
                        };
                        self.allLegalMoveCount += 1;
                    }
                    break;
                }
                self.allLegalMoves[self.allLegalMoveCount] = Move{
                    .from = .{ @intCast(row), @intCast(col) },
                    .to = .{ @intCast(r), @intCast(c) },
                    .move_type = .Normal,
                };

                self.allLegalMoveCount += 1;
            }
        }
    }

    fn selectSquare(self: *GameState, row: usize, col: usize) void {
        if (self.board[row][col] == null or row > 7 or col > 7) return;
        if (self.turn != self.board[row][col].?.color) return;
        self.selectedSquare = .{ @intCast(row), @intCast(col) };
    }

    fn isSquareAttacked(self: *GameState, target_square: [2]u8, attacker_color: Color) bool {
        const pawn_dirs = if (attacker_color == .White) [_]Vec2{ .{ .row = -1, .col = 1 }, .{ .row = -1, .col = -1 } } else [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = -1 } };
        for (pawn_dirs) |dir| {
            var r: i8 = @intCast(target_square[0]);
            var c: i8 = @intCast(target_square[1]);
            r += dir.row;
            c += dir.col;
            if (!isInBounds(r, c)) continue;
            if (self.board[@abs(r)][@abs(c)]) |piece| {
                if (piece.color == attacker_color and (piece.type == .Pawn or piece.type == .Queen or piece.type == .Bishop)) return true;
            }
        }

        for (knight_dirs) |dir| {
            var r: i8 = @intCast(target_square[0]);
            var c: i8 = @intCast(target_square[1]);
            r += dir.row;
            c += dir.col;
            if (!isInBounds(r, c)) continue;
            if (self.board[@abs(r)][@abs(c)]) |piece| {
                if (piece.color == attacker_color and piece.type == .Knight) return true;
            }
        }

        for (king_dirs) |dir| {
            var r: i8 = @intCast(target_square[0]);
            var c: i8 = @intCast(target_square[1]);
            r += dir.row;
            c += dir.col;
            if (!isInBounds(r, c)) continue;
            if (self.board[@abs(r)][@abs(c)]) |piece| {
                if (piece.color == attacker_color and piece.type == .King) return true;
            }
        }

        for (rook_dirs) |dir| {
            var r: i8 = @intCast(target_square[0]);
            var c: i8 = @intCast(target_square[1]);
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;
                if (self.board[@abs(r)][@abs(c)]) |piece| {
                    if (piece.color == attacker_color and (piece.type == .Rook or piece.type == .Queen)) return true;
                    break;
                }
            }
        }
        for (bishop_dirs) |dir| {
            var r: i8 = @intCast(target_square[0]);
            var c: i8 = @intCast(target_square[1]);
            while (true) {
                r += dir.row;
                c += dir.col;
                if (!isInBounds(r, c)) break;
                if (self.board[@abs(r)][@abs(c)]) |piece| {
                    if (piece.color == attacker_color and (piece.type == .Bishop or piece.type == .Queen)) return true;
                    break;
                }
            }
        }
        return false;
    }
};

fn loadTextureFromImage(path: [:0]const u8) !rl.Texture2D {
    const image = try rl.loadImage(path);
    const texture = try rl.loadTextureFromImage(image);
    rl.unloadImage(image);
    return texture;
}

fn drawPiece(texture: rl.Texture2D, row: u8, col: u8) void {
    const src_width: f32 = @floatFromInt(texture.width);
    const src_height: f32 = @floatFromInt(texture.height);

    const dst_width: f32 = @floatFromInt(col * BLOCK_SIZE);
    const dst_height: f32 = @floatFromInt(row * BLOCK_SIZE);
    rl.drawTexturePro(texture, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(dst_width, dst_height, BLOCK_SIZE, BLOCK_SIZE), rl.Vector2.init(0, 0), 0.0, rl.Color.white);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Zig Chess");
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    var game_state = try GameState.init(allocator, initial_board);
    defer game_state.deinit();
    var assets = try PieceAssets.init();
    defer assets.deinit();

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.white);

        drawBoard(game_state, assets);

        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            try handleMousePressed(&game_state);
        }
    }
}

fn getMouseBoardPosition() [2]u8 {
    const mouse = rl.getMousePosition();
    const row = @as(usize, @intFromFloat(mouse.y / BLOCK_SIZE));
    const col = @as(usize, @intFromFloat(mouse.x / BLOCK_SIZE));
    return .{ @intCast(row), @intCast(col) };
}

fn handleMousePressed(state: *GameState) !void {
    const mouse_pos = getMouseBoardPosition();
    const row = mouse_pos[0];
    const col = mouse_pos[1];
    if (state.selectedSquare) |sel| {
        try handleMoveAttempt(state, @intCast(row), @intCast(col), sel);
    } else {
        handleInitialSelection(state, @intCast(row), @intCast(col));
    }
}

fn handleInitialSelection(state: *GameState, row: usize, col: usize) void {
    const piece = state.board[row][col];
    if (piece) |p| {
        if (p.color != state.turn) return;
        state.selectSquare(row, col);
    }
}

fn handleMoveAttempt(state: *GameState, row: u8, col: u8, selected_square: [2]u8) !void {
    if (selected_square[0] == row and selected_square[1] == col) {
        state.selectedSquare = null;
        return;
    }
    const targetPiece = state.board[row][col];
    if (targetPiece != null and targetPiece.?.color == state.turn) {
        state.selectedSquare = .{ row, col };
        return;
    }
    for (state.allLegalMoves[0..state.allLegalMoveCount]) |move| {
        if (move.to[0] == row and move.to[1] == col and move.from[0] == selected_square[0] and move.from[1] == selected_square[1]) {
            _ = try state.applyMove(move);
            state.selectedSquare = null;
            try state.switchTurn();
            return;
        }
    }
}

fn drawBoard(state: GameState, assets: PieceAssets) void {
    for (0..BLOCKS) |row| {
        for (0..BLOCKS) |col| {
            const i: u8 = @intCast(row);
            const j: u8 = @intCast(col);
            const x = @as(i32, @intCast(col)) * BLOCK_SIZE;
            const y = @as(i32, @intCast(row)) * BLOCK_SIZE;
            const color: rl.Color = if ((row + col) % 2 == 0) rl.Color.init(122, 153, 90, 255) else rl.Color.init(240, 240, 211, 255);
            rl.drawRectangle(x, y, BLOCK_SIZE, BLOCK_SIZE, color);

            if (state.selectedSquare) |sel| {
                if (sel[0] == row and sel[1] == col) {
                    rl.drawRectangle(x, y, BLOCK_SIZE, BLOCK_SIZE, rl.Color.sky_blue);
                }
            }

            if (state.board[row][col]) |piece| {
                const texture = assets.getTexture(piece);
                drawPiece(texture, i, j);
            }
        }
    }

    if (state.selectedSquare) |sel| {
        for (state.allLegalMoves[0..state.allLegalMoveCount]) |move| {
            if (move.from[0] == sel[0] and move.from[1] == sel[1]) {
                const x = @as(i32, @intCast(move.to[1])) * BLOCK_SIZE;
                const y = @as(i32, @intCast(move.to[0])) * BLOCK_SIZE;
                rl.drawRectangle(x, y, BLOCK_SIZE, BLOCK_SIZE, rl.Color.init(0, 0, 255, 100));
            }
        }
    }
}

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

fn perft(state: *GameState, depth: u32) !PerftResults {
    // Base case: we reached a leaf node
    if (depth == 0) return PerftResults{ .nodes = 1 };

    var total_results = PerftResults{};

    _ = try state.calculateAllLegalMoves();

    // Copy moves to local stack to avoid recursion corruption
    var local_moves: [218]Move = undefined;
    const count = state.allLegalMoveCount;
    @memcpy(local_moves[0..count], state.allLegalMoves[0..count]);

    for (local_moves[0..count]) |move| {
        var is_capture = move.move_type == .Capture or move.move_type == .EnPassant;
        const is_ep = move.move_type == .EnPassant;
        const is_castle = move.move_type == .Castling;
        const is_promo = move.move_type == .Promotion;

        const history = try state.applyMove(move);
        if (history.captured_piece != null) {
            // std.debug.print("Move: {any}\n", .{nonull_history_captured_piece});
            is_capture = true;
        }
        try state.switchTurn();

        const branch_results = try perft(state, depth - 1);

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

        try state.switchTurn();
        try state.undoMove(move);
    }

    return total_results;
}

pub fn perftDivide(state: *GameState, depth: u32) !void {
    if (depth == 0) {
        std.debug.print("Total nodes: 1\n", .{});
        return;
    }

    var total_nodes: u64 = 0;

    _ = try state.calculateAllLegalMoves();

    // Copy to local stack (to avoid recursion corruption)
    var root_moves: [218]Move = undefined;
    const count = state.allLegalMoveCount;
    @memcpy(root_moves[0..count], state.allLegalMoves[0..count]);

    std.debug.print("\n--- Perft Divide Depth {d} ---\n", .{depth});

    for (root_moves[0..count]) |move| {
        _ = try state.applyMove(move);
        try state.switchTurn();

        const nodes_from_move = try perft(state, depth - 1);

        total_nodes += nodes_from_move.nodes;

        printMove(move);
        std.debug.print(": {d}\n", .{nodes_from_move.nodes});

        try state.switchTurn();
        try state.undoMove(move);
    }

    std.debug.print("---------------------------\n", .{});
    std.debug.print("Total Nodes at Depth {d}: {d}\n\n", .{ depth, total_nodes });
}

fn printMove(move: Move) void {
    const files = "abcdefgh";
    const ranks = "12345678"; // Adjusted for 0-indexed top-down board

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

const testing = std.testing;

test "Chess Move Generation - Initial Position" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var state = try GameState.init(allocator, test_board);
    defer state.deinit();

    // try perftDivide(&state, 1);

    const result1 = try perft(&state, 1);
    std.debug.print("Depth 1: {d}--{d} -- {d} -- {d} -- {d}\n", .{ result1.nodes, result1.captures, result1.en_passants, result1.castles, result1.promotions });
}
