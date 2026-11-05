"""Импорт партий с chess.com (этап 7, вторичная функция из раздела 1).

Публичный API: /pub/player/{user}/games/archives → список месяцев,
/pub/player/{user}/games/{YYYY}/{MM} → партии с pgn, time_class, rated и рейтингами.

У chess.com нет фильтра «лёгких» партий, а разбирать всё подряд долго, поэтому
простое решение — свои фильтры до загрузки в очередь: контроль времени, только
рейтинговые, только поражения/ничьи, минимальная длина и разница рейтингов
(партии против заметно более слабых соперников обычно и есть «лёгкие»).
"""

from __future__ import annotations

import io
import json
import sqlite3
import urllib.request
from collections.abc import Callable

import chess.pgn

from .pgn_io import load_pgn_text

API = "https://api.chess.com/pub/player"
Fetch = Callable[[str], str]


def http_fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "chessanalyst/0.1 (training tool)"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8")


def _game_ok(g: dict, user: str, *, time_classes: set[str] | None, rated_only: bool,
             results: set[str] | None, min_moves: int, max_rating_gap: int | None,
             skip_easy: bool) -> bool:
    if time_classes and g.get("time_class") not in time_classes:
        return False
    if rated_only and not g.get("rated", False):
        return False
    me_white = g["white"]["username"].lower() == user.lower()
    me, opp = (g["white"], g["black"]) if me_white else (g["black"], g["white"])
    if results:
        res = me.get("result", "")
        kind = "win" if res == "win" else ("draw" if res in (
            "agreed", "repetition", "stalemate", "insufficient", "50move", "timevsinsufficient") else "loss")
        if kind not in results:
            return False
    gap = opp.get("rating", 0) - me.get("rating", 0)
    if max_rating_gap is not None and abs(gap) > max_rating_gap:
        return False
    if skip_easy and gap < -200:
        return False  # соперник слабее на 200+ — партия, скорее всего, «лёгкая»
    game = chess.pgn.read_game(io.StringIO(g.get("pgn", "")))
    if game is None:
        return False
    plies = sum(1 for _ in game.mainline_moves())
    return (plies + 1) // 2 >= min_moves


def import_user(conn: sqlite3.Connection, user: str, *, months: int = 1,
                time_classes: set[str] | None = None, rated_only: bool = True,
                results: set[str] | None = None, min_moves: int = 20,
                max_rating_gap: int | None = None, skip_easy: bool = True,
                limit: int | None = None, fetch: Fetch = http_fetch) -> list[int]:
    archives = json.loads(fetch(f"{API}/{user.lower()}/games/archives"))["archives"]
    ids: list[int] = []
    for url in reversed(archives[-months:]):
        games = json.loads(fetch(url))["games"]
        for g in reversed(games):
            if "pgn" not in g or g.get("rules", "chess") != "chess":
                continue
            if not _game_ok(g, user, time_classes=time_classes, rated_only=rated_only, results=results,
                            min_moves=min_moves, max_rating_gap=max_rating_gap, skip_easy=skip_easy):
                continue
            ids += load_pgn_text(conn, g["pgn"])
            if limit and len(ids) >= limit:
                return ids
    return ids
