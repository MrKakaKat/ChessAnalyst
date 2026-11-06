"""Конвейер: партия из базы → анализ движком → классификация → move_records."""

from __future__ import annotations

import json
import sqlite3
import time
from collections.abc import Callable
from dataclasses import dataclass

import chess

from .classify import MoveRecord, classify, trivial_candidate
from .db import dumps
from .engine import Analyzer, Line
from .ideas import find_ideas, save_ideas
from .openings import book_names
from .settings import Settings

Progress = Callable[[int, int], None]


def game_plies(conn: sqlite3.Connection, game_id: int) -> list[sqlite3.Row]:
    return conn.execute(
        "SELECT * FROM plies WHERE game_id = ? ORDER BY ply", (game_id,)
    ).fetchall()


@dataclass
class PlyAnalysis:
    board: chess.Board
    lines: list[Line]
    played: Line
    all_lines: list[Line] | None = None


def analyze_game(analyzer: Analyzer, game_id: int, progress: Progress | None = None
                 ) -> list[PlyAnalysis]:
    """Корневой MultiPV для каждой позиции и оценка сыгранного хода. Всё кэшируется."""
    plies = game_plies(analyzer.conn, game_id)
    out = []
    for i, row in enumerate(plies):
        board = chess.Board(row["fen_before"])
        lines = analyzer.root_lines(board)
        played = analyzer.played_line(board, chess.Move.from_uci(row["uci"]), lines)
        n_legal = board.legal_moves.count()
        all_lines = analyzer.all_moves(board) if trivial_candidate(lines, n_legal, analyzer.s) else None
        out.append(PlyAnalysis(board, lines, played, all_lines))
        if progress:
            progress(i + 1, len(plies))
    analyzer.conn.execute("UPDATE games SET status = 'analyzed' WHERE id = ? AND status = 'queued'",
                          (game_id,))
    analyzer.conn.commit()
    return out


def classify_game(analyzer: Analyzer, game_id: int, progress: Progress | None = None
                  ) -> list[MoveRecord]:
    s = analyzer.s
    analysed = analyze_game(analyzer, game_id, progress)
    records = classify_analysed(analysed, s)
    save_records(analyzer.conn, game_id, records, s)
    save_ideas(analyzer.conn, game_id, find_ideas(analysed, records, s), s)
    return records


def classify_analysed(analysed: list[PlyAnalysis], s: Settings) -> list[MoveRecord]:
    """Метки по данным движка; ходы по книге дебютов получают ступень book."""
    openings = book_names(analysed[0].board.fen(), [a.played.move for a in analysed]) if analysed else []
    records = []
    for ply, a in enumerate(analysed):
        # E0 игрока — это корневая оценка соперника на предыдущем полуходе.
        prev_root = analysed[ply - 1].lines[0].eval if ply >= 1 else None
        records.append(classify(a.board, a.lines, a.played, prev_root, s, ply=ply, all_lines=a.all_lines,
                                opening=openings[ply],
                                continuation=[x.played.move for x in analysed[ply + 1:ply + 7]]))
    desperado(analysed, records)
    return records


def desperado(analysed: list[PlyAnalysis], records: list[MoveRecord]) -> None:
    """«Бешеная» фигура: жертвы с шахом одной и той же фигурой подряд (обычно
    ладья, ищущая пат или вечный шах). Блестящим считается только первый ход
    цепочки, и лишь когда ничья после него обеспечена (оценка около нуля, до
    0,3 пешки); иначе он — единственный ход (only_move). Следующие её шахи —
    единственные ходы облегчённые (only_light)."""
    def checks(i: int) -> tuple[int, int] | None:
        if i < 0 or i >= len(analysed):
            return None
        board = analysed[i].board
        m = chess.Move.from_uci(analysed[i].played.move)
        return (m.from_square, m.to_square) if board.gives_check(m) else None

    for i, r in enumerate(records):
        if r.subtype != "brilliant":
            continue
        me = checks(i)
        if me is None:
            continue
        prev = checks(i - 2)
        if prev is not None and prev[1] == me[0]:
            r.subtype = "only_light"
            continue
        nxt = checks(i + 2)
        if nxt is not None and nxt[0] == me[1] and abs(r.pawns.ep) > 0.3:
            r.subtype = "only_move"


def save_records(conn: sqlite3.Connection, game_id: int, records: list[MoveRecord], s: Settings) -> None:
    conn.execute("DELETE FROM move_records WHERE game_id = ? AND settings_version = ? AND depth = ?",
                 (game_id, s.version, s.depth))
    conn.executemany(
        """INSERT INTO move_records(
            game_id, ply, settings_version, depth, unit, side, san, uci, fen_before,
            e0, e1, ep,
            e0_pawns, e1_pawns, ep_pawns, g_pawns, d_pawns, l_pawns,
            e0_wdl, e1_wdl, ep_wdl, g_wdl, d_wdl, l_wdl,
            cat_e0, cat_e1, cat_ep, step, decided_by, unit_steps, subtype, move_type, type_subtypes, flags,
            best_moves, near_best_moves, stage, opening, engine_step)
           VALUES (?,?,?,?,?,?,?,?,?, ?,?,?, ?,?,?,?,?,?, ?,?,?,?,?,?, ?,?,?,?,?,?,?,?,?,?, ?,?,?,?,?)""",
        [(
            game_id, r.ply, s.version, s.depth, s.unit, r.side, r.san, r.uci, r.fen_before,
            dumps(r.e0.to_json()) if r.e0 else None, dumps(r.e1.to_json()), dumps(r.ep.to_json()),
            r.pawns.e0, r.pawns.e1, r.pawns.ep, r.pawns.g, r.pawns.d, r.pawns.l,
            r.wdl.e0, r.wdl.e1, r.wdl.ep, r.wdl.g, r.wdl.d, r.wdl.l,
            r.cat_e0, r.cat_e1, r.cat_ep, r.step, r.decided_by, dumps(r.unit_steps), r.subtype, r.move_type,
            dumps(r.type_subtypes), dumps(r.flags),
            dumps(r.best_moves), dumps(r.near_best_moves), r.stage, r.opening, r.engine_step,
        ) for r in records],
    )
    conn.execute("UPDATE games SET status = 'classified' WHERE id = ?", (game_id,))
    conn.commit()


def timed(fn, *a, **kw):
    t = time.monotonic()
    res = fn(*a, **kw)
    return res, time.monotonic() - t


def stability(analyzer: Analyzer, game_id: int, depths: tuple[int, int],
              progress: Progress | None = None) -> dict:
    """Проверка стабильности меток (6.7, 12): та же партия на двух глубинах.

    Возвращает долю совпавших ступеней и составов зоны A и список расхождений."""
    from dataclasses import replace

    base = analyzer.s
    runs = []
    for d in depths:
        analyzer.s = replace(base, depth=d)
        try:
            runs.append(classify_game(analyzer, game_id, progress))
        finally:
            analyzer.s = base
    a, b = runs
    diffs = []
    same_step = same_best = 0
    for ra, rb in zip(a, b):
        best_a = {m["uci"] for m in ra.best_moves}
        best_b = {m["uci"] for m in rb.best_moves}
        same_step += ra.step == rb.step
        same_best += best_a == best_b
        if ra.step != rb.step or best_a != best_b:
            diffs.append({"ply": ra.ply, "san": ra.san, "steps": [ra.step, rb.step],
                          "best": [sorted(best_a), sorted(best_b)]})
    n = max(len(a), 1)
    return {"depths": list(depths), "plies": len(a), "step_agreement": same_step / n,
            "best_set_agreement": same_best / n, "diffs": diffs}


def latest_run(conn: sqlite3.Connection, game_id: int) -> tuple[str, int] | None:
    """(версия настроек, глубина) последнего прогона партии."""
    row = conn.execute(
        """SELECT settings_version, depth, MAX(created_at) AS t FROM move_records WHERE game_id = ?
           GROUP BY settings_version, depth ORDER BY t DESC LIMIT 1""", (game_id,)).fetchone()
    return (row["settings_version"], row["depth"]) if row else None


def load_records(conn: sqlite3.Connection, game_id: int, version: str | None = None,
                 depth: int | None = None) -> list[dict]:
    """Записи ходов прогона как словари с разобранными JSON-полями."""
    if version is None or depth is None:
        run = latest_run(conn, game_id)
        if run is None:
            return []
        version, depth = run
    rows = conn.execute(
        "SELECT * FROM move_records WHERE game_id = ? AND settings_version = ? AND depth = ? ORDER BY ply",
        (game_id, version, depth)).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        for k in ("e0", "e1", "ep", "type_subtypes", "flags", "best_moves", "near_best_moves",
                  "unit_steps", "idea_signature"):
            if d.get(k):
                d[k] = json.loads(d[k])
        out.append(d)
    return out


def load_ideas(conn: sqlite3.Connection, game_id: int, version: str, depth: int) -> list[dict]:
    rows = conn.execute(
        "SELECT * FROM ideas WHERE game_id = ? AND settings_version = ? AND depth = ? ORDER BY punish_ply",
        (game_id, version, depth)).fetchall()
    out = []
    for r in rows:
        d = dict(r)
        for k in ("signature", "chain", "builder_plies"):
            d[k] = json.loads(d[k])
        out.append(d)
    return out
