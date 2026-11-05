"""Режимы 9.2–9.5, задачи и проба, chess.com, статистика — без движка."""

import json
import random
from pathlib import Path

import chess
import pytest

from chessanalyst import chesscom, db, puzzles, stats, training
from chessanalyst.engine import Line
from chessanalyst.evals import Eval
from chessanalyst.play import choose_move
from chessanalyst.settings import Settings

DATA = Path(__file__).parent / "data"
OPERA = Path(__file__).resolve().parent.parent / "examples" / "opera_game.pgn"
S = Settings()


@pytest.fixture
def conn(tmp_path):
    return db.connect(tmp_path / "m.sqlite")


def test_parse_line_san_uci_and_numbers():
    b = chess.Board()
    assert training.parse_line(b, "1. e4 e5 2.Nf3 b8c6") == ["e2e4", "e7e5", "g1f3", "b8c6"]


def test_continuation_divergence():
    b = chess.Board()
    b.push_san("e4")                      # мой ход сделан, на ходу соперник
    engine = training.parse_line(b, "e5 Nf3 Nc6 Bb5")
    r = training.compare_continuation(b, training.parse_line(b, "e5 Nf3 Nc6"), engine, S)
    assert r["diverge_kind"] == "match" and r["diverge_index"] is None
    r = training.compare_continuation(b, training.parse_line(b, "c5 Nf3"), engine, S)
    assert r["diverge_index"] == 0 and r["diverge_side"] == "opponent"
    assert r["engine_move"] == "e5" and r["user_move"] == "c5"
    r = training.compare_continuation(b, training.parse_line(b, "e5 d4"), engine, S)
    assert r["diverge_index"] == 1 and r["diverge_side"] == "self"


def test_library_review_and_recall(conn):
    fen = "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 0 1"
    item = training.add_to_library(conn, "Мат по последней", fen, ["a1a8"], stage="endgame")
    assert training.next_training_item(conn, random.Random(1))["id"] == item
    r = training.review_library_item(conn, item, "Ra8#", "Kg1 Ra1 Pf2 Pg2 Ph2 kg8 pf7 pg7 ph7")
    assert r["line_score"] == 1.0 and r["recall_score"] == 1.0
    r = training.review_library_item(conn, item, "Rb1", "Kg1 kg8")
    assert r["line_score"] == 0.0 and 0 < r["recall_score"] < 1
    assert training.library_items(conn)[0]["reviews"] == 2
    assert conn.execute("SELECT SUM(points) FROM events").fetchone()[0] == 2  # сохранение + успех


def _fake_records(conn):
    (gid,) = __import__("chessanalyst.pgn_io", fromlist=["x"]).load_pgn_file(conn, OPERA)
    for ply, step in enumerate(["best", "mistake", "best", "blunder"]):
        conn.execute(
            """INSERT INTO move_records(game_id, ply, settings_version, depth, unit, side, san, uci,
               fen_before, e1, ep, cat_e1, cat_ep, step, decided_by, unit_steps, move_type, type_subtypes,
               flags, best_moves, near_best_moves, stage, l_pawns, l_wdl)
               VALUES (?,?,?,?,?,?,?,?,?,'{}','{}','equal','equal',?,'wdl','{}','positional','[]','[]',
                       '[{"san":"e4"}]','[]','opening',0.5,0.1)""",
            (gid, ply, "v1", 18, "both", "white" if ply % 2 == 0 else "black", "e4", "e2e4",
             chess.STARTING_FEN, step))
    conn.commit()
    return gid


def test_quiz_and_mastery_without_rollback(conn):
    _fake_records(conn)
    s = Settings(mastery_required=1)
    seen = set()
    rng = random.Random(0)
    for _ in range(4):
        q = training.quiz_question(conn, rng)
        seen.add(q["ply"])
        truth = conn.execute("SELECT step FROM move_records WHERE ply = ?", (q["ply"],)).fetchone()[0]
        res = training.quiz_answer(conn, q["game_id"], q["ply"], q["settings_version"],
                                   truth if q["ply"] != 3 else "best")
        assert res["correct"] == (q["ply"] != 3)
    assert len(seen) == 4 and training.quiz_question(conn, rng) is None   # только новые позиции
    m = training.mastery(conn, s)
    assert m["mistake"]["mastered"] and not m["blunder"]["mastered"]
    st = stats.game_stats(conn, s)
    assert st["by_stage"]["opening"]["errors"] == 2


def test_puzzles_import_check_and_probe(conn):
    assert puzzles.import_puzzles(conn, DATA / "puzzles.csv") == 3
    assert puzzles.import_puzzles(conn, DATA / "puzzles.csv", themes={"fork"}) == 1
    p = puzzles.pick_puzzle(conn, theme="fork", rng=random.Random(0))
    assert p["id"] == "p0002" and p["opponent_san"] == "a6"
    r = puzzles.check_move(conn, "p0002", [], "Nc7+")
    assert r["correct"] and r["reply"] == "e8d7" and not r["done"]
    assert puzzles.check_move(conn, "p0002", ["b5c7", "e8d7"], "Nxa8")["done"]
    assert not puzzles.check_move(conn, "p0002", [], "Nd6+")["correct"]

    db.set_pref(conn, "player_rating", "1500")
    s = Settings(probe_history_min=2, probe_size=2)
    verdicts = []
    for secs, ease, interest in [(10, 4, 4), (10, 4, 4), (60, 2, 1), (60, 3, 4)]:
        pr = puzzles.start_probe(conn, s, random.Random(0))
        assert all(x["rating"] < 1300 for x in pr["puzzles"])     # 300–400 ниже уровня
        for x in pr["puzzles"]:
            puzzles.record_attempt(conn, x["id"], secs, True, s, difficulty=2,
                                   reasons=["blind_spot"], probe_id=pr["probe_id"])
        verdicts.append(puzzles.finish_probe(conn, pr["probe_id"], ease, interest, s))
    assert verdicts[0]["mode"] == "subjective" and verdicts[2]["mode"] == "compared"
    assert verdicts[2]["verdict"].startswith("туман")
    assert verdicts[3]["verdict"].startswith("слепота")
    dm = puzzles.difficulty_map(conn)
    assert dm["themes"] and dm["plan"][0]["reason"] == "blind_spot"


def test_expected_seconds_scales_with_rating():
    assert puzzles.expected_seconds(1500, 1500, S) == S.puzzle_base_seconds
    assert puzzles.expected_seconds(1700, 1500, S) == 2 * S.puzzle_base_seconds


def test_chesscom_import_filters(conn):
    pgn = OPERA.read_text()
    me, opp = {"username": "Me", "rating": 1500, "result": "checkmated"}, {"username": "Opp", "rating": 1550,
                                                                          "result": "win"}
    easy = {"username": "Weak", "rating": 1000, "result": "resigned"}
    month = {"games": [
        {"pgn": pgn, "time_class": "rapid", "rated": True, "rules": "chess", "white": opp, "black": me},
        {"pgn": pgn.replace("Paris", "Lyon"), "time_class": "rapid", "rated": True, "rules": "chess",
         "white": {**me, "result": "win"}, "black": easy},
        {"pgn": pgn.replace("Paris", "Nice"), "time_class": "bullet", "rated": True, "rules": "chess",
         "white": opp, "black": me},
    ]}
    pages = {"https://api.chess.com/pub/player/me/games/archives": {"archives": ["M1"]}, "M1": month}
    ids = chesscom.import_user(conn, "Me", time_classes={"rapid"}, min_moves=10,
                               fetch=lambda url: json.dumps(pages[url]))
    assert len(ids) == 1          # блиц отфильтрован, «лёгкая» победа над слабым — тоже


def _ln(move, cp):
    return Line(move=move, eval=Eval(cp, None, (900, 100, 0)), pv=[move])


def test_free_play_deviates_but_keeps_category():
    lines = [_ln("a", 500), _ln("b", 460), _ln("c", 300), _ln("d", 100)]
    s = Settings(unit="pawns", play_deviation_rate=1.0)
    picks = {choose_move(lines, s, random.Random(i))[0].move for i in range(30)}
    assert picks == {"b"}          # c теряет больше play_max_loss, d меняет категорию
    s = Settings(unit="pawns", play_deviation_rate=0.0)
    assert choose_move(lines, s, random.Random(0)) == (lines[0], False)
    s = Settings(human_temperature=1.0)
    picks = {choose_move(lines, s, random.Random(i))[0].move for i in range(200)}
    assert {"a", "b"} <= picks


def test_day_summary_and_story(conn):
    db.award(conn, "quiz_correct", 1)
    training.save_story(conn, "Ладья d1 ждала с 14-го хода")
    d = training.day_summary(conn)
    assert d["story"]["finding"].startswith("Ладья") and d["total_points"] == 2
