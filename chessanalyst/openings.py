"""Opening book: positions from the Lichess opening tables (CC0).

Source: data/openings.tsv (eco, name, pgn), taken from the Lichess chess-openings
tables as embedded in the chess-openings-graph package (MIT). The book is the
set of all positions on those lines, keyed by EPD; named positions keep their
opening name.

A move is a book move when it is played while the game is still in the book
(every earlier move was a book move) and the position after it is a book
position. Book moves get their own step, "book", instead of the engine verdict:
gambits early in the game are theory, not inaccuracies.
"""

from __future__ import annotations

import csv
import json
from functools import lru_cache
from pathlib import Path

import chess

DATA = Path(__file__).resolve().parent / "data" / "openings_book.json"
WEIGHTS = Path(__file__).resolve().parent / "data" / "openings_weights.json"
TSV = Path(__file__).resolve().parent.parent / "data" / "openings.tsv"


def build_book(tsv: Path = TSV) -> dict[str, str]:
    """EPD -> opening name ("" for positions inside a line that have no name)."""
    book: dict[str, str] = {}
    with tsv.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            board = chess.Board()
            tokens = [t for t in row["pgn"].split() if not t.endswith(".")]
            for san in tokens:
                board.push_san(san)
                book.setdefault(board.epd(), "")
            book[board.epd()] = row["name"]
    return book


def build_weights(tsv: Path = TSV) -> dict[str, int]:
    """EPD -> number of named book lines passing through the position.

    The tables have no game counts; the number of studied lines through a
    position stands in for its popularity (1.e4 and 1.d4 lead)."""
    weights: dict[str, int] = {}
    with tsv.open(encoding="utf-8", newline="") as f:
        for row in csv.DictReader(f, delimiter="\t"):
            board = chess.Board()
            seen = set()
            for san in (t for t in row["pgn"].split() if not t.endswith(".")):
                board.push_san(san)
                seen.add(board.epd())
            for epd in seen:
                weights[epd] = weights.get(epd, 0) + 1
    return weights


def write_book(path: Path = DATA, weights_path: Path = WEIGHTS) -> dict[str, str]:
    book = build_book()
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(book, ensure_ascii=False, separators=(",", ":"), sort_keys=True),
                    encoding="utf-8")
    weights_path.write_text(json.dumps(build_weights(), separators=(",", ":"), sort_keys=True), encoding="utf-8")
    return book


@lru_cache(maxsize=1)
def load_weights() -> dict[str, int]:
    return json.loads(WEIGHTS.read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def load_book() -> dict[str, str]:
    return json.loads(DATA.read_text(encoding="utf-8"))


ALIEN = "Caro-Kann Defense: Alien Gambit"


def alien_gambit(board: chess.Board, move: chess.Move, name: str, ply: int) -> bool:
    """White's knight from g5 takes on f7 early in a Caro-Kann."""
    if ply >= 20 or "Caro-Kann" not in name or move.uci() != "g5f7":
        return False
    piece = board.piece_at(chess.G5)
    target = board.piece_at(chess.F7)
    return piece == chess.Piece(chess.KNIGHT, chess.WHITE) and target is not None and target.color == chess.BLACK


def book_names(start_fen: str, ucis: list[str], book: dict[str, str] | None = None) -> list[str | None]:
    """For each ply: the opening name if the move is a book move, else None.

    The name is the deepest named position reached so far on the book line."""
    book = load_book() if book is None else book
    board = chess.Board(start_fen)
    if board.fen() != chess.STARTING_FEN:
        return [None] * len(ucis)
    out: list[str | None] = []
    in_book = True
    name = ""
    for i, uci in enumerate(ucis):
        move = chess.Move.from_uci(uci)
        # [авторское] Alien Gambit: жертва коня Ng5xf7 в Каро-Канн — в любой
        # системе (книга знает её только после 4...Nf6)
        if alien_gambit(board, move, name, i):
            board.push(move)
            name = ALIEN
            out.append(name)
            in_book = False
            continue
        board.push(move)
        epd = board.epd()
        if in_book and epd in book:
            name = book[epd] or name
            out.append(name)
        else:
            in_book = False
            out.append(None)
    return out
