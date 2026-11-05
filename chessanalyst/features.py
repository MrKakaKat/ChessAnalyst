"""Шахматные признаки позиции и хода: материал, форсированность, тип, стадия.

Это эвристики из 8.2 (шаги 7–10); пороги лежат в Settings.
"""

from __future__ import annotations

from collections.abc import Sequence

import chess

from .settings import Settings

PIECE_VALUES = {chess.PAWN: 1, chess.KNIGHT: 3, chess.BISHOP: 3, chess.ROOK: 5, chess.QUEEN: 9, chess.KING: 0}

_MINOR_HOMES = {
    chess.WHITE: {chess.B1: chess.KNIGHT, chess.G1: chess.KNIGHT, chess.C1: chess.BISHOP, chess.F1: chess.BISHOP},
    chess.BLACK: {chess.B8: chess.KNIGHT, chess.G8: chess.KNIGHT, chess.C8: chess.BISHOP, chess.F8: chess.BISHOP},
}


# --- материал ---

def material(board: chess.Board, color: chess.Color) -> int:
    return sum(PIECE_VALUES[p.piece_type] for p in board.piece_map().values() if p.color == color)


def balance(board: chess.Board, color: chess.Color) -> int:
    return material(board, color) - material(board, not color)


def non_pawn_material(board: chess.Board) -> int:
    """Сумма материала обеих сторон без королей и пешек (старт — 62)."""
    return sum(PIECE_VALUES[p.piece_type] for p in board.piece_map().values()
               if p.piece_type not in (chess.PAWN, chess.KING))


# --- стадия (шаг 9) ---

def undeveloped_minors(board: chess.Board) -> int:
    n = 0
    for color, homes in _MINOR_HOMES.items():
        for sq, pt in homes.items():
            p = board.piece_at(sq)
            if p is not None and p.color == color and p.piece_type == pt:
                n += 1
    return n


def stage(board: chess.Board, s: Settings) -> str:
    if non_pawn_material(board) <= s.endgame_material:
        return "endgame"
    if board.fullmove_number <= s.opening_max_move and undeveloped_minors(board) >= s.opening_min_undeveloped:
        return "opening"
    return "middlegame"


# --- форсированность (шаг 7) ---

def _has_mate_in_one(b: chess.Board) -> bool:
    for m in b.legal_moves:
        b.push(m)
        mate = b.is_checkmate()
        b.pop()
        if mate:
            return True
    return False


def creates_mate_threat(board: chess.Board, move: chess.Move) -> bool:
    """После хода у ходившего появился бы мат в один, если бы ход снова был его.
    Угроза, которая была и до хода, не считается: ход её не создал."""
    b = board.copy(stack=False)
    b.push(move)
    if b.is_check() or b.is_game_over():
        return False
    b.push(chess.Move.null())
    if not _has_mate_in_one(b):
        return False
    return not _has_mate_in_one(board.copy(stack=False))


def is_forcing(board: chess.Board, move: chess.Move) -> bool:
    return board.is_capture(move) or board.gives_check(move) or creates_mate_threat(board, move)


def forcing_count(board: chess.Board, pv: Sequence[str], window: int) -> int:
    b = board.copy(stack=False)
    n = 0
    for uci in pv[:window]:
        m = chess.Move.from_uci(uci)
        if m not in b.legal_moves:
            break
        if is_forcing(b, m):
            n += 1
        b.push(m)
    return n


# --- подтипы positional (шаг 7) ---

def king_zone_pressure(board: chess.Board, color: chess.Color) -> int:
    """Сколько полей вокруг короля соперника (включая его поле) бьёт сторона color."""
    k = board.king(not color)
    if k is None:
        return 0
    zone = chess.SquareSet(chess.BB_KING_ATTACKS[k]) | chess.SquareSet.from_square(k)
    return sum(1 for sq in zone if board.is_attacked_by(color, sq))


def _own_pieces(board: chess.Board, color: chess.Color):
    for sq, p in board.piece_map().items():
        if p.color == color and p.piece_type != chess.KING:
            yield sq, p


def defended_count(board: chess.Board, color: chess.Color) -> int:
    return sum(1 for sq, _ in _own_pieces(board, color) if board.is_attacked_by(color, sq))


def threatened(board: chess.Board, color: chess.Color) -> set[int]:
    """Поля своих фигур под угрозой: атакованы и не защищены, либо атакованы более дешёвой фигурой."""
    out = set()
    for sq, p in _own_pieces(board, color):
        attackers = board.attackers(not color, sq)
        if not attackers:
            continue
        cheapest = min(PIECE_VALUES[board.piece_type_at(a)] or 100 for a in attackers)
        if not board.is_attacked_by(color, sq) or cheapest < PIECE_VALUES[p.piece_type]:
            out.add(sq)
    return out


def threats_count(board: chess.Board, color: chess.Color) -> int:
    return len(threatened(board, color))


def obvious_capture(board: chess.Board, move: chess.Move) -> bool:
    """Взятие фигуры (не пешки), которое сразу выигрывает материал: взятая
    фигура не дешевле берущей или не защищена."""
    if not board.is_capture(move) or board.is_en_passant(move):
        return False
    taken = board.piece_type_at(move.to_square)
    mover = board.piece_type_at(move.from_square)
    if taken is None or PIECE_VALUES[taken] < 3:
        return False
    defended = board.is_attacked_by(not board.turn, move.to_square)
    return PIECE_VALUES[taken] >= (PIECE_VALUES[mover] or 100) or not defended


def pressured(board: chess.Board, after: chess.Board, me: chess.Color) -> int:
    """Фигуры соперника, на которые ход создал угрозу: новая угроза или
    добавочный нападающий, когда нападающих стало больше, чем защитников."""
    before = threatened(board, not me)
    n = 0
    for sq, _ in _own_pieces(after, not me):
        attackers = len(after.attackers(me, sq))
        if not attackers:
            continue
        if sq in threatened(after, not me) and sq not in before:
            n += 1
        elif attackers > len(board.attackers(me, sq)) and attackers > len(after.attackers(not me, sq)):
            n += 1
    return n


def positional_subtypes(board: chess.Board, move: chess.Move, s: Settings) -> list[str]:
    """Направления хода: attack, counterattack, defense (или neutral).

    - attack: после хода появилась новая угроза — шах, фигура соперника под
      угрозой, которой раньше не было, добавочный нападающий на фигуру, где
      нападающих теперь больше, чем защитников, или (не взятием) давление на
      зону короля.
      Само взятие атакой не считается: взятая фигура не в счёт.
    - defense: ход снял угрозу (уход из-под шаха; не взятием — меньше других
      своих фигур под угрозой) или добавил защитника атакованной фигуре, у
      которой защитников было не больше, чем нападающих. Уход самой фигуры из-под
      удара — отступление, а не защита; взятие атакующей фигуры — размен.
    - counterattack: ответ угрозой на угрозу — своя угроза осталась, а ход
      создал новую. Сливается только с защитой (частично снятые угрозы)."""
    me = board.turn
    after = board.copy(stack=False)
    after.push(move)
    capture = board.is_capture(move)
    new_threats = pressured(board, after, me)
    attack = after.is_check() or new_threats >= 1 or (
        not capture and king_zone_pressure(after, me) - king_zone_pressure(board, me) >= s.attack_threshold)
    mine_before = threats_count(board, me)
    # Уход самой фигуры из-под удара — отступление, а не защита: считаются
    # только угрозы другим фигурам.
    others_before = len(threatened(board, me) - {move.from_square})
    others_after = len(threatened(after, me) - {move.to_square})
    removed = 0 if capture else others_before - others_after
    # Защита: у атакованной своей фигуры (не сходившей) стало больше
    # защитников, а до хода их было не больше, чем нападающих.
    guarded = 0
    for sq, p in _own_pieces(board, me):
        if sq == move.from_square or after.piece_at(sq) != p or not board.is_attacked_by(not me, sq):
            continue
        before_def = len(board.attackers(me, sq))
        if len(after.attackers(me, sq)) > before_def and before_def <= len(board.attackers(not me, sq)):
            guarded += 1
    defense = board.is_check() or removed >= s.threats_removed_threshold or guarded >= s.defense_threshold
    out = []
    if attack:
        still = mine_before > 0 and threats_count(after, me) > 0 and not board.is_check()
        out.append("counterattack" if still else "attack")
    if defense:
        out.append("defense")
    return out or ["neutral"]


# --- brilliant (шаг 8) ---

def leaves_piece_en_prise(board: chess.Board, move: chess.Move) -> bool:
    """Сходившая фигура после хода бьётся: не защищена, атакована более дешёвой
    или взяла фигуру дешевле себя (размен с доплатой, как жертва качества)."""
    me = board.turn
    captured = board.piece_at(move.to_square)
    if board.is_en_passant(move):
        captured = chess.Piece(chess.PAWN, not me)
    after = board.copy(stack=False)
    after.push(move)
    piece = after.piece_at(move.to_square)
    if piece is None or piece.piece_type in (chess.PAWN, chess.KING):
        return False
    attackers = after.attackers(not me, move.to_square)
    if not attackers:
        return False
    value = PIECE_VALUES[piece.piece_type]
    if captured is not None and PIECE_VALUES[captured.piece_type] < value:
        return True
    cheapest = min(PIECE_VALUES[after.piece_type_at(a)] or 100 for a in attackers)
    return not after.is_attacked_by(me, move.to_square) or cheapest < value


def leaves_material_en_prise(board: chess.Board, move: chess.Move) -> bool:
    """После хода под боем своя фигура: сама сходившая (см. выше) или другая,
    которую ход оставил висеть, как ферзь b6 в 17...Сe6 Бирн — Фишер."""
    if leaves_piece_en_prise(board, move):
        return True
    if board.is_check():
        return False  # защита от шаха: оставить фигуру не было выбора, это не жертва
    me = board.turn
    after = board.copy(stack=False)
    after.push(move)
    for sq, p in _own_pieces(after, me):
        if p.piece_type == chess.PAWN or sq == move.to_square:
            continue
        attackers = after.attackers(not me, sq)
        if not attackers:
            continue
        cheapest = min(PIECE_VALUES[after.piece_type_at(a)] or 100 for a in attackers)
        if not after.is_attacked_by(me, sq) or cheapest < PIECE_VALUES[p.piece_type]:
            return True
    return False


def is_sacrifice_line(board: chess.Board, pv: Sequence[str], s: Settings) -> bool:
    """Работающая жертва: после первых brilliant_hold_replies ответов соперника
    материал игрока ниже исходного минимум на brilliant_material.

    Проверяется после каждого ответа соперника: так взятие пешки самой жертвой
    (Сxh7+) не маскирует отдачу фигуры после Крxh7. Дальше материал может
    вернуться: требование «не возвращается до конца варианта» отсекало бы
    жертвы, которые окупаются с лихвой (17...Сe6 Бирн — Фишер).
    """
    me = board.turn
    start = balance(board, me)
    b = board.copy(stack=False)
    checked = 0
    for i, uci in enumerate(pv):
        m = chess.Move.from_uci(uci)
        if m not in b.legal_moves:
            break
        b.push(m)
        if i % 2 == 1:  # только что ответил соперник
            if start - balance(b, me) < s.brilliant_material:
                return False
            checked += 1
            if checked >= s.brilliant_hold_replies:
                break
    return checked > 0
