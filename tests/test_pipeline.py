import shutil
from pathlib import Path

import pytest

from chessanalyst import db, pgn_io, report
from chessanalyst.cli import main
from chessanalyst.engine import Analyzer
from chessanalyst.pipeline import classify_game
from chessanalyst.settings import Settings

OPERA = Path(__file__).resolve().parent.parent / "examples" / "opera_game.pgn"
ENGINE = shutil.which("stockfish") or shutil.which("/usr/games/stockfish")


def test_load_pgn_and_dedupe(tmp_path):
    conn = db.connect(tmp_path / "t.sqlite")
    ids = pgn_io.load_pgn_file(conn, OPERA)
    assert pgn_io.load_pgn_file(conn, OPERA) == ids  # повторная загрузка не дублирует
    plies = conn.execute("SELECT * FROM plies WHERE game_id = ? ORDER BY ply", (ids[0],)).fetchall()
    assert len(plies) == 33
    assert plies[0]["san"] == "e4" and plies[1]["side"] == "black"
    assert plies[-1]["san"] == "Rd8#" and plies[-1]["move_no"] == 17


@pytest.mark.skipif(ENGINE is None, reason="Stockfish не установлен")
def test_full_pipeline_with_engine(tmp_path):
    conn = db.connect(tmp_path / "t.sqlite")
    (gid,) = pgn_io.load_pgn_file(conn, OPERA)
    s = Settings(engine_path=ENGINE, depth=10)
    with Analyzer(conn, s) as an:
        recs = classify_game(an, gid)
        searches = an.stats["searches"]
        recs2 = classify_game(an, gid)          # второй прогон — целиком из кэша
        assert an.stats["searches"] == searches
    assert [r.step for r in recs] == [r.step for r in recs2]
    assert len(recs) == 33
    assert recs[-1].san == "Rd8#" and recs[-1].step == "best"
    assert recs[-1].ep.mate == 1
    assert recs[-2].san == "Nxb8"
    saved = conn.execute("SELECT COUNT(*) FROM move_records WHERE game_id = ?", (gid,)).fetchone()[0]
    assert saved == 33

    for ext in ("txt", "csv", "json"):
        out = tmp_path / f"r.{ext}"
        report.write_file(recs, s, out)
        assert out.stat().st_size > 0


@pytest.mark.skipif(ENGINE is None, reason="Stockfish не установлен")
def test_cli_run(tmp_path, capsys):
    rc = main(["run", str(OPERA), "--db", str(tmp_path / "c.sqlite"), "--engine", ENGINE,
               "--depth", "8", "-o", str(tmp_path / "out.json")])
    assert rc == 0
    assert "Rd8#" in capsys.readouterr().out
    assert (tmp_path / "out.json").exists()


@pytest.mark.skipif(ENGINE is None, reason="Stockfish не установлен")
def test_multipv_extension_and_trivial(tmp_path):
    import chess

    from chessanalyst.classify import classify, trivial_candidate

    conn = db.connect(tmp_path / "t.sqlite")
    s = Settings(engine_path=ENGINE, depth=8)
    with Analyzer(conn, s) as an:
        # K+B против K: все ходы — ничья 0.00, пяти линий мало для зоны B → 10 линий.
        draw = chess.Board("8/8/8/4k3/8/8/2B5/4K3 w - - 0 1")
        assert len(an.root_lines(draw)) == 10
        # K+Q против K: любой ход, кроме зевка ферзя, сохраняет выигрыш.
        win = chess.Board("8/8/8/4k3/8/8/1Q6/K7 w - - 0 1")
        lines = an.root_lines(win)
        n = win.legal_moves.count()
        assert trivial_candidate(lines, n, s)
        all_lines = an.all_moves(win)
        assert len(all_lines) == n
        rec = classify(win, lines, lines[0], None, s, all_lines=all_lines)
        assert "trivial" in rec.flags


@pytest.mark.skipif(ENGINE is None, reason="Stockfish не установлен")
def test_stability_and_ideas(tmp_path):
    from chessanalyst.pipeline import load_ideas, stability

    conn = db.connect(tmp_path / "t.sqlite")
    (gid,) = pgn_io.load_pgn_file(conn, OPERA)
    with Analyzer(conn, Settings(engine_path=ENGINE)) as an:
        res = stability(an, gid, (8, 10))
    assert res["plies"] == 33 and 0 <= res["step_agreement"] <= 1
    agree_both = sum(1 for _ in range(33)) - len(res["diffs"])
    assert agree_both <= 33 * min(res["step_agreement"], res["best_set_agreement"]) + 1e-9
    ideas = load_ideas(conn, gid, Settings().version, 10)
    assert ideas and all(i["start_ply"] >= 0 for i in ideas)
