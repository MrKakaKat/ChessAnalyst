"""Stockfish с кэшем в SQLite (8.2, шаги 2–3).

Корневой анализ: глубина D, MultiPV N — для каждой линии первый ход, оценка
(сантипешки или мат), WDL и главный вариант. Сыгранный ход вне MultiPV
оценивается отдельным поиском после хода с той же глубиной (знак меняется).
"""

from __future__ import annotations

import json
import sqlite3
from dataclasses import dataclass

import chess
import chess.engine

from .db import dumps
from .evals import DRAW, Eval, after_move_to_root
from .settings import Settings


@dataclass(frozen=True)
class Line:
    move: str          # uci
    eval: Eval         # с точки зрения ходящего, рамка «до хода»
    pv: list[str]      # uci, начиная с move

    def to_json(self) -> dict:
        return {"move": self.move, "eval": self.eval.to_json(), "pv": self.pv}

    @classmethod
    def from_json(cls, d: dict) -> "Line":
        return cls(move=d["move"], eval=Eval.from_json(d["eval"]), pv=list(d["pv"]))


def epd_key(board: chess.Board) -> str:
    return board.epd()


def _eval_from_info(info: dict, board: chess.Board) -> Eval:
    pov = info["score"].pov(board.turn)
    wdl = info.get("wdl")
    w = wdl.pov(board.turn) if wdl is not None else pov.wdl(model="sf16", ply=board.ply())
    wdl_t = (w.wins, w.draws, w.losses)
    if pov.is_mate():
        m = pov.mate()
        if m == 0:  # сторона на ходу заматована
            return Eval(cp=None, mate=-1, wdl=(0, 0, 1000))
        return Eval(cp=None, mate=m, wdl=wdl_t)
    return Eval(cp=pov.score(), mate=None, wdl=wdl_t)


def terminal_eval_after_move(board: chess.Board) -> Eval | None:
    """Оценка для игрока, только что сделавшего ход, если партия на этом кончилась."""
    if board.is_checkmate():
        return Eval(cp=None, mate=1, wdl=(1000, 0, 0))  # уже в рамке «до хода»
    if board.is_stalemate() or board.is_insufficient_material() or board.is_fivefold_repetition() \
            or board.is_seventyfive_moves():
        return DRAW
    return None


class Analyzer:
    def __init__(self, conn: sqlite3.Connection, settings: Settings):
        self.conn = conn
        self.s = settings
        self._engine: chess.engine.SimpleEngine | None = None
        self.engine_id = "?"
        self.stats = {"cache_hits": 0, "searches": 0}

    # --- жизненный цикл ---

    def _open(self) -> chess.engine.SimpleEngine:
        if self._engine is None:
            eng = chess.engine.SimpleEngine.popen_uci(self.s.engine_path)
            opts = {}
            if "UCI_ShowWDL" in eng.options:
                opts["UCI_ShowWDL"] = True
            if "Threads" in eng.options:
                opts["Threads"] = self.s.threads
            if "Hash" in eng.options:
                opts["Hash"] = self.s.hash_mb
            eng.configure(opts)
            self._engine = eng
            self.engine_id = eng.id.get("name", "?")
        return self._engine

    def close(self) -> None:
        if self._engine is not None:
            self._engine.quit()
            self._engine = None

    def __enter__(self) -> "Analyzer":
        return self

    def __exit__(self, *exc) -> None:
        self.close()

    # --- корневой анализ ---

    def root_lines(self, board: chess.Board, depth: int | None = None,
                   multipv: int | None = None) -> list[Line]:
        """MultiPV в корне. Если все линии попали в зону «практически равен
        лучшему», пяти мало для only move и состава зоны B (вопрос из раздела 13):
        поиск повторяется с multipv_max линиями."""
        depth = depth or self.s.depth
        n_legal = board.legal_moves.count()
        want = min(multipv or self.s.multipv, n_legal)
        cached = self._cached(board, depth, want)
        if cached is not None:
            return cached
        lines = self._search(board, depth, want)
        if multipv is None and len(lines) == want < n_legal and self._zone_is_full(lines):
            want = min(self.s.multipv_max, n_legal)
            lines = self._search(board, depth, want)
        self._store(board, depth, len(lines), lines)
        return lines

    def all_moves(self, board: chess.Board, depth: int | None = None) -> list[Line]:
        """Все легальные ходы на малой глубине — для сигнала «тривиальная позиция»."""
        depth = depth or self.s.trivial_depth
        n_legal = board.legal_moves.count()
        cached = self._cached(board, depth, n_legal)
        if cached is not None:
            return cached
        lines = self._search(board, depth, n_legal)
        self._store(board, depth, n_legal, lines)
        return lines

    def _zone_is_full(self, lines: list[Line]) -> bool:
        best, last = lines[0].eval, lines[-1].eval
        if best.mate is not None or last.mate is not None:
            return best.structurally_equal(last)
        return (best.pawns(self.s) - last.pawns(self.s) <= self.s.pawns.eps2
                or best.expected - last.expected <= self.s.wdl.eps2)

    def _cached(self, board: chess.Board, depth: int, want: int) -> list[Line] | None:
        row = self.conn.execute(
            "SELECT multipv, lines FROM engine_cache WHERE epd = ? AND depth = ?", (epd_key(board), depth)
        ).fetchone()
        if row and row["multipv"] >= want:
            self.stats["cache_hits"] += 1
            return [Line.from_json(d) for d in json.loads(row["lines"])]
        return None

    def _search(self, board: chess.Board, depth: int, multipv: int) -> list[Line]:
        eng = self._open()
        limit = chess.engine.Limit(depth=depth, time=self.s.time_per_position)
        infos = eng.analyse(board, limit, multipv=multipv)
        self.stats["searches"] += 1
        lines = []
        for info in infos:
            if not info.get("pv"):
                continue
            pv = [m.uci() for m in info["pv"]]
            lines.append(Line(move=pv[0], eval=_eval_from_info(info, board), pv=pv))
        return lines

    def _store(self, board: chess.Board, depth: int, multipv: int, lines: list[Line]) -> None:
        self.conn.execute(
            "INSERT OR REPLACE INTO engine_cache(epd, depth, multipv, engine, lines) VALUES (?,?,?,?,?)",
            (epd_key(board), depth, multipv, self.engine_id, dumps([l.to_json() for l in lines])),
        )
        self.conn.commit()

    # --- оценка сыгранного хода ---

    def played_line(self, board: chess.Board, move: chess.Move, lines: list[Line],
                    depth: int | None = None) -> Line:
        """Линия сыгранного хода в рамке «до хода» с точки зрения ходящего."""
        for line in lines:
            if line.move == move.uci():
                return line

        depth = depth or self.s.depth
        key = epd_key(board)
        row = self.conn.execute(
            "SELECT eval, pv FROM played_cache WHERE epd = ? AND depth = ? AND move = ?",
            (key, depth, move.uci()),
        ).fetchone()
        if row:
            self.stats["cache_hits"] += 1
            return Line(move=move.uci(), eval=Eval.from_json(json.loads(row["eval"])),
                        pv=json.loads(row["pv"]))

        after = board.copy(stack=False)
        after.push(move)
        terminal = terminal_eval_after_move(after)
        if terminal is not None:
            line = Line(move=move.uci(), eval=terminal, pv=[move.uci()])
        else:
            eng = self._open()
            info = eng.analyse(after, chess.engine.Limit(depth=depth, time=self.s.time_per_position))
            self.stats["searches"] += 1
            ev = after_move_to_root(_eval_from_info(info, after).negate())
            pv = [move.uci()] + [m.uci() for m in info.get("pv", [])]
            line = Line(move=move.uci(), eval=ev, pv=pv)

        self.conn.execute(
            "INSERT OR REPLACE INTO played_cache(epd, depth, move, engine, eval, pv) VALUES (?,?,?,?,?,?)",
            (key, depth, move.uci(), self.engine_id, dumps(line.eval.to_json()), dumps(line.pv)),
        )
        self.conn.commit()
        return line
