"""API веб-приложения и режимы с движком (пропускаются без Stockfish)."""

import json
import shutil
import threading
import time
import urllib.request
from pathlib import Path

import pytest

from chessanalyst.settings import Settings

ENGINE = shutil.which("stockfish") or shutil.which("/usr/games/stockfish")
OPERA = (Path(__file__).resolve().parent.parent / "examples" / "opera_game.pgn").read_text()
pytestmark = pytest.mark.skipif(ENGINE is None, reason="Stockfish не установлен")


@pytest.fixture(scope="module")
def base(tmp_path_factory):
    from chessanalyst.web.server import make_server
    db_path = str(tmp_path_factory.mktemp("web") / "w.sqlite")
    srv = make_server(db_path, Settings(engine_path=ENGINE, depth=8, play_depth=6), port=0)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    yield f"http://127.0.0.1:{srv.server_address[1]}"
    srv.shutdown()


def call(base, path, body=None):
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(base + path, data=data, headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        raw = r.read()
        return json.loads(raw) if r.headers["Content-Type"].startswith("application/json") else raw.decode()


def test_static_and_board(base):
    assert "ChessAnalyst" in call(base, "/")
    svg = call(base, "/api/board.svg?fen=8/8/8/8/8/8/8/K6k%20w%20-%20-%200%201&arrows=a1a2:red&sel=a1")
    assert svg.startswith("<svg")


def test_upload_analyze_and_game_view(base):
    ids = call(base, "/api/games/upload", {"pgn": OPERA, "analyze": True, "depth": 8})["ids"]
    gid = ids[0]
    for _ in range(600):
        g = [x for x in call(base, "/api/games") if x["id"] == gid][0]
        if g["progress"] and g["progress"]["state"] in ("done", "error"):
            break
        time.sleep(0.1)
    assert g["progress"]["state"] == "done"
    game = call(base, f"/api/games/{gid}")
    assert len(game["records"]) == 33 and game["run"]["depth"] == 8
    assert game["ideas"]
    assert game["final_fen"].startswith("1n1Rkb1r")
    call(base, f"/api/games/{gid}/cursor", {"ply": 12})
    assert call(base, f"/api/games/{gid}")["cursor"] == 12

    pos = call(base, "/api/position", {"fen": game["plies"][29]["fen_before"], "depth": 8})
    assert pos["lines"] and pos["lines"][0]["pv"]
    cont = call(base, "/api/continuation", {"fen": game["plies"][29]["fen_before"], "move": game["plies"][29]["uci"],
                                            "line": "Qb8+ Nxb8 Rd8#", "ref": f"{gid}:29"})
    assert cont["diverge_kind"] == "match"

    lib = call(base, "/api/library", {"game_id": gid, "ply": 30, "title": "Мат Морфи"})
    item = call(base, "/api/library/next")
    assert item["id"] == lib["id"]
    review = call(base, f"/api/library/{lib['id']}/review", {"line": "Qb8+ Nxb8 Rd8#"})
    assert review["line_score"] > 0

    q = call(base, "/api/quiz")
    ans = call(base, "/api/quiz", {**{k: q[k] for k in ("game_id", "ply", "settings_version")}, "answer": "best"})
    assert "mastery" in ans

    idea = game["ideas"][-1]
    guess = call(base, f"/api/ideas/{idea['id']}/guess", {"ply": idea["start_ply"]})
    assert guess["correct"]

    st = call(base, "/api/stats")
    book = sum(r["step"] == "book" for r in game["records"])
    assert book > 0                              # «Оперная партия» начинается Филидором
    assert st["games"]["moves"] == 33 - book and st["points"] >= 4
    day = call(base, "/api/day", {"finding": "ладья d1"})
    assert day["story"]["finding"] == "ладья d1"


def test_play_mode(base):
    sess = call(base, "/api/play", {"fen": "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1"})
    assert sess["human"] == "white"
    r = call(base, f"/api/play/{sess['id']}/move", {"move": "Rd8#"})
    assert r["human"]["step"] == "best" and r["status"].startswith("finished:1-0")


def test_errors_are_json(base):
    req = urllib.request.Request(base + "/api/games/999")
    with pytest.raises(urllib.error.HTTPError) as e:
        urllib.request.urlopen(req)
    assert e.value.code == 400 and "не найдена" in json.loads(e.value.read())["error"]
