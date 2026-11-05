"""Локальное веб-приложение (этап 4, раздел 11).

Только стандартная библиотека: http.server + JSON API, доска рисуется на сервере
через chess.svg (стрелки идей, подсветка), интерфейс — один HTML без сборки.
Запуск: python -m chessanalyst serve  →  http://127.0.0.1:8765
"""

from __future__ import annotations

import json
import queue
import random
import re
import threading
import traceback
from contextlib import contextmanager
from dataclasses import replace
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

import chess
import chess.svg

from .. import chesscom, db, pgn_io, puzzles, stats, training
from ..engine import Analyzer
from ..pipeline import classify_game, latest_run, load_ideas, load_records
from ..play import PlaySession
from ..settings import Settings

STATIC = Path(__file__).parent / "static"
ARROW_COLORS = {"green": "#15781B80", "red": "#88202080", "blue": "#003088a0", "yellow": "#e6a20080"}


class App:
    """Общее состояние: путь к базе, настройки, движок для интерактива, очередь анализа."""

    def __init__(self, db_path: str, settings: Settings):
        self.db_path = db_path
        self.s = settings
        self.rng = random.Random()
        # Интерактивный движок (игра, продолжение, углубление) — один, под замком.
        self.engine_lock = threading.Lock()
        self.engine_conn = db.connect(db_path, check_same_thread=False)
        self.analyzer = Analyzer(self.engine_conn, settings)
        # Фоновый анализ партий — отдельный процесс движка и своя очередь.
        self.jobs: queue.Queue = queue.Queue()
        self.progress: dict[int, dict] = {}
        threading.Thread(target=self._worker, daemon=True).start()

    @contextmanager
    def conn(self):
        c = db.connect(self.db_path)
        try:
            yield c
            c.commit()
        finally:
            c.close()

    def _worker(self) -> None:
        conn = db.connect(self.db_path, check_same_thread=False)
        an = Analyzer(conn, self.s)
        while True:
            gid, s = self.jobs.get()
            an.s = s
            self.progress[gid] = {"state": "running", "done": 0, "total": 0}

            def cb(done, total, gid=gid):
                self.progress[gid].update(done=done, total=total)
            try:
                classify_game(an, gid, cb)
                self.progress[gid]["state"] = "done"
            except Exception as e:  # noqa: BLE001 — показать ошибку в интерфейсе
                self.progress[gid] = {"state": "error", "error": str(e)}
                traceback.print_exc()

    def enqueue(self, gid: int, s: Settings) -> None:
        self.progress[gid] = {"state": "queued", "done": 0, "total": 0}
        self.jobs.put((gid, s))


def _square(name: str) -> int:
    return chess.parse_square(name)


def board_svg(q: dict) -> str:
    fen = q.get("fen", chess.STARTING_FEN)
    board = chess.Board(fen)
    arrows = []
    for a in filter(None, q.get("arrows", "").split(",")):
        uci, _, color = a.partition(":")
        if len(uci) >= 4:
            arrows.append(chess.svg.Arrow(_square(uci[:2]), _square(uci[2:4]),
                                          color=ARROW_COLORS.get(color, ARROW_COLORS["green"])))
    fill = {}
    for sq in filter(None, q.get("mark", "").split(",")):
        fill[_square(sq)] = "#cc000055"
    if q.get("sel"):
        fill[_square(q["sel"])] = "#14551e80"
    last = chess.Move.from_uci(q["last"]) if q.get("last") else None
    check = board.king(board.turn) if board.is_check() else None
    return chess.svg.board(board, size=int(q.get("size", 400)), coordinates=False,
                           flipped=q.get("flip") == "1", arrows=arrows, fill=fill, lastmove=last,
                           check=check)


class Handler(BaseHTTPRequestHandler):
    app: App  # назначается в serve()

    # --- транспорт ---

    def log_message(self, fmt, *args):  # тише в консоли
        pass

    def _send(self, body: bytes, ctype: str, status: int = 200) -> None:
        self.send_response(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, status: int = 200) -> None:
        self._send(json.dumps(obj, ensure_ascii=False, default=str).encode(), "application/json", status)

    def _body(self) -> dict:
        n = int(self.headers.get("Content-Length") or 0)
        return json.loads(self.rfile.read(n) or b"{}") if n else {}

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def _route(self, method: str) -> None:
        url = urlparse(self.path)
        q = {k: v[-1] for k, v in parse_qs(url.query).items()}
        path = url.path
        try:
            if method == "GET" and (path == "/" or path.startswith("/static/")):
                return self._static(path)
            if path == "/api/board.svg":
                return self._send(board_svg(q).encode(), "image/svg+xml")
            for pattern, meth, fn in ROUTES:
                m = re.fullmatch(pattern, path)
                if m and meth == method:
                    body = self._body() if method == "POST" else {}
                    return self._json(fn(self.app, q, body, *m.groups()))
            self._json({"error": "not found"}, 404)
        except (KeyError, ValueError, LookupError) as e:
            self._json({"error": str(e)}, 400)
        except Exception as e:  # noqa: BLE001
            traceback.print_exc()
            self._json({"error": str(e)}, 500)

    def _static(self, path: str) -> None:
        name = "index.html" if path == "/" else path.removeprefix("/static/")
        f = (STATIC / name).resolve()
        if STATIC.resolve() not in f.parents or not f.is_file():
            return self._json({"error": "not found"}, 404)
        ctype = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
                 ".css": "text/css; charset=utf-8"}.get(f.suffix, "application/octet-stream")
        self._send(f.read_bytes(), ctype)


# --- обработчики API ---

def _settings_from(app: App, body: dict) -> Settings:
    kw = {}
    if body.get("depth"):
        kw["depth"] = int(body["depth"])
    if body.get("unit"):
        kw["unit"] = body["unit"]
    if body.get("multipv"):
        kw["multipv"] = int(body["multipv"])
    return replace(app.s, **kw)


def api_games(app, q, body):
    with app.conn() as conn:
        out = []
        for g in conn.execute("SELECT * FROM games ORDER BY id DESC"):
            n = conn.execute("SELECT COUNT(*) FROM plies WHERE game_id = ?", (g["id"],)).fetchone()[0]
            st = conn.execute("SELECT * FROM game_state WHERE game_id = ?", (g["id"],)).fetchone()
            out.append({"id": g["id"], "label": pgn_io.game_label(g), "white": g["white"], "black": g["black"],
                        "result": g["result"], "plies": n, "status": g["status"],
                        "cursor": st["cursor_ply"] if st else None,
                        "updated": st["updated_at"] if st else None,
                        "progress": app.progress.get(g["id"])})
        return out


def api_upload(app, q, body):
    with app.conn() as conn:
        ids = pgn_io.load_pgn_text(conn, body.get("pgn", ""))
    if body.get("analyze"):
        s = _settings_from(app, body)
        for gid in ids:
            app.enqueue(gid, s)
    return {"ids": ids}


def api_analyze(app, q, body):
    s = _settings_from(app, body)
    for gid in body.get("ids", []):
        app.enqueue(int(gid), s)
    return {"queued": body.get("ids", [])}


def api_game(app, q, body, gid):
    gid = int(gid)
    with app.conn() as conn:
        g = conn.execute("SELECT * FROM games WHERE id = ?", (gid,)).fetchone()
        if g is None:
            raise KeyError(f"партия {gid} не найдена")
        plies = [dict(r) for r in conn.execute("SELECT * FROM plies WHERE game_id = ? ORDER BY ply", (gid,))]
        run = latest_run(conn, gid)
        records = load_records(conn, gid) if run else []
        ideas = load_ideas(conn, gid, *run) if run else []
        st = conn.execute("SELECT cursor_ply FROM game_state WHERE game_id = ?", (gid,)).fetchone()
    final = chess.Board(g["start_fen"])
    for p in plies:
        final.push(chess.Move.from_uci(p["uci"]))
    return {"final_fen": final.fen(),"id": gid, "label": pgn_io.game_label(g), "headers": {k: g[k] for k in ("white", "black", "result",
                                                                                   "event", "date")},
            "start_fen": g["start_fen"], "plies": plies, "records": records, "ideas": ideas,
            "run": {"version": run[0], "depth": run[1]} if run else None,
            "cursor": st["cursor_ply"] if st else 0, "progress": app.progress.get(gid)}


def api_cursor(app, q, body, gid):
    with app.conn() as conn:
        training.touch_game(conn, int(gid), int(body.get("ply", 0)))
    return {"ok": True}


def _lines_json(board: chess.Board, lines, s: Settings) -> list[dict]:
    out = []
    for ln in lines:
        b = board.copy(stack=False)
        san = []
        for u in ln.pv[:10]:
            m = chess.Move.from_uci(u)
            if m not in b.legal_moves:
                break
            san.append(b.san(m))
            b.push(m)
        out.append({"uci": ln.move, "eval": str(ln.eval), "pawns": ln.eval.pawns(s),
                    "wdl": ln.eval.expected, "pv": san})
    return out


def api_position(app, q, body):
    """Все ходы позиции (MultiPV) — из кэша; углубление ветки — по запросу (9.1)."""
    fen = body.get("fen") or q.get("fen")
    board = chess.Board(fen)
    depth = int(body.get("depth") or q.get("depth") or app.s.depth)
    multipv = int(body.get("multipv") or q.get("multipv") or app.s.multipv)
    with app.engine_lock:
        lines = app.analyzer.root_lines(board, depth=depth, multipv=multipv)
    return {"fen": fen, "depth": depth, "lines": _lines_json(board, lines, app.s)}


def api_continuation(app, q, body):
    """«Покажи своё продолжение»: fen — позиция после своего хода."""
    board = chess.Board(body["fen"])
    if body.get("move"):                       # позиция до хода + сам ход
        board.push(chess.Move.from_uci(body["move"]))
    user = training.parse_line(board, body.get("line", ""))
    if not user:
        raise ValueError("пустое продолжение")
    with app.engine_lock:
        lines = app.analyzer.root_lines(board)
    engine = lines[0].pv[:max(len(user), 4)]
    res = training.compare_continuation(board, user, engine, app.s)
    with app.conn() as conn:
        training.save_continuation(conn, body.get("source", "game"), body.get("ref"), board, user, engine, res)
    b = board.copy(stack=False)
    engine_san = []
    for u in engine:
        m = chess.Move.from_uci(u)
        engine_san.append(b.san(m))
        b.push(m)
    res["engine_line"] = engine_san
    res["kind_label"] = training.KIND_LABELS.get(res["diverge_kind"], res["diverge_kind"])
    return res


def api_library_add(app, q, body):
    with app.conn() as conn:
        fen, key, sig, chunk, stage = body.get("fen"), body.get("key_line"), None, None, None
        gid, ply = body.get("game_id"), body.get("ply")
        if gid is not None and ply is not None:
            rec = next((r for r in load_records(conn, int(gid)) if r["ply"] == int(ply)), None)
            if rec is None:
                raise KeyError("ход не разобран")
            fen = fen or rec["fen_before"]
            stage = rec["stage"]
            sig = rec.get("idea_signature") or None
            idea = conn.execute("SELECT chunk FROM ideas WHERE game_id = ? AND punish_ply = ? "
                                "ORDER BY id DESC LIMIT 1", (gid, ply)).fetchone()
            chunk = idea["chunk"] if idea else None
            if not key:
                cached = conn.execute("SELECT lines FROM engine_cache WHERE epd = ? ORDER BY depth DESC LIMIT 1",
                                      (chess.Board(fen).epd(),)).fetchone()
                key = json.loads(cached["lines"])[0]["pv"][:6] if cached else [rec["uci"]]
        board = chess.Board(fen)
        if isinstance(key, str):
            key = training.parse_line(board, key)
        if not key:
            raise ValueError("нужна ключевая линия")
        iid = training.add_to_library(conn, body.get("title") or "Идея", board.fen(), key,
                                      game_id=gid, ply=ply, signature=sig, chunk=chunk, stage=stage,
                                      note=body.get("note"), locus=body.get("locus"))
    return {"id": iid}


def api_library(app, q, body):
    with app.conn() as conn:
        return training.library_items(conn)


def api_library_next(app, q, body):
    with app.conn() as conn:
        return training.next_training_item(conn, app.rng)


def api_library_review(app, q, body, iid):
    with app.conn() as conn:
        return training.review_library_item(conn, int(iid), body.get("line", ""), body.get("recall"))


def api_quiz(app, q, body):
    with app.conn() as conn:
        return training.quiz_question(conn, app.rng)


def api_quiz_answer(app, q, body):
    with app.conn() as conn:
        res = training.quiz_answer(conn, int(body["game_id"]), int(body["ply"]), body["settings_version"],
                                   body["answer"])
        res["mastery"] = training.mastery(conn, app.s)
    return res


def api_idea_guess(app, q, body, iid):
    with app.conn() as conn:
        return training.guess_idea_start(conn, int(iid), int(body["ply"]))


def api_play_start(app, q, body):
    with app.engine_lock:
        sess = PlaySession.start(app.engine_conn, app.analyzer, body["fen"], body.get("source"), app.rng)
    return sess.to_json()


def api_play_get(app, q, body, sid):
    return PlaySession(app.engine_conn, app.analyzer, int(sid)).to_json()


def api_play_move(app, q, body, sid):
    with app.engine_lock:
        sess = PlaySession(app.engine_conn, app.analyzer, int(sid), app.rng)
        res = sess.human_move(body["move"])
    res["session"] = sess.to_json()
    return res


def api_puzzle(app, q, body):
    with app.conn() as conn:
        p = puzzles.pick_puzzle(conn, theme=q.get("theme") or None,
                                min_rating=int(q["min"]) if q.get("min") else None,
                                max_rating=int(q["max"]) if q.get("max") else None, rng=app.rng)
    if p is None:
        raise LookupError("нет задач по фильтру — импортируйте базу Lichess")
    return p


def api_puzzle_move(app, q, body):
    with app.conn() as conn:
        return puzzles.check_move(conn, body["id"], body.get("done", []), body["move"])


def api_puzzle_attempt(app, q, body):
    with app.conn() as conn:
        return puzzles.record_attempt(conn, body["id"], float(body["seconds"]), bool(body["solved"]), app.s,
                                      body.get("difficulty"), body.get("reasons"), body.get("probe_id"))


def api_probe_start(app, q, body):
    with app.conn() as conn:
        return puzzles.start_probe(conn, app.s, app.rng)


def api_probe_finish(app, q, body, pid):
    with app.conn() as conn:
        return puzzles.finish_probe(conn, int(pid), int(body["ease"]), int(body["interest"]), app.s)


def api_puzzles_import(app, q, body):
    themes = set(body.get("themes", "").split()) or None
    with app.conn() as conn:
        n = puzzles.import_puzzles(conn, body["path"], themes=themes,
                                   min_rating=int(body.get("min") or 0), max_rating=int(body.get("max") or 4000),
                                   limit=int(body["limit"]) if body.get("limit") else None)
    return {"imported": n}


def api_themes(app, q, body):
    with app.conn() as conn:
        return {"themes": puzzles.all_themes(conn)[:80], "reasons": puzzles.REASONS,
                "count": conn.execute("SELECT COUNT(*) FROM puzzles").fetchone()[0],
                "rating": puzzles.player_rating(conn)}


def api_chesscom(app, q, body):
    tc = set(body.get("time_classes", "").split()) or None
    res = set(body.get("results", "").split()) or None
    with app.conn() as conn:
        ids = chesscom.import_user(conn, body["user"], months=int(body.get("months") or 1), time_classes=tc,
                                   results=res, min_moves=int(body.get("min_moves") or 20),
                                   skip_easy=bool(body.get("skip_easy", True)),
                                   limit=int(body["limit"]) if body.get("limit") else None)
        db.set_pref(conn, "player_name", body["user"])
    return {"ids": ids}


def api_stats(app, q, body):
    with app.conn() as conn:
        return stats.all_stats(conn, app.s)


def api_day(app, q, body):
    with app.conn() as conn:
        return training.day_summary(conn)


def api_day_save(app, q, body):
    with app.conn() as conn:
        training.save_story(conn, body["finding"], body.get("game_id"), body.get("idea_id"))
        return training.day_summary(conn)


def api_prefs(app, q, body):
    with app.conn() as conn:
        for k in ("player_rating", "player_name"):
            if k in body:
                db.set_pref(conn, k, str(body[k]))
        return {"player_rating": db.get_pref(conn, "player_rating", str(puzzles.DEFAULT_RATING)),
                "player_name": db.get_pref(conn, "player_name", ""),
                "settings": {"depth": app.s.depth, "multipv": app.s.multipv, "unit": app.s.unit,
                             "version": app.s.version}}


ROUTES = [
    (r"/api/games", "GET", api_games),
    (r"/api/games/upload", "POST", api_upload),
    (r"/api/games/analyze", "POST", api_analyze),
    (r"/api/games/(\d+)", "GET", api_game),
    (r"/api/games/(\d+)/cursor", "POST", api_cursor),
    (r"/api/position", "POST", api_position),
    (r"/api/position", "GET", api_position),
    (r"/api/continuation", "POST", api_continuation),
    (r"/api/library", "GET", api_library),
    (r"/api/library", "POST", api_library_add),
    (r"/api/library/next", "GET", api_library_next),
    (r"/api/library/(\d+)/review", "POST", api_library_review),
    (r"/api/quiz", "GET", api_quiz),
    (r"/api/quiz", "POST", api_quiz_answer),
    (r"/api/ideas/(\d+)/guess", "POST", api_idea_guess),
    (r"/api/play", "POST", api_play_start),
    (r"/api/play/(\d+)", "GET", api_play_get),
    (r"/api/play/(\d+)/move", "POST", api_play_move),
    (r"/api/puzzle", "GET", api_puzzle),
    (r"/api/puzzle/move", "POST", api_puzzle_move),
    (r"/api/puzzle/attempt", "POST", api_puzzle_attempt),
    (r"/api/probe", "POST", api_probe_start),
    (r"/api/probe/(\d+)/finish", "POST", api_probe_finish),
    (r"/api/puzzles/import", "POST", api_puzzles_import),
    (r"/api/themes", "GET", api_themes),
    (r"/api/chesscom", "POST", api_chesscom),
    (r"/api/stats", "GET", api_stats),
    (r"/api/day", "GET", api_day),
    (r"/api/day", "POST", api_day_save),
    (r"/api/prefs", "GET", api_prefs),
    (r"/api/prefs", "POST", api_prefs),
]


def make_server(db_path: str, settings: Settings, host: str = "127.0.0.1", port: int = 8765):
    db.connect(db_path).close()  # создать схему
    handler = type("BoundHandler", (Handler,), {"app": App(db_path, settings)})
    return ThreadingHTTPServer((host, port), handler)


def serve(db_path: str, settings: Settings, host: str = "127.0.0.1", port: int = 8765) -> None:
    srv = make_server(db_path, settings, host, port)
    print(f"ChessAnalyst: http://{host}:{port}  (Ctrl+C — выход)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        srv.server_close()
