"""Эталон для переноса на Dart не устарел: Python на данных ассета даёт то же,
что записано в app/test/fixtures. Если логика классификации меняется, этот тест
падает, пока эталон не перегенерирован tools/export_flutter_fixture.py, а после
этого падает Dart-тест, пока изменение не перенесено в app/lib/analysis."""

import json
from dataclasses import replace
from pathlib import Path

import chess
import pytest

from chessanalyst.engine import Line
from chessanalyst.ideas import find_ideas
from chessanalyst.pipeline import PlyAnalysis, classify_analysed
from chessanalyst.settings import Settings

APP = Path(__file__).resolve().parent.parent / "app"
GAMES = ["byrne_fischer_1956", "kasparov_topalov_1999", "morphy_opera_1858", "perfect_game"]


def _lines(xs):
    return None if xs is None else [Line.from_json(x) for x in xs]


@pytest.mark.parametrize("name", GAMES)
@pytest.mark.parametrize("unit", ["both", "pawns", "wdl"])
def test_fixture_matches_python(name, unit):
    game = json.loads((APP / "assets" / "games" / f"{name}.json").read_text(encoding="utf-8"))
    expected = json.loads((APP / "test" / "fixtures" / f"{name}.expected.json").read_text(encoding="utf-8"))
    expected = expected["units"][unit]
    analysed = [PlyAnalysis(chess.Board(p["fen_before"]), _lines(p["lines"]), Line.from_json(p["played"]),
                            _lines(p["all_lines"])) for p in game["plies"]]
    s = replace(Settings(), unit=unit)
    records = classify_analysed(analysed, s)
    got = [(r.step, r.subtype, sorted(r.flags), [b["uci"] for b in r.best_moves], r.opening) for r in records]
    want = [(e["step"], e["subtype"], e["flags"], e["best"], e["opening"]) for e in expected["records"]]
    assert got == want
    ideas = find_ideas(analysed, records, s)
    assert [(i.punish_ply, i.start_ply, i.miss_ply, i.chunk) for i in ideas] == \
        [(e["punish_ply"], e["start_ply"], e["miss_ply"], e["chunk"]) for e in expected["ideas"]]
