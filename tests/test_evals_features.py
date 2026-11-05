import chess

from chessanalyst import features
from chessanalyst.classify import move_type
from chessanalyst.engine import Line
from chessanalyst.evals import Eval, after_move_to_root, category, previous_after_move_to_root
from chessanalyst.settings import PAWNS, WDL, Settings, load_settings

S = Settings()


def test_negate_swaps_wdl():
    e = Eval(cp=120, mate=None, wdl=(600, 300, 100)).negate()
    assert e.cp == -120 and e.wdl == (100, 300, 600)


def test_mate_values_prefer_faster():
    assert Eval(None, 2, (1000, 0, 0)).pawns(S) > Eval(None, 5, (1000, 0, 0)).pawns(S)
    assert Eval(None, 5, (1000, 0, 0)).pawns(S) > Eval(9000, None, (1000, 0, 0)).pawns(S)
    assert Eval(None, -2, (0, 0, 1000)).pawns(S) < Eval(None, -5, (0, 0, 1000)).pawns(S)


def test_mate_frame_projection():
    # Игрок матовал в 3 до хода → после лучшего хода у соперника «мат в 2» → снова 3.
    assert after_move_to_root(Eval(None, 2, (1000, 0, 0))).mate == 3
    assert after_move_to_root(Eval(None, -3, (0, 0, 1000))).mate == -3
    # Соперник матует в 3 после моего хода → после его хода мне мат в 2.
    assert previous_after_move_to_root(Eval(None, -3, (0, 0, 1000))).mate == -2
    assert previous_after_move_to_root(Eval(None, 4, (1000, 0, 0))).mate == 4


def test_categories():
    assert [category(x, WDL) for x in (0.1, 0.3, 0.5, 0.7, 0.9)] == [0, 1, 2, 3, 4]
    assert category(0.80, WDL) == 4 and category(0.20, WDL) == 1 and category(0.40, WDL) == 2
    assert [category(x, PAWNS) for x in (-3, -1, 0, 1, 3)] == [0, 1, 2, 3, 4]


def test_stage():
    assert features.stage(chess.Board(), S) == "opening"
    assert features.stage(chess.Board("8/5k2/8/8/8/8/2R2K2/8 w - - 0 40"), S) == "endgame"
    mid = chess.Board("r1bq1rk1/ppp2ppp/2np1n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQ1RK1 w - - 0 7")
    assert features.stage(mid, S) == "middlegame"


def test_mate_threat_and_forcing():
    # Угроза Rd8# уже есть: тихий ход короля её не создаёт.
    b = chess.Board("6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
    assert not features.creates_mate_threat(b, chess.Move.from_uci("g1f1"))
    # Ладья с a2 на a1 создаёт угрозу Ra8#.
    # Ладья c3-a3 создаёт угрозу Ra8# (по вертикали c мешает своя пешка).
    b = chess.Board("6k1/5ppp/8/8/2P5/2R5/5PPP/6K1 w - - 0 1")
    assert features.creates_mate_threat(b, chess.Move.from_uci("c3a3"))
    assert features.is_forcing(b, chess.Move.from_uci("c3a3"))


def _ln(move, cp, pv=None):
    return Line(move=move, eval=Eval(cp, None, (500, 0, 500)), pv=pv or [move])


def test_tactical_vs_positional():
    b = chess.Board("r1bqkbnr/pppp1ppp/2n5/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R w KQkq - 2 3")
    ln = _ln("f1c4", 30, ["f1c4", "g8f6", "d2d3", "f8c5"])
    t, _ = move_type(b, ln, [ln], S)
    assert t == "positional"
    # Bxf7+ Kxf7 Ng5+: три форсированных полухода из четырёх.
    b = chess.Board("r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4")
    sac = _ln("c4f7", 150, ["c4f7", "e8f7", "f3g5", "f7g8"])
    # тихая альтернатива сильно хуже — результат зависит от форсированных ходов
    # с шахом — тактика с направлением «атака»
    assert move_type(b, sac, [sac, _ln("d2d3", 20)], S) == ("tactical", ["attacking"])
    # тихая альтернатива та же по оценке — от форсированных ходов результат не зависит
    t, _ = move_type(b, sac, [sac, _ln("d2d3", 150)], S)
    assert t != "tactical"


def test_positional_subtypes():
    b = chess.Board("r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQ - 0 6")
    assert features.positional_subtypes(b, chess.Move.from_uci("f3g5"), S) == ["attack"]
    assert features.positional_subtypes(b, chess.Move.from_uci("a2a3"), S) == ["neutral"]
    # Конь e5 под ударом пешки: уход самой фигуры — отступление, не защита;
    # защита — ладья встаёт за коня.
    b = chess.Board("4k3/8/3p4/4N3/8/8/8/R3K3 w - - 0 1")
    assert features.positional_subtypes(b, chess.Move.from_uci("e5f3"), S) == ["neutral"]
    assert features.positional_subtypes(b, chess.Move.from_uci("a1a5"), S) == ["defense"]
    assert features.positional_subtypes(b, chess.Move.from_uci("a1a2"), S) == ["neutral"]


def test_move_directions():
    b = chess.Board("r1bq1rk1/pppp1ppp/2n2n2/2b1p3/2B1P3/2NP1N2/PPP2PPP/R1BQK2R w KQ - 0 6")
    # Ng5 — новая угроза f7 и давление на короля
    assert move_type(b, _ln("f3g5", 30), [_ln("f3g5", 30)], S) == ("positional", ["attacking"])
    assert move_type(b, _ln("a2a3", 30), [_ln("a2a3", 30)], S) == ("positional", [])
    # конь уходит из-под удара пешки — отступление; ладья его защищает
    b = chess.Board("4k3/8/3p4/4N3/8/8/8/R3K3 w - - 0 1")
    assert move_type(b, _ln("e5f3", 30), [_ln("e5f3", 30)], S) == ("positional", [])
    assert move_type(b, _ln("a1a5", 30), [_ln("a1a5", 30)], S) == ("positional", ["defensive"])


def test_capture_is_not_attack_or_defence_by_itself():
    # Взятие атакующей пешки: угроза снята взятием — это не защита; новых
    # угроз нет — и не атака.
    b = chess.Board("4k3/8/8/8/3p4/4N3/8/4K3 w - - 0 1")
    assert move_type(b, _ln("e3d5", 30), [_ln("e3d5", 30)], S)[1] != ["defensive"]
    # Защита + атака (скрин автора): ферзь защищает пешку c4 и вторым нападает на d5.
    b = chess.Board("4k3/8/8/3p4/2P5/Q7/8/4K3 w - - 0 1")
    t, dirs = move_type(b, _ln("a3d3", 30), [_ln("a3d3", 30)], S)
    assert dirs == ["attacking", "defensive"]
    # Угроза осталась (слон под ударом пешки), а ход создал свою — контратака
    # вместе с частичной защитой.
    b = chess.Board("4k3/8/8/3p4/2B5/Q7/8/4K3 w - - 0 1")
    assert move_type(b, _ln("a3d3", 30), [_ln("a3d3", 30)], S)[1] == ["counterattacking", "defensive"]


def test_en_prise_and_exchange_sac():
    b = chess.Board("r1b2rk1/ppp2ppp/2n5/3qN3/3P4/3B4/PP3PPP/R2Q1RK1 w - - 0 1")
    assert features.leaves_piece_en_prise(b, chess.Move.from_uci("d3h7"))
    assert not features.leaves_piece_en_prise(b, chess.Move.from_uci("d1d2"))


def test_settings_version_and_toml(tmp_path):
    p = tmp_path / "s.toml"
    p.write_text('unit = "pawns"\ndepth = 20\n[pawns]\neps2 = 0.08\n', encoding="utf-8")
    s = load_settings(p)
    assert s.unit == "pawns" and s.depth == 20 and s.pawns.eps2 == 0.08
    assert s.version != Settings().version
    # путь к движку не влияет на версию меток
    assert Settings(engine_path="x").version == Settings().version
    assert Settings(depth=20).version == Settings().version   # глубина — отдельный ключ


def test_material_left_en_prise():
    # 17...Сe6 Бирн — Фишер: слон уходит, ферзь b6 остаётся под боем слона c5.
    b = chess.Board("r3r1k1/pp3pbp/1qp3p1/2B5/2BP2b1/Q1n2N2/P4PPP/3R1K1R b - - 3 17")
    assert features.leaves_material_en_prise(b, chess.Move.from_uci("g4e6"))
    assert not features.leaves_piece_en_prise(b, chess.Move.from_uci("g4e6"))
    # Уход от шаха с оставленной фигурой — не жертва.
    b = chess.Board("4k3/8/8/8/8/8/r7/4R1K1 b - - 0 1")
    assert not features.leaves_material_en_prise(b, chess.Move.from_uci("e8d7"))
