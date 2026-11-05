"""Rewrites the Python reference labels (app/test/fixtures/*.expected.json)
from the engine data already stored in the app's game assets — no engine and
no database needed. Run after changing the classification in chessanalyst,
then port the same change to app/lib/analysis until the Dart test passes.

  python3 tools/refresh_fixtures.py
"""

from __future__ import annotations

import json
import sys
from dataclasses import replace
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "tools"))

from chessanalyst.engine import Line  # noqa: E402
from chessanalyst.ideas import find_ideas  # noqa: E402
from chessanalyst.pipeline import PlyAnalysis, classify_analysed  # noqa: E402
from chessanalyst.settings import Settings  # noqa: E402
from export_flutter_fixture import record_json  # noqa: E402

GAMES = [
    "byrne_fischer_1956", "kasparov_topalov_1999", "morphy_opera_1858", "perfect_game",
    "immortal_zugzwang", "evergreen_game",
    *[f"alphazero_{i:02d}" for i in range(1, 11)],
    "sf_kings_gambit", "sf_najdorf", "sf_grunfeld", "sf_english",
]
# тестовые партии вне приложения: данные и эталон лежат вместе в app/test/games
TEST_GAMES = ["mrkakakat_2026_11_04"]


def _lines(xs):
    return None if xs is None else [Line.from_json(x) for x in xs]


def main() -> None:
    jobs = [(ROOT / "app/assets/games" / f"{n}.json", ROOT / "app/test/fixtures" / f"{n}.expected.json") for n in GAMES]
    jobs += [(ROOT / "app/test/games" / f"{n}.json", ROOT / "app/test/games" / f"{n}.expected.json") for n in TEST_GAMES]
    for src, out in jobs:
        if not src.exists():
            continue
        game = json.loads(src.read_text(encoding="utf-8"))
        analysed = [PlyAnalysis(chess.Board(p["fen_before"]), _lines(p["lines"]), Line.from_json(p["played"]),
                                _lines(p["all_lines"])) for p in game["plies"]]
        base = Settings()
        # версия настроек — как при экспорте с движком (она учитывает путь к движку и глубину)
        old = json.loads(out.read_text(encoding="utf-8"))["settings_version"] if out.exists() else base.version
        expected = {"settings_version": old, "units": {}}
        for unit in ("both", "pawns", "wdl"):
            s = replace(base, unit=unit)
            records = classify_analysed(analysed, s)
            ideas = find_ideas(analysed, records, s)
            expected["units"][unit] = {
                "records": [record_json(r) for r in records],
                "ideas": [{**i.to_json(), "signature_text": i.signature.text()} for i in ideas],
            }
        out.write_text(json.dumps(expected, ensure_ascii=False, indent=1), encoding="utf-8")
        print(out.relative_to(ROOT))


if __name__ == "__main__":
    main()
