const std = @import("std");
const rl = @import("raylib");

const BLOCKS = 8;
const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 800;
const BLOCK_SIZE: i32 = SCREEN_WIDTH / BLOCKS;

const initial_board = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";

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
    promotion_piece: ?PieceType = null, // Only used if move_type == .Promotion
};

const HistoryEntry = struct {
    move: Move,
    captured_piece: ?Piece,
    old_castling_rights: CastlingRights,
    old_en_passant_pos: ?[2]u8, // Was there an EP target before this move?
    half_move_clock: u32, // For the 50-move rule
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

// Define the state for the game
const GameState = struct {
    board: [8][8]?Piece,
    selectedSquare: ?[2]u8,
    turn: Color,
    moveInProgress: bool,
    allLegalMoves: [218]Move,
    allLegalMoveCount: u8,
    castlingRights: CastlingRights,
    allocator: std.mem.Allocator,
    history: std.ArrayList(HistoryEntry),
    en_passant_pos: ?[2]u8,

    fn init(allocator: std.mem.Allocator) !GameState {
        var game_state = GameState{
            .allocator = allocator,
            .board = buildInitialBoard(),
            .selectedSquare = null,
            .turn = Color.Black,
            .moveInProgress = false,
            .allLegalMoves = [_]Move{undefined} ** 218,
            .allLegalMoveCount = 0,
            .history = try std.ArrayList(HistoryEntry).initCapacity(allocator, 100),
            .castlingRights = CastlingRights{ .white_king_side = true, .white_queen_side = true, .black_king_side = true, .black_queen_side = true },
            .en_passant_pos = null,
        };
        try game_state.calculateAllLegalMoves();
        return game_state;
    }

    fn deinit(self: *GameState) void {
        self.history.deinit(self.allocator);
        self.allocator.destroy(self.history);
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
        self.board[move.to[0]][move.to[1]] = self.board[move.from[0]][move.from[1]];
        self.board[move.from[0]][move.from[1]] = null;

        const history_entry = HistoryEntry{
            .move = move,
            .captured_piece = target,
            .old_castling_rights = self.castlingRights,
            .half_move_clock = 0,
            .old_en_passant_pos = self.en_passant_pos,
        };

        if (move.move_type == .DoublePawnPush) {
            self.en_passant_pos = if (self.turn == Color.White) .{ move.to[0] - 1, move.to[1] } else .{ move.to[0] + 1, move.to[1] };
        } else {
            self.en_passant_pos = null;
        }

        try self.history.append(self.allocator, history_entry);
        return history_entry;
    }

    fn undoMove(self: *GameState, move: Move) !void {
        const history_entry = self.history.pop();
        if (history_entry) |entry| {
            self.board[move.from[0]][move.from[1]] = self.board[move.to[0]][move.to[1]];
            if (move.move_type == .EnPassant) {
                self.board[move.to[0]][move.to[1]] = null;
                self.board[move.from[0]][move.to[1]] = entry.captured_piece;
            } else {
                self.board[move.to[0]][move.to[1]] = entry.captured_piece;
            }

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
        const king_pos = self.findKing(self.turn);
        var idx: usize = 0;
        while (idx < self.allLegalMoveCount) {
            const move = self.allLegalMoves[idx];
            _ = try self.applyMove(move);
            const attacker_color = if (self.turn == Color.White) Color.Black else Color.White;
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

    fn findKing(self: *GameState, color: Color) [2]u8 {
        for (self.board, 0..) |row, row_idx| {
            for (row, 0..) |col, col_idx| {
                if (col) |piece| {
                    if (piece.type == .King and piece.color == color) {
                        return .{
                            @intCast(row_idx),
                            @intCast(col_idx),
                        };
                    }
                }
            }
        }
        unreachable;
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
    }

    fn getPawnMoves(self: *GameState, row: usize, col: usize) void {
        const isWhite = self.turn == Color.White;
        const row_offset: i8 = if (isWhite) 1 else -1;
        var r: i8 = @intCast(row);
        const c: i8 = @intCast(col);
        r += row_offset;

        const start_row: u8 = if (isWhite) 1 else 6;

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
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ @intCast(r), @intCast(col - 1) },
                        .move_type = .Capture,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
        }

        if (isInBounds(r, c + 1)) {
            if (self.board[@intCast(r)][col + 1]) |piece| {
                if (piece.color != self.turn) {
                    self.allLegalMoves[self.allLegalMoveCount] = Move{
                        .from = .{ @intCast(row), @intCast(col) },
                        .to = .{ @intCast(r), @intCast(col + 1) },
                        .move_type = .Capture,
                    };
                    self.allLegalMoveCount += 1;
                }
            }
        }

        if (self.board[@intCast(r)][col] != null) return;
        self.allLegalMoves[self.allLegalMoveCount] = Move{
            .from = .{ @intCast(row), @intCast(col) },
            .to = .{ @intCast(r), @intCast(col) },
            .move_type = .Normal,
        };
        self.allLegalMoveCount += 1;
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
            }
            self.allLegalMoves[self.allLegalMoveCount] = Move{
                .from = .{ @intCast(row), @intCast(col) },
                .to = .{ @intCast(r), @intCast(c) },
                .move_type = .Normal,
            };
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

    fn movePiece(self: *GameState, src_row: usize, src_col: usize, dst_row: usize, dst_col: usize) void {
        if (src_row == dst_row and src_col == dst_col) return;
        if (self.board[dst_row][dst_col] != null) return;
        if (self.board[src_row][src_col]) |piece| {
            self.board[dst_row][dst_col] = piece;
            self.board[src_row][src_col] = null;
        }
    }

    fn isSquareAttacked(self: *GameState, target_square: [2]u8, attacker_color: Color) bool {
        const pawn_dirs = if (attacker_color == .White) [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = -1 } } else [_]Vec2{ .{ .row = 1, .col = 1 }, .{ .row = 1, .col = -1 } };
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

    var game_state = try GameState.init(allocator);
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
