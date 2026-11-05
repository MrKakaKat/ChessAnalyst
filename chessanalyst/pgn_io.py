"""Загрузка PGN в базу (8.2, шаг 1)."""

from __future__ import annotations

import hashlib
import io
import sqlite3
from pathlib import Path

import chess
import chess.pgn


def _normalized_pgn(game: chess.pgn.Game) -> str:
    exporter = chess.pgn.StringExporter(headers=True, variations=False, comments=False)
    return game.accept(exporter)


def load_pgn_text(conn: sqlite3.Connection, text: str) -> list[int]:
    """Добавляет все партии из текста PGN. Возвращает id (новых и уже бывших)."""
    ids: list[int] = []
    stream = io.StringIO(text)
    while True:
        game = chess.pgn.read_game(stream)
        if game is None:
            break
        if game.errors:
            raise ValueError(f"PGN parse error: {game.errors[0]}")
        ids.append(_insert_game(conn, game))
    conn.commit()
    return ids


def load_pgn_file(conn: sqlite3.Connection, path: str | Path) -> list[int]:
    return load_pgn_text(conn, Path(path).read_text(encoding="utf-8", errors="replace"))


def _insert_game(conn: sqlite3.Connection, game: chess.pgn.Game) -> int:
    pgn = _normalized_pgn(game)
    pgn_hash = hashlib.sha1(pgn.encode()).hexdigest()
    row = conn.execute("SELECT id FROM games WHERE pgn_hash = ?", (pgn_hash,)).fetchone()
    if row:
        return row["id"]

    h = game.headers
    board = game.board()
    cur = conn.execute(
        """INSERT INTO games(event, site, date, round, white, black, result,
                             start_fen, pgn, pgn_hash)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (h.get("Event"), h.get("Site"), h.get("Date"), h.get("Round"),
         h.get("White"), h.get("Black"), h.get("Result"),
         board.fen(), pgn, pgn_hash),
    )
    game_id = cur.lastrowid

    rows = []
    for ply, move in enumerate(game.mainline_moves()):
        rows.append((
            game_id, ply,
            "white" if board.turn == chess.WHITE else "black",
            board.fullmove_number,
            board.san(move), move.uci(), board.fen(),
        ))
        board.push(move)
    conn.executemany(
        "INSERT INTO plies(game_id, ply, side, move_no, san, uci, fen_before) VALUES (?,?,?,?,?,?,?)",
        rows,
    )
    return game_id


def game_label(row: sqlite3.Row) -> str:
    return f"#{row['id']} {row['white']} – {row['black']}, {row['event'] or '?'} {row['date'] or ''}".strip()
