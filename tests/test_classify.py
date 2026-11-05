"""Правила раздела 7 на синтетических оценках (без движка)."""

import chess
import pytest

from chessanalyst.classify import classify
from chessanalyst.engine import Line
from chessanalyst.evals import Eval
from chessanalyst.settings import Settings

PAWNS = Settings(unit="pawns")
WDL = Settings(unit="wdl")
BOTH = Settings(unit="both")

START = chess.Board()
MOVES = ["e2e4", "d2d4", "g1f3", "c2c4", "b1c3", "g2g3"]


def ev(cp=None, mate=None, exp=None):
    """Оценка для тестов; WDL по умолчанию грубо следует пешкам."""
    if exp is None:
        if mate is not None:
            exp = 1.0 if mate > 0 else 0.0
        else:
            exp = min(1.0, max(0.0, 0.5 + cp / 1000))
    w = round(exp * 1000)
    return Eval(cp=cp, mate=mate, wdl=(w, 0, 1000 - w))


def lines(*evals, board=START):
    return [Line(move=MOVES[i], eval=e, pv=[MOVES[i]]) for i, e in enumerate(evals)]


def run(ls, played_idx=None, played_eval=None, prev=None, s=PAWNS, board=START):
    if played_idx is not None:
        played = ls[played_idx]
    else:
        played = Line(move=MOVES[5], eval=played_eval, pv=[MOVES[5]])
    return classify(board, ls, played, prev, s)


def opp(e: Eval) -> Eval:
    """prev_root — оценка с точки зрения соперника."""
    return e.negate()


def test_best_zone_a_and_neutral_flag():
    ls = lines(ev(30), ev(25), ev(10))
    r = run(ls, 0, prev=opp(ev(30)))
    assert r.step == "best"
    assert "neutral" in r.flags          # G ≈ 0
    assert [b["uci"] for b in r.best_moves] == ["e2e4"]


def test_several_best_moves_no_only_move():
    ls = lines(ev(30), ev(30), ev(-200))
    r = run(ls, 1, prev=opp(ev(30)))
    assert r.step == "best"
    assert len(r.best_moves) == 2
    assert r.subtype is None


def test_zone_b_is_near_best_not_best():
    ls = lines(ev(30), ev(27))
    r = run(ls, 1, prev=opp(ev(30)))
    assert r.step == "neutral"
    assert "near_best" in r.flags
    assert [b["uci"] for b in r.near_best_moves] == ["d2d4"]


def test_float_tolerance_at_eps1():
    ls = lines(ev(-35), ev(-36))
    r = run(ls, 1, prev=opp(ev(-35)))
    assert r.step == "best"


def test_only_move():
    # Соперник ошибся (было −0,5): только первый ход поднимает оценку над E0.
    ls = lines(ev(50), ev(-60), ev(-150))
    r = run(ls, 0, prev=opp(ev(-50)))
    # короткая линия без форсировки — лёгкий only
    assert r.step == "best" and r.subtype == "only_light"


def test_blunder_from_win_to_equal():
    ls = lines(ev(300))
    r = run(ls, played_eval=ev(0), prev=opp(ev(300)))
    assert r.step == "blunder"


def test_mistake_one_category():
    ls = lines(ev(100))
    r = run(ls, played_eval=ev(20), prev=opp(ev(100)))
    assert (r.cat_e1, r.cat_ep) == ("better", "equal")
    # смена категории сама по себе не ошибка: потеря 0,8 — слабость
    assert r.step == "laxity"
    # потеря больше пешки — ошибка
    assert run(ls, played_eval=ev(-10), prev=opp(ev(100))).step == "mistake"


def test_blunder_into_mate_from_lost_position():
    ls = lines(ev(-500))
    r = run(ls, played_eval=ev(mate=-3), prev=opp(ev(-500)))
    assert r.step == "blunder"


def test_laxity_inside_category():
    ls = lines(ev(150))
    r = run(ls, played_eval=ev(90), prev=opp(ev(150)))
    assert r.step == "laxity"
    # 0,1…0,5 — неточность, до 0,1 — нейтральный ход
    assert run(ls, played_eval=ev(120), prev=opp(ev(150))).step == "inaccuracy"
    assert run(ls, played_eval=ev(145), prev=opp(ev(150))).step == "neutral"


def test_inaccuracy():
    ls = lines(ev(40))
    r = run(ls, played_eval=ev(25), prev=opp(ev(25)))
    assert r.step == "inaccuracy"


def test_excellent_and_good_after_gift():
    prev = opp(ev(0))       # база 0
    ls = lines(ev(150))     # соперник отдал 1,5
    assert run(ls, played_eval=ev(120), prev=prev).step == "excellent"   # D/G = 0,8
    assert run(ls, played_eval=ev(70), prev=prev).step == "good"         # D/G ≈ 0,47


def test_pass_instead_of_inaccuracy():
    prev = opp(ev(0))
    ls = lines(ev(150))                       # соперник ошибся: равно → лучше
    r = run(ls, played_eval=ev(10), prev=prev)
    assert "pass" in r.flags
    # своя позиция не хуже, чем до подарка соперника — пропуск, а не ошибка
    assert r.step == "pass"
    ls = lines(ev(60))                        # G ниже T_pass, но категория та же
    r = run(ls, played_eval=ev(5), prev=prev)
    assert "pass" not in r.flags and r.step == "laxity"   # потеря 0,55


def test_pass_step_when_category_kept():
    prev = opp(ev(250))
    ls = lines(ev(400))                       # +1,5 внутри «выигрыша»
    r = run(ls, played_eval=ev(260), prev=prev)
    assert "pass" in r.flags and r.step == "pass"


def test_opponent_improving_is_not_laxity():
    # Соперник сыграл сильно (G < 0), игрок сыграл лучший ход — без laxity.
    prev = opp(ev(150))
    ls = lines(ev(80), ev(70))
    r = run(ls, 0, prev=prev)
    assert r.step == "best"
    r = run(ls, 1, prev=prev)
    assert r.step != "laxity"


def test_faster_mate_is_best_slower_is_excellent():
    ls = lines(ev(mate=3), ev(mate=5), ev(900))
    assert run(ls, 0, prev=opp(ev(mate=3))).step == "best"
    assert run(ls, 1, prev=opp(ev(mate=3))).step == "excellent"
    # В WDL мат в 3 и мат в 5 оба равны 1,0, но лучшим остаётся только быстрый.
    assert run(ls, 1, prev=opp(ev(mate=3)), s=WDL).step == "excellent"
    assert len(run(ls, 0, s=WDL).best_moves) == 1


def test_both_takes_stricter_verdict():
    # Проигранная позиция: WDL насыщен (0,0), пешки видят потерю 1,5.
    ls = lines(ev(-500, exp=0.0))
    r = run(ls, played_eval=ev(-650, exp=0.0), prev=opp(ev(-500, exp=0.0)), s=BOTH)
    assert r.unit_steps == {"pawns": "mistake", "wdl": "best"}
    assert r.step == "mistake" and r.decided_by == "pawns"


def test_first_move_has_no_base():
    ls = lines(ev(30))
    r = run(ls, 0, prev=None)
    assert r.e0 is None and r.cat_e0 is None
    assert r.pawns.g == 0
    assert "pass" not in r.flags


def test_trivial_position():
    ls = lines(ev(900), ev(850), ev(800), ev(700), ev(600))
    r = run(ls, 0, prev=opp(ev(900)))
    assert "trivial" in r.flags


def test_brilliant_sacrifice():
    board = chess.Board("r1b2rk1/ppp2ppp/2n5/3qN3/3P4/3B4/PP3PPP/R2Q1RK1 w - - 0 1")
    # Bxh7+ Kxh7 Qh5+ Kg8: слон отдан, оценка держится.
    pv = ["d3h7", "g8h7", "d1h5", "h7g8"]
    ls = [Line(move="d3h7", eval=ev(250), pv=pv), Line(move="d1h5", eval=ev(0), pv=["d1h5"])]
    r = classify(board, ls, ls[0], opp(ev(250)), PAWNS)
    assert r.step == "best"
    assert r.subtype == "brilliant"


def test_no_brilliant_in_lost_position():
    board = chess.Board("r1b2rk1/ppp2ppp/2n5/3qN3/3P4/3B4/PP3PPP/R2Q1RK1 w - - 0 1")
    pv = ["d3h7", "g8h7", "d1h5", "h7g8"]
    ls = [Line(move="d3h7", eval=ev(-400), pv=pv)]
    r = classify(board, ls, ls[0], opp(ev(-400)), PAWNS)
    assert r.subtype != "brilliant"


@pytest.mark.parametrize("unit", ["pawns", "wdl", "both"])
def test_all_units_run(unit):
    s = Settings(unit=unit)
    ls = lines(ev(30), ev(10), ev(-50))
    r = run(ls, 2, prev=opp(ev(30)), s=s)
    assert r.step in ("laxity", "inaccuracy", "mistake")


def test_both_zone_is_intersection_in_saturated_position():
    # Выигрыш: в WDL все три хода = 1,0 (зона A), в пешках лучший только первый.
    ls = lines(ev(900, exp=1.0), ev(700, exp=1.0), ev(500, exp=1.0))
    r = run(ls, 0, prev=opp(ev(900, exp=1.0)), s=BOTH)
    assert [b["uci"] for b in r.best_moves] == ["e2e4"]
    r = run(ls, 1, prev=opp(ev(900, exp=1.0)), s=BOTH)
    assert r.step != "best"


def test_mate_in_hopeless_position_is_not_blunder():
    # −36 пешек, почти все ходы проигрывают: ускорить мат — laxity, а не зевок.
    ls = lines(ev(-3600, exp=0.0), ev(-3700, exp=0.0), ev(-3800, exp=0.0), ev(-3900, exp=0.0), ev(-4000, exp=0.0))
    r = run(ls, played_eval=ev(mate=-5), prev=opp(ev(-3600, exp=0.0)))
    assert r.step == "laxity" and "hopeless" in r.flags
    # Не тривиальная проигранная позиция (есть ход, держащий «хуже»): правило 7 в силе.
    ls = lines(ev(-500), ev(-150))
    r = run(ls, played_eval=ev(mate=-5), prev=opp(ev(-500)))
    assert r.step == "blunder"


def test_forced_move_is_separate_step():
    # Единственный легальный ход: Крh8 под шахом ладьи g8 может только взять её.
    board = chess.Board("6Rk/8/6K1/8/8/8/8/8 b - - 0 1")
    assert [m.uci() for m in board.legal_moves] == ["h8g8"]
    only = [Line(move="h8g8", eval=ev(0, exp=0.5), pv=["h8g8"])]
    r = classify(board, only, only[0], opp(ev(-1500, exp=0.0)), BOTH)
    assert r.step == "forced" and r.subtype is None
    assert r.unit_steps == {"pawns": "forced", "wdl": "forced"}
    assert "pass" not in r.flags and "neutral" not in r.flags


def test_only_move_hold_and_two_improving():
    # Лучший ход только держит оценку, но все остальные роняют категорию —
    # only на удержание.
    ls = lines(ev(50), ev(-80), ev(-150))
    assert run(ls, 0, prev=opp(ev(50))).subtype == "only_light"
    # Другой ход держит ту же категорию — не единственный.
    ls = lines(ev(50), ev(20), ev(-150))
    assert run(ls, 0, prev=opp(ev(50))).subtype is None
    # Улучшают два хода — тоже не единственный.
    ls = lines(ev(50), ev(10), ev(-150))
    assert run(ls, 0, prev=opp(ev(-50))).subtype is None


def test_book_move_replaces_engine_verdict():
    # Гамбит в начале партии: движок даёт неточность, но ход по книге — «книга».
    ls = lines(ev(40), ev(-20))
    r = run(ls, 1, prev=opp(ev(40)))
    assert r.step != "best"
    r = classify(START, ls, ls[1], opp(ev(40)), PAWNS, opening="King's Gambit")
    assert r.step == "book" and r.engine_step != "book" and r.opening == "King's Gambit"
    assert r.flags == ["book"] and r.subtype is None
