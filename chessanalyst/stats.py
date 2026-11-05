"""Статистика (раздел 11, экран 7; раздел 3: стадия — срез, а не навык).

Если задано имя игрока (prefs.player_name), считаются только его ходы — по
совпадению с заголовками White/Black. Иначе — ходы обеих сторон (партии чемпионов).
"""

from __future__ import annotations

import json
import sqlite3
import statistics
from collections import Counter, defaultdict

from .db import get_pref
from .puzzles import difficulty_map, probe_history
from .settings import Settings
from .training import mastery

ERROR_STEPS = ("laxity", "mistake", "blunder")
# Потеря в пешках для средних обрезается: зевок в мат стоит ~90 «пешек» и
# иначе один такой ход определял бы весомость ошибок всей стадии.
LOSS_CAP_PAWNS = 10.0


def _latest_records(conn: sqlite3.Connection, player: str | None) -> list[sqlite3.Row]:
    """Последний прогон каждой партии (по времени записи), только ходы игрока, если он задан."""
    runs: dict[int, tuple] = {}
    for r in conn.execute("""SELECT game_id, settings_version, depth, MAX(created_at) AS t
                             FROM move_records GROUP BY game_id, settings_version, depth"""):
        if r["game_id"] not in runs or r["t"] > runs[r["game_id"]][2]:
            runs[r["game_id"]] = (r["settings_version"], r["depth"], r["t"])
    rows = []
    for gid, (ver, depth, _) in runs.items():
        rows += conn.execute(
            """SELECT m.*, g.white, g.black FROM move_records m JOIN games g ON g.id = m.game_id
               WHERE m.game_id = ? AND m.settings_version = ? AND m.depth = ?""", (gid, ver, depth)).fetchall()
    out = []
    for r in rows:
        if {"theory", "book"} & set(json.loads(r["flags"])):
            continue
        if player:
            name = r["white"] if r["side"] == "white" else r["black"]
            if (name or "").lower() != player.lower():
                continue
        out.append(r)
    return out


def game_stats(conn: sqlite3.Connection, s: Settings) -> dict:
    player = get_pref(conn, "player_name") or None
    recs = _latest_records(conn, player)
    by_stage: dict[str, dict] = defaultdict(lambda: {"moves": 0, "errors": 0, "loss_pawns": [], "loss_wdl": []})
    steps = Counter()
    passes = 0
    for r in recs:
        steps[r["step"]] += 1
        if r["step"] == "forced":
            continue  # без выбора: не входит в частоту ошибок стадии
        st = by_stage[r["stage"]]
        st["moves"] += 1
        passes += "pass" in json.loads(r["flags"])
        if r["step"] in ERROR_STEPS:
            st["errors"] += 1
            st["loss_pawns"].append(min(r["l_pawns"], LOSS_CAP_PAWNS))
            st["loss_wdl"].append(r["l_wdl"])
    stage_out = {}
    for name in ("opening", "middlegame", "endgame"):
        st = by_stage.get(name)
        if not st:
            continue
        stage_out[name] = {
            "moves": st["moves"], "errors": st["errors"],
            "frequency": st["errors"] / st["moves"] if st["moves"] else 0.0,     # где ошибок больше
            "mean_loss_pawns": statistics.fmean(st["loss_pawns"]) if st["loss_pawns"] else 0.0,  # где весомее
            "mean_loss_wdl": statistics.fmean(st["loss_wdl"]) if st["loss_wdl"] else 0.0,
        }
    ideas = conn.execute("SELECT distance, owner, victim, signature FROM ideas WHERE kind = 'punishment'"
                         ).fetchall()
    motifs = Counter(json.loads(i["signature"])["motif"] for i in ideas)
    distances = Counter(i["distance"] for i in ideas if i["distance"] is not None)
    cont = conn.execute(
        "SELECT diverge_side, diverge_kind, COUNT(*) AS n FROM continuations GROUP BY 1, 2").fetchall()
    return {
        "player": player,
        "moves": len(recs),
        "by_stage": stage_out,
        "steps": dict(steps),
        "pass_flags": passes,
        "idea_motifs": dict(motifs),
        "idea_distances": {str(k): v for k, v in sorted(distances.items())},
        "continuations": [dict(c) for c in cont],
    }


def all_stats(conn: sqlite3.Connection, s: Settings) -> dict:
    return {
        "games": game_stats(conn, s),
        "puzzles": difficulty_map(conn),
        "probes": probe_history(conn),
        "mastery": mastery(conn, s),
        "points": conn.execute("SELECT COALESCE(SUM(points), 0) FROM events").fetchone()[0],
    }
