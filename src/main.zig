const std = @import("std");
const rl = @import("raylib");
const types = @import("types.zig");
const engine = @import("engine.zig");

const BLOCK_SIZE = 100;
const BOARD_WIDTH = 800;
const BOARD_HEIGHT = 800;
const BOX_PADDING = 20;
const HISTORY_PANEL_WIDTH = 400;
const HISTORY_PANEL_HEIGHT = BOARD_HEIGHT - (BOX_PADDING * 2);
const SCREEN_WIDTH = BOARD_WIDTH + HISTORY_PANEL_WIDTH + (BOX_PADDING * 2);
const SCREEN_HEIGHT = BOARD_HEIGHT;
const NOTATION_BOX_SIZE = 50;
const LINE_HEIGHT = 40;

const UIInteractionState = enum {
    idle,
    dragging_piece,
    promoting,
};
const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";

const UI = struct {
    game: engine.Game,
    state: UIInteractionState,

    selected_sq: ?[2]u8,
    pending_from: ?[2]u8,
    pending_to: ?[2]u8,

    textures: std.AutoHashMap(types.Piece, rl.Texture2D),
    font: rl.Font,
    history_scroll: f32 = 0,
    white_player: types.PlayerType,
    black_player: types.PlayerType,

    pub fn init(allocator: std.mem.Allocator) !UI {
        return UI{
            .game = try engine.Game.init(allocator, START_FEN),
            .state = .idle,
            .selected_sq = null,
            .pending_from = null,
            .pending_to = null,
            .textures = std.AutoHashMap(types.Piece, rl.Texture2D).init(allocator),
            .font = try rl.loadFontEx("assets/jetbrains-mono-v18-latin-regular.ttf", 48, null),
            .white_player = .Human,
            .black_player = .Computer,
        };
    }

    pub fn deinit(self: *UI) void {
        var it = self.textures.valueIterator();
        while (it.next()) |tex| {
            rl.unloadTexture(tex.*);
        }
        self.textures.deinit();
        self.game.deinit();
    }

    pub fn loadAssets(self: *UI) !void {
        const bp_texture = try loadTextureFromImage("assets/bp.png");
        try self.textures.put(types.Piece{ .type = .Pawn, .color = .Black }, bp_texture);
        const wp_texture = try loadTextureFromImage("assets/wp.png");
        try self.textures.put(types.Piece{ .type = .Pawn, .color = .White }, wp_texture);
        const br_texture = try loadTextureFromImage("assets/br.png");
        try self.textures.put(types.Piece{ .type = .Rook, .color = .Black }, br_texture);
        const wr_texture = try loadTextureFromImage("assets/wr.png");
        try self.textures.put(types.Piece{ .type = .Rook, .color = .White }, wr_texture);
        const bk_texture = try loadTextureFromImage("assets/bk.png");
        try self.textures.put(types.Piece{ .type = .King, .color = .Black }, bk_texture);
        const wk_texture = try loadTextureFromImage("assets/wk.png");
        try self.textures.put(types.Piece{ .type = .King, .color = .White }, wk_texture);
        const bq_texture = try loadTextureFromImage("assets/bq.png");
        try self.textures.put(types.Piece{ .type = .Queen, .color = .Black }, bq_texture);
        const wq_texture = try loadTextureFromImage("assets/wq.png");
        try self.textures.put(types.Piece{ .type = .Queen, .color = .White }, wq_texture);
        const bb_texture = try loadTextureFromImage("assets/bb.png");
        try self.textures.put(types.Piece{ .type = .Bishop, .color = .Black }, bb_texture);
        const wb_texture = try loadTextureFromImage("assets/wb.png");
        try self.textures.put(types.Piece{ .type = .Bishop, .color = .White }, wb_texture);
        const bn_texture = try loadTextureFromImage("assets/bn.png");
        try self.textures.put(types.Piece{ .type = .Knight, .color = .Black }, bn_texture);
        const wn_texture = try loadTextureFromImage("assets/wn.png");
        try self.textures.put(types.Piece{ .type = .Knight, .color = .White }, wn_texture);
    }

    pub fn update(self: *UI) !void {
        // Block interactions if game is over
        if (self.game.status == .ongoing) {
            const is_computer_turn = self.game.turn == .White and self.white_player == .Computer or self.game.turn == .Black and self.black_player == .Computer;
            if (is_computer_turn) {
                const best_move = try self.game.getBestMove();
                if (best_move.from[0] == 170) {
                    return;
                }

                try self.game.applyMove(best_move);
                try self.game.switchTurn();
                self.selected_sq = null;
                self.state = .idle;
            } else {
                if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                    const mouse = rl.getMousePosition();
                    const col = @divFloor(@as(i32, @intFromFloat(mouse.x)), BLOCK_SIZE);
                    const row = @divFloor(@as(i32, @intFromFloat(mouse.y)), BLOCK_SIZE);

                    const engine_row = row;

                    if (engine_row >= 0 and engine_row < 8 and col >= 0 and col < 8) {
                        try self.handleBoardClick(@intCast(engine_row), @intCast(col));
                    }
                }
            }
        } else {
            // Restart logic
            if (rl.isKeyPressed(rl.KeyboardKey.r)) {
                self.game.reset();
                try self.game.loadFen(START_FEN);
                try self.game.generateLegalMoves();
                self.state = .idle;
                self.selected_sq = null;
                return;
            }
        }
    }

    fn handleBoardClick(self: *UI, row: u8, col: u8) !void {
        if (self.state == .promoting) {
            try self.handlePromotion(row, col);
        } else if (self.selected_sq) |sel| {
            for (0..self.game.move_count) |i| {
                const move = self.game.moves[i];
                if (move.from[0] == sel[0] and move.from[1] == sel[1] and
                    move.to[0] == row and move.to[1] == col)
                {
                    if (move.move_type == .Promotion) {
                        self.state = .promoting;
                        self.pending_from = sel;
                        self.pending_to = .{ row, col };
                    } else {
                        try self.game.applyMove(move);
                        try self.game.switchTurn();
                        self.selected_sq = null;
                        self.state = .idle;
                        const total_history_height = @as(f32, @floatFromInt(self.game.history.items.len / 2)) * LINE_HEIGHT;
                        if (total_history_height > HISTORY_PANEL_HEIGHT - 40) {
                            self.history_scroll = -(total_history_height - (HISTORY_PANEL_HEIGHT - 60));
                        }
                    }
                    return;
                }
            }
            // If invalid move, select new piece
            const p = self.game.board[row][col];
            if (p != null and p.?.color == self.game.turn) {
                self.selected_sq = .{ row, col };
            } else {
                self.selected_sq = null;
            }
        } else {
            const p = self.game.board[row][col];
            if (p != null and p.?.color == self.game.turn) {
                self.selected_sq = .{ row, col };
                self.state = .dragging_piece;
            }
        }
    }

    fn handlePromotion(self: *UI, clicked_row: u8, clicked_col: u8) !void {
        const from = self.pending_from;
        const to = self.pending_to;

        if (from == null or to == null or clicked_row < 0 or clicked_col > 7 or clicked_col != to.?[1] or (self.game.turn == .White and clicked_row > 3) or (self.game.turn == .Black and clicked_row < 4)) {
            self.state = .idle;
            return;
        }

        const clicked_piece = switch (clicked_row) {
            0, 7 => types.PieceType.Queen,
            1, 6 => types.PieceType.Knight,
            2, 5 => types.PieceType.Rook,
            3, 4 => types.PieceType.Bishop,
            else => types.PieceType.Queen,
        };

        for (self.game.moves[0..self.game.move_count]) |move| {
            if (move.promotion_piece) |piece| {
                if (move.from[0] == from.?[0] and
                    move.from[1] == from.?[1] and
                    move.to[0] == to.?[0] and
                    move.to[1] == to.?[1] and
                    move.move_type == .Promotion and
                    piece == clicked_piece)
                {
                    try self.game.applyMove(move);
                    try self.game.switchTurn();
                    self.state = .idle;
                    self.selected_sq = null;
                    return;
                }
            }
        }
    }

    pub fn draw(self: *UI) void {
        self.drawHistoryPanel();
        const history = self.game.history.getLastOrNull();
        for (0..8) |r| {
            for (0..8) |c| {
                const color = if ((r + c) % 2 == 1) rl.Color.init(10, 110, 15, 255) else rl.Color.init(217, 217, 217, 255);
                const text_color = if ((r + c) % 2 == 0) rl.Color.init(10, 110, 15, 255) else rl.Color.init(217, 217, 217, 255);
                // rl.drawRectangleRounded(rl.Rectangle.init(@floatFromInt(c * BLOCK_SIZE), @floatFromInt(r * BLOCK_SIZE), BLOCK_SIZE, BLOCK_SIZE), 0.1, 1, color);
                rl.drawRectangle(@intCast(c * BLOCK_SIZE), @intCast(r * BLOCK_SIZE), BLOCK_SIZE, BLOCK_SIZE, color);

                if (self.selected_sq) |sel| {
                    if (sel[0] == r and sel[1] == c) {
                        rl.drawRectangle(@intCast(c * BLOCK_SIZE), @intCast(r * BLOCK_SIZE), BLOCK_SIZE, BLOCK_SIZE, rl.fade(rl.Color.yellow, 1));
                    }
                }

                if (history) |entry| {
                    if (entry.move.from[0] == r and entry.move.from[1] == c) {
                        rl.drawRectangle(@intCast(c * BLOCK_SIZE), @intCast(r * BLOCK_SIZE), BLOCK_SIZE, BLOCK_SIZE, rl.fade(rl.Color.yellow, 0.5));
                    }
                    if (entry.move.to[0] == r and entry.move.to[1] == c) {
                        rl.drawRectangle(@intCast(c * BLOCK_SIZE), @intCast(r * BLOCK_SIZE), BLOCK_SIZE, BLOCK_SIZE, rl.fade(rl.Color.yellow, 0.6));
                    }
                }

                if (self.game.board[r][c]) |p| {
                    const tex = self.textures.get(p);
                    if (tex) |t| {
                        const src_width: f32 = @floatFromInt(t.width);
                        const src_height: f32 = @floatFromInt(t.height);

                        const dst_width: f32 = @floatFromInt(c * BLOCK_SIZE);
                        const dst_height: f32 = @floatFromInt(r * BLOCK_SIZE);
                        rl.drawTexturePro(t, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(dst_width, dst_height, BLOCK_SIZE, BLOCK_SIZE), rl.Vector2.init(0, 0), 0.0, rl.Color.white);
                    } else {
                        const txt = switch (p.type) {
                            .Pawn => "P",
                            .Rook => "R",
                            .Knight => "N",
                            .Bishop => "B",
                            .Queen => "Q",
                            .King => "K",
                        };
                        const col = if (p.color == .White) rl.Color.white else rl.Color.black;
                        rl.drawText(txt, @intCast(c * BLOCK_SIZE + 30), @intCast(r * BLOCK_SIZE + 20), 40, col);
                    }
                }

                // Draw numbers and letters notation on board
                if (r == 7) {
                    rl.drawTextCodepoint(self.font, @intCast(97 + c), rl.Vector2.init(@floatFromInt((c * BLOCK_SIZE) + BLOCK_SIZE - 15), @floatFromInt((r * BLOCK_SIZE) + BLOCK_SIZE - 20)), 24, text_color);
                }
                if (c == 0) {
                    rl.drawTextCodepoint(self.font, @intCast(56 - r), rl.Vector2.init(@floatFromInt((c * BLOCK_SIZE) + 5), @floatFromInt((r * BLOCK_SIZE) + 5)), 24, text_color);
                }
            }
        }

        if (self.selected_sq) |sel| {
            for (0..self.game.move_count) |i| {
                const move = self.game.moves[i];
                if (move.from[0] == sel[0] and move.from[1] == sel[1]) {
                    const r = move.to[0];
                    const cx = @as(i32, @intCast(move.to[1])) * BLOCK_SIZE + BLOCK_SIZE / 2;
                    const cy = @as(i32, @intCast(r)) * BLOCK_SIZE + BLOCK_SIZE / 2;
                    rl.drawCircle(cx, cy, 18, rl.fade(rl.Color.gray, 0.6));
                }
            }
        }

        if (self.state == .promoting) {
            // black overlay
            rl.drawRectangle(0, 0, BOARD_WIDTH, BOARD_HEIGHT, rl.fade(rl.Color.black, 0.6));

            const start_x = @as(i32, @intCast(self.pending_to.?[1])) * BLOCK_SIZE; // the column the drawing begins. The same for the bg and the pieces
            const bg_row_offset: u8 = if (self.game.turn == types.Color.White) 0 else 4; // the row offset based on who's promoting
            const bg_start_y = @as(i32, bg_row_offset) * BLOCK_SIZE; // the row the drawing begins for the background
            rl.drawRectangleRounded(rl.Rectangle.init(@floatFromInt(start_x), @floatFromInt(bg_start_y), BLOCK_SIZE, BLOCK_SIZE * 4), 0.1, 1, rl.fade(rl.Color.white, 0.8));

            const promotion_pieces = [_]types.PieceType{ .Queen, .Knight, .Rook, .Bishop };
            for (promotion_pieces, 0..) |piece, i| {
                const r: u8 = @intCast(i);
                const row_offset: u8 = if (self.game.turn == types.Color.White) r else 7 - r; // for each promotion pieces
                const start_y = @as(i32, row_offset) * BLOCK_SIZE; // the row the drawing begins for each piece

                // Hover effect
                const mouse = rl.getMousePosition();
                const rect = rl.Rectangle.init(@floatFromInt(start_x), @floatFromInt(start_y), BLOCK_SIZE, BLOCK_SIZE);
                if (rl.checkCollisionPointRec(mouse, rect)) {
                    rl.drawRectangleRec(rect, rl.fade(rl.Color.sky_blue, 0.3));
                }

                const texture = self.textures.get(types.Piece{ .type = piece, .color = self.game.turn });
                if (texture) |t| {
                    const src_width: f32 = @floatFromInt(t.width);
                    const src_height: f32 = @floatFromInt(t.height);
                    const dst_width: f32 = @floatFromInt(BLOCK_SIZE);
                    const dst_height: f32 = @floatFromInt(BLOCK_SIZE);
                    rl.drawTexturePro(t, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(@as(f32, @floatFromInt(start_x)), @as(f32, @floatFromInt(start_y)), dst_width, dst_height), rl.Vector2.init(0, 0), 0.0, rl.Color.white);
                }
            }
        }

        if (self.game.status != .ongoing) {
            // black overlay
            rl.drawRectangle(0, 0, BOARD_WIDTH, BOARD_HEIGHT, rl.fade(rl.Color.black, 0.5));

            // message Box
            const msg = getEndGameMessage(self.game.status);
            const fontSize = 48;
            const textWidth = @max(rl.measureText(msg[0..], fontSize), rl.measureText("Press 'R' to restart", 20));

            const boxW = @as(f32, @floatFromInt(textWidth)) + 60;
            const boxH = 120;
            const boxX = @as(f32, (BOARD_WIDTH - boxW) / 2);
            const boxY = @as(f32, (BOARD_HEIGHT - boxH) / 2);

            // box Shadow
            rl.drawRectangleRec(rl.Rectangle{ .x = boxX + 5, .y = boxY + 5, .width = boxW, .height = boxH }, rl.fade(rl.Color.black, 0.3));
            // main Box
            rl.drawRectangleRec(rl.Rectangle{ .x = boxX, .y = boxY, .width = boxW, .height = boxH }, rl.Color.ray_white);
            rl.drawRectangleLinesEx(rl.Rectangle{ .x = boxX, .y = boxY, .width = boxW, .height = boxH }, 3, rl.Color.yellow);

            rl.drawTextEx(self.font, msg, rl.Vector2.init(boxX + 30, boxY + 30), fontSize, 4, rl.Color.black);
            // rl.drawText(msg, @intFromFloat(boxX + 30), @intFromFloat(boxY + 30), fontSize, rl.Color.black);
            rl.drawText("Press 'R' to restart", @intFromFloat(boxX + 30), @intFromFloat(boxY + 80), 20, rl.Color.black);
        }

        if (self.game.isInCheck()) {
            const king_pos = if (self.game.turn == .White) self.game.white_king_pos else self.game.black_king_pos;
            const x: i32 = @as(i32, king_pos[1]) * BLOCK_SIZE;
            const y: i32 = @as(i32, king_pos[0]) * BLOCK_SIZE;
            rl.drawRectangle(x, y, BLOCK_SIZE, BLOCK_SIZE, rl.fade(rl.Color.red, 0.5));
        }
    }

    pub fn loadTextureFromImage(path: [:0]const u8) !rl.Texture2D {
        const image = try rl.loadImage(path);
        const texture = try rl.loadTextureFromImage(image);
        rl.unloadImage(image);
        return texture;
    }

    pub fn getEndGameMessage(status: types.GameStatus) [:0]const u8 {
        return switch (status) {
            .white_wins => "CHECKMATE: WHITE WINS!",
            .black_wins => "CHECKMATE: BLACK WINS!",
            .draw => "DRAW",
            .ongoing => "",
        };
    }

    pub fn drawHistoryPanel(self: *UI) void {
        const history = self.game.history.items;

        const text_padding = 50;
        const history_panel_rect = rl.Rectangle{ .x = SCREEN_WIDTH - HISTORY_PANEL_WIDTH - BOX_PADDING, .y = 0 + BOX_PADDING, .width = HISTORY_PANEL_WIDTH, .height = HISTORY_PANEL_HEIGHT };
        rl.drawRectangleRec(history_panel_rect, rl.Color.init(30, 30, 30, 255));

        // scroll handler
        const total_history_height = @as(f32, @floatFromInt(self.game.history.items.len / 2)) * LINE_HEIGHT;
        const scroll_offset = total_history_height - HISTORY_PANEL_HEIGHT + 40;
        const mouse_wheel = rl.getMouseWheelMove();
        if (mouse_wheel != 0 and scroll_offset > 0) {
            const scrolled = self.history_scroll + (mouse_wheel * 20);
            // limit the scrolling to the top and bottom of history
            if (@abs(scrolled) <= scroll_offset and scrolled < 20) {
                self.history_scroll = scrolled;
            }
        }

        rl.beginScissorMode(@intFromFloat(history_panel_rect.x), 0, HISTORY_PANEL_WIDTH, HISTORY_PANEL_HEIGHT);
        defer rl.endScissorMode();
        var y_offset: f32 = 20 + self.history_scroll;

        for (history, 0..) |entry, i| {
            const col = i % 2;
            const fontSize = 24;
            const text = formatMoveNotation(entry.move);

            const x_pos = if (col == 0) history_panel_rect.x + text_padding else history_panel_rect.x + (4 * text_padding);

            if (col == 0) {
                // draw move number
                // since we're counting for each color (i = 0 and i = 1 are both move number 1 for white and black respectively)
                const move_number = (i / 2) + 1;
                const num_text = rl.textFormat("%d.", .{move_number});

                rl.drawTextEx(self.font, num_text, rl.Vector2.init(history_panel_rect.x + 10, y_offset), fontSize, 1, rl.Color.gray);
            }
            rl.drawTextEx(self.font, &text, rl.Vector2.init(x_pos, y_offset), fontSize, 2, rl.Color.white);

            if (col != 0) {
                y_offset += LINE_HEIGHT;
            }
        }
    }
};

pub fn formatMoveNotation(move: types.Move) [6:0]u8 {
    var buffer = [6:0]u8{ 0, 0, 0, 0, 0, 0 };
    var i: usize = 0;
    if (move.move_type == .Castling) {
        buffer[i] = 'O';
        i += 1;
        buffer[i] = '-';
        i += 1;
        buffer[i] = 'O';
        i += 1;

        if (move.to[1] == 2) {
            buffer[i] = '-';
            i += 1;
            buffer[i] = 'O';
            i += 1;
        }

        return buffer;
    }

    if (move.piece != .Pawn) {
        buffer[i] = switch (move.piece) {
            .Knight => 'N',
            .Bishop => 'B',
            .Rook => 'R',
            .Queen => 'Q',
            .King => 'K',
            else => '?',
        };
        i += 1;
    }

    if (move.move_type == .Capture) {
        // Special case for pawns: "exd5"
        if (move.piece == .Pawn) {
            buffer[i] = @as(u8, 'a') + move.from[1]; // starting file
            i += 1;
        }
        buffer[i] = 'x';
        i += 1;
    }

    buffer[i] = @as(u8, 'a') + move.to[1]; // file
    i += 1;
    buffer[i] = @as(u8, '8') - move.to[0]; // rank
    i += 1;

    if (move.move_type == .Promotion) {
        buffer[i] = '=';
        i += 1;
        buffer[i] = switch (move.promotion_piece.?) {
            .Knight => 'N',
            .Bishop => 'B',
            .Rook => 'R',
            .Queen => 'Q',
            else => '?',
        };
        i += 1;
    }

    return buffer;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "Zig Chess");
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    var ui = try UI.init(allocator);
    defer ui.deinit();
    try ui.loadAssets();

    while (!rl.windowShouldClose()) {
        try ui.update();
        rl.beginDrawing();
        defer rl.endDrawing();
        rl.clearBackground(rl.Color.dark_gray);
        ui.draw();
    }
}
