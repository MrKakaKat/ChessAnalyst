"""Свободная игра против компьютера (9.3) и имитация человека (этап 7).

Компьютер из выигрышной для человека позиции намеренно уходит с главной линии:
с вероятностью play_deviation_rate выбирает ход из MultiPV, который хуже лучшего
(неточность или laxity), но не меняет категорию — позиция остаётся играбельной,
а задача человека — реализовать перевес.

Имитация человека, простое решение: если human_temperature > 0, ход выбирается
softmax-ом по оценкам MultiPV (чем выше температура, тем «человечнее» и слабее).
Если задан human_engine_path (lc0 с весами Maia), ход берёт он, поиск nodes=1 —
так Maia и предполагает использование.
"""

from __future__ import annotations

import json
import math
import random
import sqlite3

import chess
import chess.engine

from .classify import classify
from .db import dumps
from .engine import Analyzer, Line
from .evals import category
from .settings import Settings


def choose_move(lines: list[Line], s: Settings, rng: random.Random) -> tuple[Line, bool]:
    """(линия, ушёл ли компьютер с главной линии)."""
    best = lines[0]
    if s.human_temperature > 0 and len(lines) > 1:
        vals = [ln.eval.pawns(s) for ln in lines]
        top = max(vals)
        weights = [math.exp((v - top) / s.human_temperature) for v in vals]
        pick = rng.choices(lines, weights=weights, k=1)[0]
        return pick, pick is not best
    p = s.params
    unit = s.class_unit
    c_best = category(best.eval.value(unit, s), p)
    candidates = []
    for ln in lines[1:]:
        loss = best.eval.pawns(s) - ln.eval.pawns(s)
        same_cat = category(ln.eval.value(unit, s), p) == c_best
        if s.pawns.eps2 < loss <= s.play_max_loss_pawns and same_cat:
            candidates.append(ln)
    if candidates and rng.random() < s.play_deviation_rate:
        return rng.choice(candidates), True
    return best, False


class PlaySession:
    def __init__(self, conn: sqlite3.Connection, analyzer: Analyzer, session_id: int,
                 rng: random.Random | None = None):
        self.conn = conn
        self.an = analyzer
        self.s = analyzer.s
        self.id = session_id
        self.rng = rng or random.Random()
        row = conn.execute("SELECT * FROM play_sessions WHERE id = ?", (session_id,)).fetchone()
        if row is None:
            raise KeyError(session_id)
        self.start_fen = row["start_fen"]
        self.human = chess.WHITE if row["human_color"] == "white" else chess.BLACK
        self.moves = json.loads(row["moves"])
        self.status = row["status"]

    @classmethod
    def start(cls, conn: sqlite3.Connection, analyzer: Analyzer, fen: str, source: str | None = None,
              rng: random.Random | None = None) -> "PlaySession":
        board = chess.Board(fen)
        color = "white" if board.turn == chess.WHITE else "black"
        cur = conn.execute("INSERT INTO play_sessions(start_fen, human_color, source) VALUES (?,?,?)",
                           (board.fen(), color, source))
        conn.commit()
        return cls(conn, analyzer, cur.lastrowid, rng)

    @property
    def board(self) -> chess.Board:
        b = chess.Board(self.start_fen)
        for m in self.moves:
            b.push(chess.Move.from_uci(m["uci"]))
        return b

    def _save(self) -> None:
        self.conn.execute("UPDATE play_sessions SET moves = ?, status = ? WHERE id = ?",
                          (dumps(self.moves), self.status, self.id))
        self.conn.commit()

    def _lines(self, board: chess.Board) -> list[Line]:
        return self.an.root_lines(board, depth=self.s.play_depth, multipv=self.s.play_multipv)

    def _finish_if_over(self, board: chess.Board) -> None:
        if board.is_game_over(claim_draw=True):
            self.status = "finished:" + board.result(claim_draw=True)

    def human_move(self, text: str) -> dict:
        """Ход человека (SAN или UCI) → его метка и ответ компьютера."""
        if self.status != "active":
            raise ValueError("партия закончена")
        board = self.board
        if board.turn != self.human:
            raise ValueError("сейчас ход компьютера")
        try:
            move = chess.Move.from_uci(text)
            if move not in board.legal_moves:
                raise ValueError
        except ValueError:
            move = board.parse_san(text)

        lines = self._lines(board)
        played = self.an.played_line(board, move, lines, depth=self.s.play_depth)
        prev_root = None
        if self.moves:
            prev = chess.Board(self.start_fen)
            for m in self.moves[:-1]:
                prev.push(chess.Move.from_uci(m["uci"]))
            prev_root = self._lines(prev)[0].eval
        rec = classify(board, lines, played, prev_root, self.s, ply=len(self.moves))
        self.moves.append({"uci": move.uci(), "san": board.san(move), "by": "human",
                           "step": rec.step, "flags": rec.flags,
                           "best": [b["san"] for b in rec.best_moves]})
        board.push(move)
        self._finish_if_over(board)
        reply = None
        if self.status == "active":
            reply = self.computer_move()
        self._save()
        return {"human": self.moves[-2] if reply else self.moves[-1], "computer": reply,
                "fen": self.board.fen(), "status": self.status}

    def computer_move(self) -> dict:
        board = self.board
        if self.s.human_engine_path:
            move, deviated = self._human_engine_move(board), False
        else:
            line, deviated = choose_move(self._lines(board), self.s, self.rng)
            move = chess.Move.from_uci(line.move)
        entry = {"uci": move.uci(), "san": board.san(move), "by": "computer", "deviated": deviated}
        self.moves.append(entry)
        board.push(move)
        self._finish_if_over(board)
        return entry

    def _human_engine_move(self, board: chess.Board) -> chess.Move:
        eng = chess.engine.SimpleEngine.popen_uci(self.s.human_engine_path)
        try:
            return eng.play(board, chess.engine.Limit(nodes=1)).move
        finally:
            eng.quit()

    def to_json(self) -> dict:
        b = chess.Board(self.start_fen)
        after_human = None
        for m in self.moves:
            b.push(chess.Move.from_uci(m["uci"]))
            if m["by"] == "human":
                after_human = b.fen()
        return {"id": self.id, "start_fen": self.start_fen, "fen": b.fen(), "fen_after_human": after_human,
                "human": "white" if self.human else "black", "moves": self.moves, "status": self.status}
