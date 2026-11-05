"""Задачи Lichess, проба «туман или слепота» и карта трудностей (разделы 5, 9.4).

Формат базы database.lichess.org (lichess_db_puzzle.csv[.zst]):
PuzzleId,FEN,Moves,Rating,RatingDeviation,Popularity,NbPlays,Themes,GameUrl,OpeningTags.
FEN — позиция до хода соперника; первый ход в Moves делает соперник, дальше решение.
"""

from __future__ import annotations

import csv
import io
import json
import math
import random
import shutil
import sqlite3
import statistics
import subprocess
from collections import Counter, defaultdict
from collections.abc import Iterable, Iterator
from datetime import datetime
from pathlib import Path

import chess

from .db import award, dumps, get_pref
from .settings import Settings

REASONS = {
    "calculation": "перебор вариантов",
    "hidden_move": "поиск неочевидного хода (жертвы или защиты)",
    "missed_defense": "пропущенный ресурс защиты",
    "blind_spot": "слепое пятно",
}

REASON_ADVICE = {
    "calculation": "задачи темы на время, решать до конца в уме, не двигая фигуры",
    "hidden_move": "перед решением перечислять все шахи, взятия и угрозы, включая «невозможные» жертвы",
    "missed_defense": "после найденного хода искать лучший ответ соперника, как будто играешь за него",
    "blind_spot": "лёгкие задачи той же темы сериями: цель — автоматическое узнавание, а не расчёт",
}

DEFAULT_RATING = 1500


# --- импорт ---

def _open_text(path: Path) -> io.TextIOBase:
    if path.suffix == ".zst":
        try:
            import zstandard  # type: ignore
            fh = open(path, "rb")
            return io.TextIOWrapper(zstandard.ZstdDecompressor().stream_reader(fh), encoding="utf-8")
        except ImportError:
            if shutil.which("zstd") is None:
                raise RuntimeError("для .zst нужен пакет zstandard или утилита zstd")
            proc = subprocess.Popen(["zstd", "-dc", str(path)], stdout=subprocess.PIPE)
            return io.TextIOWrapper(proc.stdout, encoding="utf-8")
    return open(path, encoding="utf-8", newline="")


def iter_rows(lines: Iterable[str]) -> Iterator[dict]:
    reader = csv.reader(lines)
    for row in reader:
        if not row or row[0] == "PuzzleId":
            continue
        row += [""] * (10 - len(row))
        yield {
            "id": row[0], "fen": row[1], "moves": row[2], "rating": int(row[3]),
            "rating_dev": int(row[4] or 0), "popularity": int(row[5] or 0), "nb_plays": int(row[6] or 0),
            "themes": row[7], "game_url": row[8], "opening": row[9],
        }


def import_puzzles(conn: sqlite3.Connection, source: str | Path | Iterable[str], *,
                   themes: set[str] | None = None, min_rating: int = 0, max_rating: int = 4000,
                   min_popularity: int = -100, limit: int | None = None) -> int:
    """Импорт с фильтрами по темам (любая из), рейтингу и популярности."""
    if isinstance(source, (str, Path)):
        fh = _open_text(Path(source))
        lines: Iterable[str] = fh
    else:
        fh, lines = None, source
    n = 0
    try:
        batch = []
        for r in iter_rows(lines):
            if not (min_rating <= r["rating"] <= max_rating) or r["popularity"] < min_popularity:
                continue
            if themes and not themes & set(r["themes"].split()):
                continue
            batch.append(tuple(r.values()))
            n += 1
            if len(batch) >= 5000:
                _insert(conn, batch)
                batch = []
            if limit and n >= limit:
                break
        _insert(conn, batch)
    finally:
        if fh is not None:
            fh.close()
    return n


def _insert(conn: sqlite3.Connection, batch: list[tuple]) -> None:
    if batch:
        conn.executemany(
            """INSERT OR REPLACE INTO puzzles(id, fen, moves, rating, rating_dev, popularity, nb_plays,
                                              themes, game_url, opening) VALUES (?,?,?,?,?,?,?,?,?,?)""",
            batch)
        conn.commit()


def all_themes(conn: sqlite3.Connection) -> list[tuple[str, int]]:
    c = Counter()
    for (t,) in conn.execute("SELECT themes FROM puzzles"):
        c.update(t.split())
    return c.most_common()


# --- решение ---

def player_rating(conn: sqlite3.Connection) -> int:
    return int(get_pref(conn, "player_rating", str(DEFAULT_RATING)))


def pick_puzzle(conn: sqlite3.Connection, *, theme: str | None = None, min_rating: int | None = None,
                max_rating: int | None = None, exclude: Iterable[str] = (),
                rng: random.Random | None = None) -> dict | None:
    rng = rng or random.Random()
    q = "SELECT * FROM puzzles WHERE 1=1"
    args: list = []
    if theme:
        q += " AND (' ' || themes || ' ') LIKE ?"
        args.append(f"% {theme} %")
    if min_rating is not None:
        q += " AND rating >= ?"
        args.append(min_rating)
    if max_rating is not None:
        q += " AND rating <= ?"
        args.append(max_rating)
    exclude = set(exclude)
    rows = [r for r in conn.execute(q, args).fetchall() if r["id"] not in exclude]
    if not rows:
        return None
    return puzzle_view(rng.choice(rows))


def puzzle_view(row: sqlite3.Row) -> dict:
    """Позиция для решающего: первый ход соперника уже сделан."""
    board = chess.Board(row["fen"])
    moves = row["moves"].split()
    first = chess.Move.from_uci(moves[0])
    first_san = board.san(first)
    board.push(first)
    return {"id": row["id"], "fen": board.fen(), "opponent_move": moves[0], "opponent_san": first_san,
            "rating": row["rating"], "themes": row["themes"].split(),
            "solution_length": len(moves) // 2, "game_url": row["game_url"]}


def check_move(conn: sqlite3.Connection, puzzle_id: str, done: list[str], move: str) -> dict:
    """done — ходы решения, уже сделанные после хода соперника (свои и ответы).
    Принимается ход из решения или любой ход, дающий мат (как на Lichess)."""
    row = conn.execute("SELECT * FROM puzzles WHERE id = ?", (puzzle_id,)).fetchone()
    if row is None:
        raise KeyError(puzzle_id)
    sol = row["moves"].split()[1:]
    board = chess.Board(row["fen"])
    board.push(chess.Move.from_uci(row["moves"].split()[0]))
    for u in done:
        board.push(chess.Move.from_uci(u))
    i = len(done)
    try:
        m = chess.Move.from_uci(move)
        if m not in board.legal_moves:
            raise ValueError
    except ValueError:
        m = board.parse_san(move)
    expected = sol[i] if i < len(sol) else None
    b2 = board.copy(stack=False)
    b2.push(m)
    ok = m.uci() == expected or b2.is_checkmate()
    if not ok:
        return {"correct": False, "expected": board.san(chess.Move.from_uci(expected)) if expected else None,
                "done": False}
    finished = b2.is_checkmate() or i + 1 >= len(sol)
    reply = None
    if not finished:
        reply = sol[i + 1]
        b2.push(chess.Move.from_uci(reply))
        finished = i + 2 >= len(sol)
    return {"correct": True, "reply": reply, "done": finished, "fen": b2.fen()}


def expected_seconds(puzzle_rating: int, rating: int, s: Settings) -> float:
    """Ожидаемое время: базовое для задачи своего рейтинга, вдвое дольше на каждые
    +200 пунктов. Простая модель для нормировки времени по рейтингу задачи."""
    return s.puzzle_base_seconds * 2 ** ((puzzle_rating - rating) / 200)


def record_attempt(conn: sqlite3.Connection, puzzle_id: str, seconds: float, solved: bool, s: Settings,
                   difficulty: int | None = None, reasons: list[str] | None = None,
                   probe_id: int | None = None) -> dict:
    row = conn.execute("SELECT rating FROM puzzles WHERE id = ?", (puzzle_id,)).fetchone()
    if row is None:
        raise KeyError(puzzle_id)
    rating = player_rating(conn)
    norm = seconds / expected_seconds(row["rating"], rating, s)
    reasons = [r for r in (reasons or []) if r in REASONS]
    cur = conn.execute(
        """INSERT INTO puzzle_attempts(puzzle_id, probe_id, seconds, solved, player_rating, normalized,
                                       difficulty, reasons) VALUES (?,?,?,?,?,?,?,?)""",
        (puzzle_id, probe_id, seconds, int(solved), rating, norm, difficulty, dumps(reasons)))
    conn.commit()
    if difficulty is not None:
        award(conn, "puzzle_reflection", 1, puzzle_id)   # за разбор трудности, не за решение
    return {"id": cur.lastrowid, "normalized": norm}


# --- проба «туман или слепота» ---

def start_probe(conn: sqlite3.Connection, s: Settings, rng: random.Random | None = None) -> dict:
    """Несколько лёгких задач: на probe_offset_min–probe_offset_max ниже уровня."""
    rng = rng or random.Random()
    r = player_rating(conn)
    lo, hi = r - s.probe_offset_max, r - s.probe_offset_min
    seen = {x["puzzle_id"] for x in conn.execute("SELECT puzzle_id FROM puzzle_attempts")}
    rows = conn.execute("SELECT * FROM puzzles WHERE rating BETWEEN ? AND ?", (lo, hi)).fetchall()
    fresh = [x for x in rows if x["id"] not in seen] or rows
    if len(fresh) < s.probe_size:
        # нет задач в окне — ближайшие по рейтингу к середине окна
        mid = (lo + hi) / 2
        fresh = sorted(conn.execute("SELECT * FROM puzzles").fetchall(), key=lambda x: abs(x["rating"] - mid))
        fresh = fresh[: max(s.probe_size * 5, s.probe_size)]
    if not fresh:
        raise LookupError("в базе нет задач: импортируйте базу Lichess")
    chosen = rng.sample(fresh, min(s.probe_size, len(fresh)))
    cur = conn.execute("INSERT INTO probes(hour, puzzle_ids) VALUES (?, ?)",
                       (datetime.now().hour, dumps([c["id"] for c in chosen])))
    conn.commit()
    return {"probe_id": cur.lastrowid, "puzzles": [puzzle_view(c) for c in chosen]}


def _pearson(xs: list[float], ys: list[float]) -> float | None:
    if len(xs) < 3:
        return None
    try:
        return statistics.correlation(xs, ys)
    except statistics.StatisticsError:
        return None


def finish_probe(conn: sqlite3.Connection, probe_id: int, ease: int, interest: int, s: Settings) -> dict:
    norms = [r["normalized"] for r in conn.execute(
        "SELECT normalized FROM puzzle_attempts WHERE probe_id = ?", (probe_id,))]
    mean_norm = statistics.fmean(norms) if norms else None
    conn.execute("UPDATE probes SET ease = ?, interest = ?, mean_norm = ?, finished = 1 WHERE id = ?",
                 (ease, interest, mean_norm, probe_id))
    conn.commit()
    award(conn, "probe", 1, str(probe_id))
    return probe_result(conn, probe_id, s)


def probe_result(conn: sqlite3.Connection, probe_id: int, s: Settings) -> dict:
    """Первые probe_history_min проб — только субъективный итог. Потом: время
    выше или ниже своей средней и корреляция времени с субъективной лёгкостью."""
    p = conn.execute("SELECT * FROM probes WHERE id = ?", (probe_id,)).fetchone()
    prev = conn.execute(
        "SELECT * FROM probes WHERE finished = 1 AND id < ? AND mean_norm IS NOT NULL ORDER BY id",
        (probe_id,)).fetchall()
    out = {"probe_id": probe_id, "hour": p["hour"], "ease": p["ease"], "interest": p["interest"],
           "mean_norm": p["mean_norm"], "history": len(prev)}
    interested = (p["interest"] or 0) >= 3
    if len(prev) < s.probe_history_min:
        out["mode"] = "subjective"
        out["verdict"] = ("интерес есть — можно тренироваться" if interested
                          else "интереса нет — похоже на туман: сон, перерыв, смена деятельности")
        out["note"] = f"сравнение со средней появится после {s.probe_history_min} проб (сейчас {len(prev)})"
        return out
    avg = statistics.fmean(x["mean_norm"] for x in prev)
    all_p = prev + [p]
    corr = _pearson([x["mean_norm"] for x in all_p], [float(x["ease"]) for x in all_p])
    slow = p["mean_norm"] is not None and p["mean_norm"] > avg
    out.update({"mode": "compared", "average_norm": avg, "slower_than_average": slow,
                "time_ease_correlation": corr})
    if not slow and interested:
        out["verdict"] = "ресурс в порядке: тренировка по теме"
    elif slow and not interested:
        out["verdict"] = "туман: пауза или смена деятельности, тактику через силу не гонять"
    elif slow and interested:
        out["verdict"] = ("слепота: ресурс есть, но паттерны не подгружаются — отдых мало поможет; "
                          "лёгкие задачи сериями на одну тему")
    else:
        out["verdict"] = "распознавание в порядке, мотивации мало — короткая сессия, один сюжет"
    return out


def probe_history(conn: sqlite3.Connection) -> list[dict]:
    return [dict(r) for r in conn.execute("SELECT * FROM probes WHERE finished = 1 ORDER BY id")]


# --- карта трудностей и план ---

def difficulty_map(conn: sqlite3.Connection) -> dict:
    rows = conn.execute(
        "SELECT a.*, p.themes FROM puzzle_attempts a JOIN puzzles p ON p.id = a.puzzle_id").fetchall()
    per: dict[str, dict] = defaultdict(lambda: {"attempts": 0, "failed": 0, "difficulty": [],
                                                "normalized": [], "reasons": Counter()})
    for r in rows:
        for t in r["themes"].split():
            d = per[t]
            d["attempts"] += 1
            d["failed"] += 1 - r["solved"]
            if r["difficulty"] is not None:
                d["difficulty"].append(r["difficulty"])
            d["normalized"].append(r["normalized"])
            d["reasons"].update(json.loads(r["reasons"]))
    themes = []
    for t, d in per.items():
        fail = d["failed"] / d["attempts"]
        diff = statistics.fmean(d["difficulty"]) if d["difficulty"] else None
        norm = statistics.fmean(d["normalized"])
        # Простая оценка трудности темы: провалы + субъективная сложность + медленность.
        score = fail + ((diff or 3) - 1) / 4 + max(0.0, math.log2(max(norm, 1e-6)))
        themes.append({"theme": t, "attempts": d["attempts"], "fail_rate": fail, "difficulty": diff,
                       "normalized": norm, "reasons": dict(d["reasons"]), "score": score})
    themes.sort(key=lambda x: -x["score"])
    plan = []
    for th in [x for x in themes if x["attempts"] >= 2][:3]:
        reason = max(th["reasons"], key=th["reasons"].get) if th["reasons"] else None
        plan.append({"theme": th["theme"], "reason": reason,
                     "advice": REASON_ADVICE.get(reason, "больше задач этой темы, с разбором после каждой")})
    return {"themes": themes, "plan": plan}
