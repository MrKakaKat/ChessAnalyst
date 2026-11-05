"""Идейный слой: цепочка назад от наказания (8.3).

Подпись идеи: атакующая фигура соперника (отслеживается по ходам), цель
(фигура, король или поле) и мотив. Подпись берётся из главного варианта в момент
наказания. Дальше идём назад по партии и на каждой позиции, где ходит владелец
идеи, проверяем по уже посчитанному MultiPV, достигает ли та же фигура той же
цели в пределах K полуходов. «Достигает» значит:
  фигура — взята этой фигурой; король — получил от неё шах; поле — она туда пришла.
Простое «нападает» не считается, иначе цепочка тянулась бы через любую
висящую под боем, но защищённую фигуру.
"""

from __future__ import annotations

import sqlite3
from collections.abc import Sequence
from dataclasses import dataclass, field

import chess

from .classify import MoveRecord
from .db import dumps
from .engine import Line
from .features import PIECE_VALUES, balance
from .settings import Settings

PUNISHING_STEPS = ("mistake", "blunder")


@dataclass
class Signature:
    attacker_piece: str      # символ фигуры, 'R' / 'n'
    attacker_square: int     # в позиции наказания (ход владельца идеи)
    target_kind: str         # piece | king | square
    target_square: int
    target_piece: str | None
    motif: str               # mate, promotion, fork, pin, discovered, open_line, hanging, material, plan
    key_san: str             # ключевой ход в линии наказания

    def to_json(self) -> dict:
        return {
            "attacker": {"piece": self.attacker_piece, "square": chess.square_name(self.attacker_square)},
            "target": {"kind": self.target_kind, "square": chess.square_name(self.target_square),
                       "piece": self.target_piece},
            "motif": self.motif,
            "key": self.key_san,
        }

    def text(self) -> str:
        tgt = self.target_piece or ""
        return (f"{_glyph(self.attacker_piece)}{chess.square_name(self.attacker_square)} → "
                f"{_glyph(tgt) if tgt else ''}{chess.square_name(self.target_square)} ({self.motif})")


@dataclass
class Idea:
    kind: str                    # punishment | pass | brilliant
    punish_ply: int              # полуход ошибки (или pass)
    owner: str                   # чья идея: white | black
    victim: str
    signature: Signature
    start_ply: int               # позиция (до полухода), откуда идея непрерывно присутствует
    miss_ply: int | None         # ход жертвы, которым идею можно было остановить
    distance: int | None         # полуходов между пропуском и наказанием
    chain: list[dict] = field(default_factory=list)
    builder_plies: list[int] = field(default_factory=list)
    chunk: str = ""

    def to_json(self) -> dict:
        return {
            "kind": self.kind, "punish_ply": self.punish_ply, "owner": self.owner, "victim": self.victim,
            "signature": self.signature.to_json(), "signature_text": self.signature.text(),
            "start_ply": self.start_ply, "miss_ply": self.miss_ply, "distance": self.distance,
            "chain": self.chain, "builder_plies": self.builder_plies, "chunk": self.chunk,
        }


def _glyph(symbol: str) -> str:
    return chess.Piece.from_symbol(symbol).unicode_symbol() if symbol else ""


# --- отслеживание фигуры ---

def _castling_rook(board: chess.Board, move: chess.Move) -> tuple[int, int] | None:
    if not board.is_castling(move):
        return None
    rank = chess.square_rank(move.from_square)
    if board.is_kingside_castling(move):
        return chess.square(7, rank), chess.square(5, rank)
    return chess.square(0, rank), chess.square(3, rank)


def track_back(steps: Sequence[tuple[chess.Board, chess.Move]], sq: int) -> int:
    """Где была фигура, стоящая на sq после всех steps, до первого из них."""
    for board, move in reversed(steps):
        rook = _castling_rook(board, move)
        if move.to_square == sq:
            sq = move.from_square
        elif rook and rook[1] == sq:
            sq = rook[0]
    return sq


def _advance(board: chess.Board, move: chess.Move, sq: int | None) -> int | None:
    """Новое поле фигуры с sq после хода; None, если её взяли."""
    if sq is None:
        return None
    rook = _castling_rook(board, move)
    if move.from_square == sq:
        return move.to_square
    if rook and rook[0] == sq:
        return rook[1]
    if move.to_square == sq:
        return None
    if board.is_en_passant(move):
        ep_victim = chess.square(chess.square_file(move.to_square), chess.square_rank(move.from_square))
        if ep_victim == sq:
            return None
    return sq


def reaches(board: chess.Board, pv: Sequence[str], attacker: int, target: int, kind: str,
            window: int) -> bool:
    """Достигает ли фигура с поля attacker цели в пределах window полуходов pv."""
    b = board.copy(stack=False)
    att, tgt = attacker, target
    for uci in pv[:window]:
        m = chess.Move.from_uci(uci)
        if m not in b.legal_moves:
            return False
        mover_is_attacker = m.from_square == att
        if kind == "piece" and mover_is_attacker and m.to_square == tgt:
            return True
        gives_check = b.gives_check(m)
        new_att = _advance(b, m, att)
        new_tgt = tgt if kind == "square" else _advance(b, m, tgt)
        b.push(m)
        att, tgt = new_att, new_tgt
        if att is None or tgt is None:
            return False
        if kind == "square" and mover_is_attacker and att == target:
            return True
        if kind == "king" and gives_check and att in b.checkers():
            return True
    return False


# --- подпись ---

def _motif(before_key: chess.Board, key: chess.Move, steps: list[tuple[chess.Board, chess.Move]],
           target_sq: int, mate: bool) -> str:
    owner = before_key.turn
    if mate:
        return "mate"
    if key.promotion:
        return "promotion"
    attacker_sq = key.from_square
    piece = before_key.piece_at(attacker_sq)
    # вилка: сразу после прихода на поле фигура бьёт две ценные цели
    arrival = before_key
    for i, (b, m) in enumerate(steps):
        if b.turn == owner and m.to_square == attacker_sq:
            arrival = steps[i + 1][0] if i + 1 < len(steps) else before_key
    valuable = [sq for sq in arrival.attacks(attacker_sq)
                if (p := arrival.piece_at(sq)) and p.color != owner
                and (p.piece_type == chess.KING or PIECE_VALUES[p.piece_type] >= 3)]
    if len(valuable) >= 2:
        return "fork"
    if before_key.is_pinned(not owner, target_sq):
        return "pin"
    # вскрытое нападение: предыдущий ход владельца сделан другой фигурой и открыл линию
    own_prev = [(b, m) for b, m in steps if b.turn == owner]
    if own_prev and piece and piece.piece_type in (chess.BISHOP, chess.ROOK, chess.QUEEN):
        b, m = own_prev[-1]
        if m.to_square != attacker_sq and target_sq not in b.attacks(attacker_sq):
            return "discovered"
    if piece and piece.piece_type in (chess.ROOK, chess.QUEEN):
        file_ = chess.square_file(attacker_sq)
        if not any(before_key.piece_type_at(chess.square(file_, r)) == chess.PAWN for r in range(8)):
            return "open_line"
    if not before_key.is_attacked_by(not owner, target_sq):
        return "hanging"
    return "material"


def extract_signature(board: chess.Board, pv: Sequence[str], s: Settings) -> Signature | None:
    """Ключевое событие в линии владельца идеи. board — его позиция, pv — его линия."""
    owner = board.turn
    b = board.copy(stack=False)
    start_balance = balance(b, owner)
    steps: list[tuple[chess.Board, chess.Move]] = []
    # Ключ — взятие владельца, на котором его выигрыш материала дошёл до порога
    # (последнее взятие перед порогом, а не первое: первым часто идёт размен).
    last_capture: tuple[int, chess.Board, chess.Move] | None = None
    biggest: tuple[int, chess.Board, chess.Move] | None = None
    for uci in pv[:s.idea_scan_plies]:
        m = chess.Move.from_uci(uci)
        if m not in b.legal_moves:
            break
        before = b.copy(stack=False)
        is_owner = b.turn == owner
        captured = b.piece_at(m.to_square)
        b.push(m)
        if is_owner and b.is_checkmate():
            return _make(before, m, steps, "king", before.king(not owner), None, s, mate=True)
        if is_owner and m.promotion:
            return _make(before, m, steps, "square", m.to_square, None, s)
        if is_owner and captured is not None:
            last_capture = (len(steps), before, m)
            if biggest is None or PIECE_VALUES[captured.piece_type] > PIECE_VALUES[
                    biggest[1].piece_type_at(biggest[2].to_square)]:
                biggest = last_capture
        steps.append((before, m))
        if last_capture and balance(b, owner) - start_balance >= s.idea_min_gain:
            return _capture_sig(last_capture, steps, s)
    if biggest and PIECE_VALUES[biggest[1].piece_type_at(biggest[2].to_square)] >= s.idea_min_gain:
        return _capture_sig(biggest, steps, s)
    # Без материала и мата — позиционное наказание: первая не королевская фигура владельца.
    for before, m in steps:
        if before.turn == owner and before.piece_type_at(m.from_square) != chess.KING:
            return _make(before, m, [], "square", m.to_square, None, s, motif="plan")
    return None


def _capture_sig(capture: tuple[int, chess.Board, chess.Move], steps: list, s: Settings) -> Signature:
    idx, board, move = capture
    target = board.piece_at(move.to_square)
    return _make(board, move, steps[:idx], "piece", move.to_square, target.symbol(), s)


def _make(before: chess.Board, key: chess.Move, steps: list, kind: str, target_sq: int,
          target_piece: str | None, s: Settings, mate: bool = False, motif: str | None = None
          ) -> Signature:
    piece = before.piece_at(key.from_square)
    motif = motif or _motif(before, key, steps, target_sq, mate)
    # вернуть поля к позиции владельца в начале линии
    attacker0 = track_back(steps, key.from_square)
    target0 = target_sq if kind == "square" else track_back(steps, target_sq)
    return Signature(
        attacker_piece=piece.symbol(), attacker_square=attacker0,
        target_kind=kind, target_square=target0, target_piece=target_piece,
        motif=motif, key_san=before.san(key),
    )


# --- цепочка ---

def _lines_at(analysed, j: int) -> list[Line]:
    a = analysed[j]
    lines = list(a.lines)
    if all(ln.move != a.played.move for ln in lines):
        lines.append(a.played)
    return lines


def build_chain(analysed, records: list[MoveRecord], k: int, s: Settings, kind: str = "punishment"
                ) -> Idea | None:
    """analysed — PlyAnalysis по партии; k — полуход ошибки (или pass)."""
    K = s.idea_window_plies
    game_steps = [(a.board, chess.Move.from_uci(a.played.move)) for a in analysed]

    if kind == "punishment":
        # Владелец — соперник ошибившегося; его позиция — после ошибки.
        mistake = analysed[k]
        after = mistake.board.copy(stack=False)
        after.push(chess.Move.from_uci(mistake.played.move))
        owner_pv = analysed[k + 1].lines[0].pv if k + 1 < len(analysed) else mistake.played.pv[1:]
        p = k + 1                       # позиция владельца (возможно, за концом партии)
        owner_board = after
    else:
        # Pass: владелец — сам игрок, идея — его лучшая линия, которую он не сыграл.
        # Brilliant: идея — сыгранная линия блестящего хода: когда она появилась
        # (цепочка назад) и к чему привела.
        p = k
        owner_board = analysed[k].board
        owner_pv = analysed[k].played.pv if kind == "brilliant" else analysed[k].lines[0].pv
    if not owner_pv:
        return None
    sig = extract_signature(owner_board, owner_pv, s)
    if sig is None:
        return None
    owner = owner_board.turn

    def squares_at(j: int) -> tuple[int, int]:
        att = track_back(game_steps[j:p], sig.attacker_square)
        tgt = sig.target_square if sig.target_kind == "square" else track_back(game_steps[j:p], sig.target_square)
        return att, tgt

    chain = [{"ply": p, "side": "white" if owner else "black", "present": True,
              "attacker": chess.square_name(sig.attacker_square),
              "target": chess.square_name(sig.target_square)}]
    start = p
    builders = []
    # У позиционной подписи («plan») цель — поле, куда фигуры приходят и так
    # постоянно; цепочка назад для неё была бы шумом, поэтому начало = наказание.
    j = p - 2 if sig.motif != "plan" else -1
    while j >= 0:
        board = analysed[j].board
        att, tgt = squares_at(j)
        piece = board.piece_at(att)
        if piece is None or piece.color != owner:
            break
        present = any(reaches(board, ln.pv, att, tgt, sig.target_kind, K) for ln in _lines_at(analysed, j))
        chain.append({"ply": j, "side": "white" if owner else "black", "present": present,
                      "attacker": chess.square_name(att), "target": chess.square_name(tgt)})
        if not present:
            break
        start = j
        if reaches(board, analysed[j].played.pv, att, tgt, sig.target_kind, K):
            builders.append(j)
        j -= 2

    miss = None
    distance = None
    if kind == "punishment":
        # Первый ход жертвы после начала идеи, где лучшая линия снимает идею, а сыгран не лучший ход.
        for m in range(start + 1, k + 1, 2):
            board = analysed[m].board
            att, tgt = squares_at(m)
            best = analysed[m].lines[0]
            stops = not reaches(board, best.pv, att, tgt, sig.target_kind, K + 1)
            if stops and records[m].step not in ("best", "forced"):
                miss = m
                break
        if miss is None:
            miss = k                     # зевок без предыстории
        distance = k - miss

    idea = Idea(
        kind=kind, punish_ply=k,
        owner="white" if owner else "black", victim="black" if owner else "white",
        signature=sig, start_ply=start, miss_ply=miss, distance=distance,
        chain=sorted(chain, key=lambda c: c["ply"]), builder_plies=sorted(builders),
    )
    idea.chunk = make_chunk(owner_board, owner_pv, sig, s)
    return idea


def make_chunk(board: chess.Board, pv: Sequence[str], sig: Signature, s: Settings) -> str:
    """Запись активного чанка идеи (простое решение для этапа 7): атакующий,
    цель, мотив и фигуры поддержки — фигуры владельца, которые ходят в линии
    до ключевого хода или бьют поле цели."""
    owner = board.turn
    support = {sq for sq in board.attackers(owner, sig.target_square) if sq != sig.attacker_square}
    b = board.copy(stack=False)
    steps: list[tuple[chess.Board, chess.Move]] = []
    for uci in pv[:s.idea_scan_plies]:
        m = chess.Move.from_uci(uci)
        if m not in b.legal_moves or b.san(m) == sig.key_san:
            break
        if b.turn == owner:
            origin = track_back(steps, m.from_square)
            if origin != sig.attacker_square:
                support.add(origin)
        steps.append((b.copy(stack=False), m))
        b.push(m)
    names = []
    for sq in sorted(support):
        p = board.piece_at(sq)
        if p is not None and p.color == owner and p.piece_type != chess.KING:
            names.append(f"{p.unicode_symbol()}{chess.square_name(sq)}")
    return sig.text() + (" | " + ", ".join(names) if names else "")


def find_ideas(analysed, records: list[MoveRecord], s: Settings) -> list[Idea]:
    ideas = []
    for r in records:
        if "theory" in r.flags or "book" in r.flags:
            continue
        if r.step in PUNISHING_STEPS:
            idea = build_chain(analysed, records, r.ply, s, "punishment")
        elif "pass" in r.flags:
            idea = build_chain(analysed, records, r.ply, s, "pass")
        elif r.subtype == "brilliant":
            idea = build_chain(analysed, records, r.ply, s, "brilliant")
        else:
            continue
        if idea is not None:
            ideas.append(idea)
    return ideas


def save_ideas(conn: sqlite3.Connection, game_id: int, ideas: list[Idea], s: Settings) -> None:
    conn.execute("DELETE FROM ideas WHERE game_id = ? AND settings_version = ? AND depth = ?",
                 (game_id, s.version, s.depth))
    for idea in ideas:
        conn.execute(
            """INSERT INTO ideas(game_id, settings_version, depth, kind, punish_ply, owner, victim,
                                 signature, start_ply, miss_ply, distance, chain, builder_plies, chunk)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (game_id, s.version, s.depth, idea.kind, idea.punish_ply, idea.owner, idea.victim,
             dumps(idea.signature.to_json()), idea.start_ply, idea.miss_ply, idea.distance,
             dumps(idea.chain), dumps(idea.builder_plies), idea.chunk),
        )
        conn.execute(
            """UPDATE move_records SET idea_signature = ?, idea_start_ply = ?, miss_ply = ?, distance = ?
               WHERE game_id = ? AND ply = ? AND settings_version = ? AND depth = ?""",
            (dumps(idea.signature.to_json()), idea.start_ply, idea.miss_ply, idea.distance,
             game_id, idea.punish_ply, s.version, s.depth),
        )
    conn.commit()
