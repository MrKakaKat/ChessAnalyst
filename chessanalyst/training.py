"""Тренировочные режимы без игры: «покажи своё продолжение» (9.2), библиотека
идей (9.5), определение меток и освоение (10), поиск начала идеи, итог дня."""

from __future__ import annotations

import json
import random
import re
import sqlite3
from datetime import date

import chess

from . import features
from .db import award, dumps
from .settings import Settings

# --- 9.2 «Покажи своё продолжение» ---

KIND_LABELS = {"capture": "взятие", "check": "шах", "defense": "защита", "quiet": "тихий ход",
               "mate_threat": "угроза мата", "match": "совпало"}


def parse_line(board: chess.Board, text: str | list[str]) -> list[str]:
    """SAN или UCI через пробел (номера ходов игнорируются) → список uci."""
    tokens = text if isinstance(text, list) else re.split(r"\s+", text.strip())
    b = board.copy(stack=False)
    out = []
    for t in tokens:
        t = re.sub(r"^\d+\.(\.\.)?", "", t).strip()
        if not t or t in ("...", "..", "."):
            continue
        try:
            m = chess.Move.from_uci(t)
            if m not in b.legal_moves:
                raise ValueError
        except ValueError:
            m = b.parse_san(t)
        out.append(m.uci())
        b.push(m)
    return out


def move_kind(board: chess.Board, move: chess.Move, s: Settings) -> str:
    if board.gives_check(move):
        return "check"
    if board.is_capture(move):
        return "capture"
    if features.creates_mate_threat(board, move):
        return "mate_threat"
    if "defense" in features.positional_subtypes(board, move, s):
        return "defense"
    return "quiet"


def compare_continuation(board: chess.Board, user_line: list[str], engine_line: list[str],
                         s: Settings) -> dict:
    """board — позиция после своего хода (на ходу соперник).

    Первое расхождение и его характер: чей это был ход (ответ соперника или
    свой) и что сделал ход движка, которого не было во вводе."""
    b = board.copy(stack=False)
    me = not board.turn
    n = min(len(user_line), len(engine_line))
    for i in range(n):
        if user_line[i] != engine_line[i]:
            em = chess.Move.from_uci(engine_line[i])
            um = chess.Move.from_uci(user_line[i])
            return {
                "diverge_index": i,
                "diverge_side": "self" if b.turn == me else "opponent",
                "diverge_kind": move_kind(b, em, s),
                "engine_move": b.san(em),
                "user_move": b.san(um) if um in b.legal_moves else user_line[i],
            }
        b.push(chess.Move.from_uci(engine_line[i]))
    return {"diverge_index": None, "diverge_side": None, "diverge_kind": "match",
            "engine_move": None, "user_move": None}


def save_continuation(conn: sqlite3.Connection, source: str, ref: str | None, board: chess.Board,
                      user_line: list[str], engine_line: list[str], result: dict) -> None:
    conn.execute(
        """INSERT INTO continuations(source, ref, fen, user_line, engine_line, diverge_index,
                                     diverge_side, diverge_kind, user_move, engine_move)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (source, ref, board.fen(), dumps(user_line), dumps(engine_line), result["diverge_index"],
         result["diverge_side"], result["diverge_kind"], result["user_move"], result["engine_move"]),
    )
    conn.commit()
    award(conn, "continuation", 1, ref)


# --- 9.5 Библиотека идей ---

def add_to_library(conn: sqlite3.Connection, title: str, fen: str, key_line: list[str], *,
                   game_id: int | None = None, ply: int | None = None, signature: dict | None = None,
                   chunk: str | None = None, stage: str | None = None, note: str | None = None,
                   locus: str | None = None) -> int:
    cur = conn.execute(
        """INSERT INTO library(title, fen, key_line, game_id, ply, signature, chunk, stage, note, locus)
           VALUES (?,?,?,?,?,?,?,?,?,?)""",
        (title, fen, dumps(key_line), game_id, ply, dumps(signature) if signature else None,
         chunk, stage, note, locus),
    )
    conn.commit()
    award(conn, "idea_saved", 1, str(cur.lastrowid))
    return cur.lastrowid


def library_items(conn: sqlite3.Connection) -> list[dict]:
    rows = conn.execute(
        """SELECT l.*, COUNT(r.id) AS reviews, COALESCE(MAX(r.line_score), 0) AS best_score
           FROM library l LEFT JOIN library_reviews r ON r.library_id = l.id
           GROUP BY l.id ORDER BY l.id DESC""").fetchall()
    out = []
    for r in rows:
        d = dict(r)
        d["key_line"] = json.loads(d["key_line"])
        d["signature"] = json.loads(d["signature"]) if d["signature"] else None
        out.append(d)
    return out


def next_training_item(conn: sqlite3.Connection, rng: random.Random | None = None) -> dict | None:
    """Случайный порядок; сначала — те, что повторялись реже."""
    items = library_items(conn)
    if not items:
        return None
    rng = rng or random.Random()
    least = min(i["reviews"] for i in items)
    return rng.choice([i for i in items if i["reviews"] == least])


_PIECE_TOKEN = re.compile(r"^([KQRBNPkqrbnp])([a-h][1-8])$")


def recall_score(fen: str, text: str) -> float:
    """Воспроизведение позиции по памяти: список фигур «Kg1 Qd1 Pa2 ke8 nd7»
    (белые заглавными, чёрные строчными). Мера — Жаккар множеств (фигура, поле)."""
    truth = {(p.symbol(), sq) for sq, p in chess.Board(fen).piece_map().items()}
    given = set()
    for tok in text.split():
        m = _PIECE_TOKEN.match(tok)
        if m:
            given.add((m.group(1), chess.parse_square(m.group(2))))
    if not truth and not given:
        return 1.0
    return len(truth & given) / len(truth | given)


def review_library_item(conn: sqlite3.Connection, item_id: int, given_line: str,
                        recall_text: str | None = None) -> dict:
    row = conn.execute("SELECT * FROM library WHERE id = ?", (item_id,)).fetchone()
    if row is None:
        raise KeyError(item_id)
    key = json.loads(row["key_line"])
    board = chess.Board(row["fen"])
    try:
        given = parse_line(board, given_line)
    except ValueError:
        given = []
    matched = 0
    for a, b in zip(given, key):
        if a != b:
            break
        matched += 1
    line_score = matched / len(key) if key else 1.0
    rec = recall_score(row["fen"], recall_text) if recall_text else None
    conn.execute("INSERT INTO library_reviews(library_id, line_score, recall_score, given) VALUES (?,?,?,?)",
                 (item_id, line_score, rec, given_line))
    conn.commit()
    if line_score == 1.0:
        award(conn, "library_success", 1, str(item_id))
    b = board.copy(stack=False)
    key_san = []
    for u in key:
        m = chess.Move.from_uci(u)
        key_san.append(b.san(m))
        b.push(m)
    return {"line_score": line_score, "recall_score": rec, "matched": matched, "key_san": key_san}


# --- 10 Освоение: определение метки без подсказки ---

QUIZ_STEPS = ("best", "excellent", "good", "neutral", "inaccuracy", "pass", "laxity", "mistake", "blunder")


def quiz_question(conn: sqlite3.Connection, rng: random.Random | None = None,
                  steps: tuple[str, ...] | None = None) -> dict | None:
    """Ход из разобранных партий, который ещё не встречался в викторине («новые позиции»)."""
    rng = rng or random.Random()
    rows = conn.execute(
        """SELECT m.game_id, m.ply, m.settings_version, m.fen_before, m.san, m.uci, m.step, m.side
           FROM move_records m
           WHERE NOT EXISTS (SELECT 1 FROM quiz_attempts q WHERE q.game_id = m.game_id AND q.ply = m.ply)
             AND m.flags NOT LIKE '%"theory"%' AND m.flags NOT LIKE '%"trivial"%'
             AND m.step NOT IN ('forced', 'book')""").fetchall()
    if steps:
        rows = [r for r in rows if r["step"] in steps]
    if not rows:
        return None
    # Ошибки встречаются реже лучших ходов — уравниваем: сначала случайная ступень.
    by_step: dict[str, list] = {}
    for r in rows:
        by_step.setdefault(r["step"], []).append(r)
    r = rng.choice(rng.choice(list(by_step.values())))
    return {"game_id": r["game_id"], "ply": r["ply"], "settings_version": r["settings_version"],
            "fen": r["fen_before"], "san": r["san"], "uci": r["uci"], "side": r["side"]}


def quiz_answer(conn: sqlite3.Connection, game_id: int, ply: int, settings_version: str, answer: str) -> dict:
    row = conn.execute(
        "SELECT step, best_moves FROM move_records WHERE game_id = ? AND ply = ? AND settings_version = ? "
        "ORDER BY depth DESC LIMIT 1", (game_id, ply, settings_version)).fetchone()
    if row is None:
        raise KeyError((game_id, ply))
    correct = int(answer == row["step"])
    conn.execute(
        "INSERT INTO quiz_attempts(game_id, ply, settings_version, answer, truth, correct) VALUES (?,?,?,?,?,?)",
        (game_id, ply, settings_version, answer, row["step"], correct))
    conn.commit()
    if correct:
        award(conn, "quiz_correct", 1, f"{game_id}:{ply}")
    return {"correct": bool(correct), "truth": row["step"],
            "best": [b["san"] for b in json.loads(row["best_moves"])]}


def mastery(conn: sqlite3.Connection, s: Settings) -> dict[str, dict]:
    """Тип освоен, если верно определён в новых позициях mastery_required раз.
    Неверные ответы освоение не отнимают: откатов навыков нет."""
    out = {}
    for step in QUIZ_STEPS:
        row = conn.execute(
            "SELECT COUNT(*) AS n, COALESCE(SUM(correct), 0) AS ok FROM quiz_attempts WHERE truth = ?",
            (step,)).fetchone()
        out[step] = {"attempts": row["n"], "correct": row["ok"],
                     "mastered": row["ok"] >= s.mastery_required, "required": s.mastery_required}
    return out


# --- Поиск начала идеи (награда за процесс) ---

def guess_idea_start(conn: sqlite3.Connection, idea_id: int, guess_ply: int) -> dict:
    """Пользователь указывает позицию, где, по его мнению, идея появилась.
    Засчитывается точное попадание или соседняя позиция владельца (±2 полухода)."""
    row = conn.execute("SELECT * FROM ideas WHERE id = ?", (idea_id,)).fetchone()
    if row is None:
        raise KeyError(idea_id)
    ok = abs(guess_ply - row["start_ply"]) <= 2
    if ok:
        award(conn, "idea_start_found", 2, str(idea_id))
    return {"correct": ok, "start_ply": row["start_ply"], "miss_ply": row["miss_ply"],
            "distance": row["distance"]}


# --- 10 День = сюжет ---

def today() -> str:
    return date.today().isoformat()


def day_summary(conn: sqlite3.Connection, day: str | None = None) -> dict:
    day = day or today()
    pts = conn.execute(
        "SELECT kind, SUM(points) AS p, COUNT(*) AS n FROM events WHERE date(created_at, 'localtime') = ? "
        "GROUP BY kind", (day,)).fetchall()
    total = conn.execute("SELECT COALESCE(SUM(points), 0) FROM events").fetchone()[0]
    story = conn.execute("SELECT * FROM stories WHERE day = ?", (day,)).fetchone()
    # Подсказка для главной находки: идея с наибольшей дистанцией в партиях, открытых сегодня.
    suggestion = conn.execute(
        """SELECT i.id, i.game_id, i.chunk, i.distance FROM ideas i
           JOIN game_state g ON g.game_id = i.game_id
           WHERE date(g.updated_at, 'localtime') = ? AND i.kind = 'punishment'
           ORDER BY i.distance DESC, i.id DESC LIMIT 1""", (day,)).fetchone()
    return {
        "day": day,
        "today": {r["kind"]: {"points": r["p"], "count": r["n"]} for r in pts},
        "today_points": sum(r["p"] for r in pts),
        "total_points": total,
        "story": dict(story) if story else None,
        "suggestion": dict(suggestion) if suggestion else None,
    }


def save_story(conn: sqlite3.Connection, finding: str, game_id: int | None = None,
               idea_id: int | None = None, day: str | None = None) -> None:
    conn.execute("INSERT OR REPLACE INTO stories(day, game_id, idea_id, finding) VALUES (?,?,?,?)",
                 (day or today(), game_id, idea_id, finding))
    conn.commit()
    award(conn, "story", 1, day or today())


def touch_game(conn: sqlite3.Connection, game_id: int, ply: int) -> None:
    """Запомнить, где остановился в партии (9.6)."""
    conn.execute(
        "INSERT INTO game_state(game_id, cursor_ply, updated_at) VALUES (?, ?, datetime('now')) "
        "ON CONFLICT(game_id) DO UPDATE SET cursor_ply = excluded.cursor_ply, updated_at = excluded.updated_at",
        (game_id, ply))
    conn.commit()
