const std = @import("std");
const rl = @import("raylib");
const types = @import("types.zig");
const engine = @import("engine.zig");

const TITLE = "Chessio";
const BLOCK_SIZE = 100;
const BOARD_WIDTH = 800;
const BOARD_HEIGHT = 800;
const BOX_PADDING = 20;

const HISTORY_PANEL_WIDTH = 400;
const HISTORY_PANEL_HEIGHT = BOARD_HEIGHT - (BOX_PADDING * 2);
const SCREEN_WIDTH = BOARD_WIDTH + HISTORY_PANEL_WIDTH + (BOX_PADDING * 2);
const SCREEN_HEIGHT = BOARD_HEIGHT;
const NOTATION_BOX_SIZE = 50;
const LINE_HEIGHT = 50;
const MOVE_HISTORY_HEIGHT = 5 * LINE_HEIGHT;

pub const PlayerAction = union(enum) {
    none,
    make_move: types.Move,
    reset_game,
};

pub const Screen = enum { Menu, Game };

const UIInteractionState = enum {
    idle,
    dragging_piece,
    promoting,
};
const START_FEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR";
// "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1";

const UI = struct {
    game: engine.Game,
    state: UIInteractionState,
    current_screen: Screen = .Menu,

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
            .font = try rl.loadFontEx("assets/jetbrains-mono-v18-latin-regular.ttf", 24, null),
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

    pub fn update(self: *UI, moves: []const types.Move) !PlayerAction {
        // Block interactions if game is over
        if (self.game.status == .ongoing) {
            const is_computer_turn = self.game.turn == .White and self.white_player == .Computer or self.game.turn == .Black and self.black_player == .Computer;
            if (is_computer_turn) {
                const best_move = try self.game.getBestMove();
                if (best_move.from[0] == 170) {
                    return .none;
                }
                return .{ .make_move = best_move };
            } else {
                if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
                    const mouse = rl.getMousePosition();
                    const col = @divFloor(@as(i32, @intFromFloat(mouse.x)), BLOCK_SIZE);
                    const row = @divFloor(@as(i32, @intFromFloat(mouse.y)), BLOCK_SIZE);

                    const engine_row = row;

                    if (engine_row >= 0 and engine_row < 8 and col >= 0 and col < 8) {
                        const move = try self.handleBoardClick(@intCast(engine_row), @intCast(col), moves);
                        if (move) |m| {
                            return .{ .make_move = m };
                        }
                    }
                }
            }
        } else {
            // Restart logic
            if (rl.isKeyPressed(rl.KeyboardKey.r)) {
                return .reset_game;
            }
        }
        return .none;
    }

    fn handleBoardClick(self: *UI, row: u8, col: u8, moves: []const types.Move) !?types.Move {
        if (self.state == .promoting) {
            return try self.handlePromotion(row, col, moves);
        } else if (self.selected_sq) |sel| {
            for (moves[0..]) |move| {
                if (move.from[0] == sel[0] and move.from[1] == sel[1] and
                    move.to[0] == row and move.to[1] == col)
                {
                    if (move.move_type == .Promotion) {
                        self.state = .promoting;
                        self.pending_from = sel;
                        self.pending_to = .{ row, col };
                    } else {
                        return move;
                    }
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
        return null;
    }

    fn handlePromotion(self: *UI, clicked_row: u8, clicked_col: u8, moves: []const types.Move) !?types.Move {
        const from = self.pending_from;
        const to = self.pending_to;

        if (from == null or to == null or clicked_row < 0 or clicked_col > 7 or clicked_col != to.?[1] or (self.game.turn == .White and clicked_row > 3) or (self.game.turn == .Black and clicked_row < 4)) {
            self.state = .idle;
            return null;
        }

        const clicked_piece = switch (clicked_row) {
            0, 7 => types.PieceType.Queen,
            1, 6 => types.PieceType.Knight,
            2, 5 => types.PieceType.Rook,
            3, 4 => types.PieceType.Bishop,
            else => types.PieceType.Queen,
        };

        for (moves[0..]) |move| {
            if (move.promotion_piece) |piece| {
                if (move.from[0] == from.?[0] and
                    move.from[1] == from.?[1] and
                    move.to[0] == to.?[0] and
                    move.to[1] == to.?[1] and
                    move.move_type == .Promotion and
                    piece == clicked_piece)
                {
                    return move;
                }
            }
        }
        return null;
    }

    pub fn draw(self: *UI, moves: []const types.Move) void {
        self.drawHistoryPanel();
        const history = self.game.history.getLastOrNull();
        for (0..8) |r| {
            for (0..8) |c| {
                const color = if ((r + c) % 2 == 1) rl.Color.init(146, 64, 14, 255) else rl.Color.init(254, 243, 199, 255);
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
                        rl.drawTexturePro(t, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(dst_width + 10, dst_height + 5, BLOCK_SIZE - 20, BLOCK_SIZE - 20), rl.Vector2.init(0, 0), 0.0, rl.Color.white);
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
            for (moves[0..]) |move| {
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

    pub fn drawSetupMenu(self: *UI) void {
        rl.clearBackground(rl.Color.init(50, 50, 50, 255));
        const title = "CHESSIO";
        const subtitle = "Select game mode to begin";
        const btn1_txt = "Player vs Player";
        const btn2_txt = "Player vs Computer";
        const btn3_txt = "Exit Game";

        const menu_rect = rl.Rectangle{ .x = 400, .y = 100, .width = 480, .height = 600 };
        rl.drawRectangleRoundedLines(menu_rect, 0.1, 1, rl.Color.yellow);
        rl.drawRectangleRounded(menu_rect, 0.1, 1, rl.fade(rl.Color.init(15, 23, 42, 255), 1));

        const title_size = rl.measureTextEx(self.font, title, 48, 1);
        const subtitle_size = rl.measureTextEx(self.font, subtitle, 24, 1);
        const title_pos_x = menu_rect.x + ((menu_rect.width - title_size.x) / 2);
        const subtitle_pos_x = menu_rect.x + ((menu_rect.width - subtitle_size.x) / 2);

        rl.drawTextEx(self.font, title, rl.Vector2.init(title_pos_x, menu_rect.y + 30), 48, 1, rl.Color.white);
        rl.drawTextEx(self.font, subtitle, rl.Vector2.init(subtitle_pos_x, menu_rect.y + title_size.y + 30), 24, 0, rl.Color.light_gray);

        // Buttons
        const button1_rect = rl.Rectangle{ .x = menu_rect.x + 40, .y = menu_rect.y + 200, .width = menu_rect.width - 80, .height = 75 };
        const button2_rect = rl.Rectangle{ .x = menu_rect.x + 40, .y = menu_rect.y + 300, .width = menu_rect.width - 80, .height = 75 };
        const button3_rect = rl.Rectangle{ .x = menu_rect.x + 40, .y = menu_rect.y + 400, .width = menu_rect.width - 80, .height = 75 };
        // rl.drawRectangleRoundedLines(button_rect, 0.1, 1, rl.Color.yellow);
        rl.drawRectangleRounded(button1_rect, 0.1, 1, rl.fade(rl.Color.init(18, 66, 171, 255), 1));
        rl.drawRectangleRounded(button2_rect, 0.1, 1, rl.fade(rl.Color.init(147, 51, 234, 255), 1));
        rl.drawRectangleRounded(button3_rect, 0.1, 1, rl.fade(rl.Color.init(51, 65, 85, 255), 1));

        const button1_size = rl.measureTextEx(self.font, btn1_txt, 28, 1);
        const button2_size = rl.measureTextEx(self.font, btn2_txt, 28, 1);
        const button3_size = rl.measureTextEx(self.font, btn3_txt, 28, 1);

        const button1_pos_x = button1_rect.x + ((button1_rect.width - button1_size.x) / 2);
        const button2_pos_x = button2_rect.x + ((button2_rect.width - button2_size.x) / 2);
        const button3_pos_x = button3_rect.x + ((button3_rect.width - button3_size.x) / 2);

        rl.drawTextEx(self.font, btn1_txt, rl.Vector2.init(button1_pos_x, button1_rect.y + 25), 28, 1, rl.Color.white);
        rl.drawTextEx(self.font, btn2_txt, rl.Vector2.init(button2_pos_x, button2_rect.y + 25), 28, 1, rl.Color.white);
        rl.drawTextEx(self.font, btn3_txt, rl.Vector2.init(button3_pos_x, button3_rect.y + 25), 28, 1, rl.Color.white);

        // scale up when hover
        if (rl.checkCollisionPointRec(rl.getMousePosition(), button1_rect)) {
            rl.drawRectangleRoundedLines(button1_rect, 0.1, 1, rl.Color.yellow);
        }
        if (rl.checkCollisionPointRec(rl.getMousePosition(), button2_rect)) {
            rl.drawRectangleRoundedLines(button2_rect, 0.1, 1, rl.Color.yellow);
        }
        if (rl.checkCollisionPointRec(rl.getMousePosition(), button3_rect)) {
            rl.drawRectangleRoundedLines(button3_rect, 0.1, 1, rl.Color.yellow);
        }

        // click events
        if (rl.isMouseButtonPressed(rl.MouseButton.left)) {
            // player vs player
            if (rl.checkCollisionPointRec(rl.getMousePosition(), button1_rect)) {
                self.white_player = .Human;
                self.black_player = .Human;
                self.current_screen = .Game;
            }
            // player vs computer
            if (rl.checkCollisionPointRec(rl.getMousePosition(), button2_rect)) {
                self.white_player = .Human;
                self.black_player = .Computer;
                self.current_screen = .Game;
            }
            // exit game
            if (rl.checkCollisionPointRec(rl.getMousePosition(), button3_rect)) {
                std.process.exit(0);
            }
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
        const text_padding = 40;
        const y_padding = 60;
        const history_panel_rect = rl.Rectangle{ .x = SCREEN_WIDTH - HISTORY_PANEL_WIDTH - BOX_PADDING, .y = 0 + BOX_PADDING, .width = HISTORY_PANEL_WIDTH, .height = HISTORY_PANEL_HEIGHT };
        const text_pos_x = history_panel_rect.x + text_padding;
        const title_pos_y = history_panel_rect.y + 20;
        const current_turn_box_pos_y = title_pos_y + y_padding;
        const move_history_box_pos_y = current_turn_box_pos_y + y_padding;

        rl.drawRectangleRec(history_panel_rect, rl.Color.init(30, 30, 60, 255));

        rl.drawTextEx(self.font, TITLE, rl.Vector2.init(text_pos_x, title_pos_y), 36, 1, rl.Color.white);

        // Current turn box
        const text_size = rl.measureTextEx(self.font, "Current Turn ", 24, 1);
        rl.drawTextEx(self.font, "Current Turn ", rl.Vector2.init(text_pos_x, current_turn_box_pos_y), 24, 1, rl.Color.light_gray);
        if (self.game.turn == .White) {
            rl.drawCircle(@intFromFloat(text_pos_x + text_size.x + 40), @intFromFloat(current_turn_box_pos_y + (text_size.y / 2)), 12, rl.Color.white);
            rl.drawTextEx(self.font, "White", rl.Vector2.init(text_pos_x + text_size.x + 60, current_turn_box_pos_y), 24, 1, rl.Color.white);
        } else {
            rl.drawCircle(@intFromFloat(text_pos_x + text_size.x + 40), @intFromFloat(current_turn_box_pos_y + (text_size.y / 2)), 12, rl.Color.black);
            rl.drawTextEx(self.font, "Black", rl.Vector2.init(text_pos_x + text_size.x + 60, current_turn_box_pos_y), 24, 1, rl.Color.white);
        }

        // scroll handler
        const total_history_height = @as(f32, @floatFromInt(history.len / 2)) * (LINE_HEIGHT + 10);
        const scroll_offset = total_history_height - MOVE_HISTORY_HEIGHT;
        const mouse_wheel = rl.getMouseWheelMove();
        if (mouse_wheel != 0 and scroll_offset > 0) {
            const scrolled = self.history_scroll + (mouse_wheel * 20);
            // limit the scrolling to the top and bottom of history
            if (@abs(scrolled) <= scroll_offset and scrolled < 20) {
                self.history_scroll = scrolled;
            }
        }

        // Move History Box
        rl.drawTextEx(self.font, "Move History ", rl.Vector2.init(text_pos_x, move_history_box_pos_y), 24, 1, rl.Color.white);
        rl.beginScissorMode(@intFromFloat(history_panel_rect.x), move_history_box_pos_y + 40, HISTORY_PANEL_WIDTH, MOVE_HISTORY_HEIGHT);
        var y_offset: f32 = move_history_box_pos_y + 40 + self.history_scroll + 10;

        for (history, 0..) |entry, i| {
            const col = i % 2;
            const fontSize = 24;
            const text = formatMoveNotation(entry.move);

            const x_pos = if (col == 0) history_panel_rect.x + (2 * text_padding) else history_panel_rect.x + (5 * text_padding) + 20;

            if (col == 0) {
                // draw move number
                // since we're counting for each color (i = 0 and i = 1 are both move number 1 for white and black respectively)
                // draw a rectangle for each move
                const move_rect = rl.Rectangle.init(text_pos_x - 10, y_offset - 15, history_panel_rect.width - (2 * text_padding), LINE_HEIGHT);
                rl.drawRectangleRounded(move_rect, 0.3, 1, rl.Color.init(15, 23, 42, 255));

                const move_number = (i / 2) + 1;
                const num_text = rl.textFormat("%d.", .{move_number});

                rl.drawTextEx(self.font, num_text, rl.Vector2.init(text_pos_x, y_offset), fontSize, 1, rl.Color.gray);
            }
            rl.drawTextEx(self.font, &text, rl.Vector2.init(x_pos, y_offset), fontSize, 2, rl.Color.white);

            if (col != 0) {
                y_offset += LINE_HEIGHT + 10;
            }
        }
        rl.endScissorMode();

        // Captured Pieces Box
        const cp_box_y = MOVE_HISTORY_HEIGHT + move_history_box_pos_y + y_padding;
        const cp_box_height = 80;
        rl.drawTextEx(self.font, "Captured Pieces", rl.Vector2.init(text_pos_x, cp_box_y), 24, 1, rl.Color.white);
        rl.drawTextEx(self.font, "white", rl.Vector2.init(text_pos_x, cp_box_y + 40), 20, 1, rl.Color.light_gray);
        // const cp_rect = rl.Rectangle.init(text_pos_x, cp_box_y + 80, history_panel_rect.width - (2 * text_padding), cp_box_height);
        // rl.drawRectangleRounded(cp_rect, 0.3, 1, rl.Color.init(42, 64, 117, 255));
        // drwa the captured pieces for white
        for (self.game.captured_black_pieces[0..self.game.captured_black_count], 0..) |p, i| {
            const texture = self.textures.get(.{ .type = p, .color = .Black });
            if (texture == null) continue;
            const t = texture.?;
            const src_width: f32 = @floatFromInt(t.width);
            const src_height: f32 = @floatFromInt(t.height);
            const piece_size = 40;
            const dst_pos_x = text_pos_x + @as(f32, @floatFromInt(i * 40));
            const dst_pos_y = cp_box_y + 100;
            rl.drawTexturePro(t, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(dst_pos_x, dst_pos_y, piece_size, piece_size), rl.Vector2.init(0, 0), 0.0, rl.Color.black);
        }

        rl.drawTextEx(self.font, "black", rl.Vector2.init(text_pos_x, cp_box_y + 40 + y_padding + cp_box_height), 20, 1, rl.Color.light_gray);
        //draw the captured pieces for black
        for (self.game.captured_white_pieces[0..self.game.captured_white_count], 0..) |p, i| {
            const texture = self.textures.get(.{ .type = p, .color = .White });
            if (texture == null) continue;
            const t = texture.?;
            const src_width: f32 = @floatFromInt(t.width);
            const src_height: f32 = @floatFromInt(t.height);
            const piece_size = 40;
            const dst_pos_x = text_pos_x + @as(f32, @floatFromInt(i * 40));
            const dst_pos_y = cp_box_y + cp_box_height + (2 * y_padding);
            if (dst_pos_x > history_panel_rect.x + history_panel_rect.width - (2 * text_padding)) break;
            rl.drawTexturePro(t, rl.Rectangle.init(0, 0, src_width, src_height), rl.Rectangle.init(dst_pos_x, dst_pos_y, piece_size, piece_size), rl.Vector2.init(0, 0), 0.0, rl.Color.white);
        }
    }

    pub fn updateHistoryScroll(self: *UI) void {
        const total_history_height = @as(f32, @floatFromInt(self.game.history.items.len / 2)) * (LINE_HEIGHT + 10);
        if (total_history_height > MOVE_HISTORY_HEIGHT) {
            self.history_scroll = -(total_history_height - MOVE_HISTORY_HEIGHT);
        }
    }

    pub fn uiReset(self: *UI) void {
        self.state = .idle;
        self.selected_sq = null;
        self.pending_from = null;
        self.pending_to = null;
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

    rl.initWindow(SCREEN_WIDTH, SCREEN_HEIGHT, TITLE);
    rl.setTargetFPS(60);
    defer rl.closeWindow();

    var ui = try UI.init(allocator);
    defer ui.deinit();
    try ui.loadAssets();

    var moves: [218]types.Move = undefined;
    var moves_count: usize = 0;
    moves_count = ui.game.generateLegalMoves(&moves, .All);

    while (!rl.windowShouldClose()) {
        rl.beginDrawing();
        defer rl.endDrawing();
        switch (ui.current_screen) {
            .Menu => ui.drawSetupMenu(),
            .Game => {
                const player_action = try ui.update(moves[0..moves_count]);
                switch (player_action) {
                    .make_move => |move| {
                        try ui.game.applyMove(move, true);
                        ui.uiReset();

                        ui.game.switchTurn();
                        ui.updateHistoryScroll();
                        moves_count = ui.game.generateLegalMoves(&moves, .All);
                        ui.game.updateStatus(moves_count);
                    },
                    .reset_game => {
                        ui.game.reset();
                        ui.uiReset();
                        ui.history_scroll = 0;
                        try ui.game.loadFen(START_FEN);

                        moves_count = ui.game.generateLegalMoves(&moves, .All);
                    },
                    .none => {},
                }

                rl.clearBackground(rl.Color.init(15, 23, 42, 255));
                ui.draw(moves[0..moves_count]);
            },
        }
    }
}
