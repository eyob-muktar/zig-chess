pub const Color = enum { White, Black };
pub const PieceType = enum { Pawn, Knight, Bishop, Rook, Queen, King };

pub const Piece = struct {
    type: PieceType,
    color: Color,
};

pub const MoveType = enum(u3) {
    Normal,
    Capture,
    DoublePawnPush,
    EnPassant,
    Castling,
    Promotion,
};

pub const Move = struct {
    from: [2]u8,
    to: [2]u8,
    piece: PieceType,
    move_type: MoveType,
    promotion_piece: ?PieceType = null,
};

pub const CastlingRights = packed struct(u4) {
    white_king_side: bool = true,
    white_queen_side: bool = true,
    black_king_side: bool = true,
    black_queen_side: bool = true,
};

pub const GameStatus = enum { ongoing, white_wins, black_wins, draw };
