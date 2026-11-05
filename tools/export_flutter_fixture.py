"""Экспорт партии для приложения Flutter.

Пишет два файла:
  app/assets/games/<name>.json            — партия и сырые данные Stockfish по каждому
                                            полуходу (MultiPV, сыгранный ход, все ходы
                                            для тривиальных позиций). Классифицирует их
                                            уже Dart-код приложения.
  app/test/fixtures/<name>.expected.json  — метки и идеи, которые дал Python, для всех
                                            трёх единиц: эталон для теста переноса.

  python tools/export_flutter_fixture.py examples/game_of_the_century.pgn byrne_fischer_1956 \
      --db chessanalyst.sqlite --depth 18
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import replace
from pathlib import Path

import chess.pgn

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from chessanalyst import db, pgn_io  # noqa: E402
from chessanalyst.engine import Analyzer  # noqa: E402
from chessanalyst.ideas import find_ideas  # noqa: E402
from chessanalyst.openings import DATA as BOOK, WEIGHTS  # noqa: E402
from chessanalyst.pipeline import analyze_game, classify_analysed  # noqa: E402
from chessanalyst.settings import Settings  # noqa: E402


def line_json(ln) -> dict:
    return {"move": ln.move, "eval": ln.eval.to_json(), "pv": ln.pv}


def record_json(r) -> dict:
    return {
        "ply": r.ply, "san": r.san, "step": r.step, "subtype": r.subtype,
        "flags": sorted(r.flags), "move_type": r.move_type, "type_subtypes": r.type_subtypes,
        "stage": r.stage, "decided_by": r.decided_by, "unit_steps": r.unit_steps,
        "cat_e1": r.cat_e1, "cat_ep": r.cat_ep,
        "best": [b["uci"] for b in r.best_moves], "near_best": [b["uci"] for b in r.near_best_moves],
        "opening": r.opening, "engine_step": r.engine_step,
        "pawns": [round(x, 6) for x in (r.pawns.e0, r.pawns.e1, r.pawns.ep)],
        "wdl": [round(x, 6) for x in (r.wdl.e0, r.wdl.e1, r.wdl.ep)],
    }


def termination(pgn_path: str) -> str:
    """How the game ended: mate, resign, time, draw or unknown (PGN Termination tag
    first; a decisive game that does not end in mate counts as a resignation)."""
    with open(pgn_path, encoding="utf-8") as f:
        game = chess.pgn.read_game(f)
    tag = game.headers.get("Termination", "").lower()
    result = game.headers.get("Result", "*")
    board = game.end().board()
    if "time" in tag:
        return "time"
    if board.is_checkmate():
        return "mate"
    if result in ("1-0", "0-1"):
        return "resign"
    if result == "1/2-1/2":
        return "draw"
    return "unknown"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("pgn")
    ap.add_argument("name")
    ap.add_argument("--db", default="chessanalyst.sqlite")
    ap.add_argument("--depth", type=int, default=18)
    ap.add_argument("--engine", default="stockfish")
    ap.add_argument("--multipv", type=int, default=10)
    args = ap.parse_args()

    conn = db.connect(args.db)
    gid = pgn_io.load_pgn_file(conn, args.pgn)[0]
    g = conn.execute("SELECT * FROM games WHERE id = ?", (gid,)).fetchone()
    base = Settings(engine_path=args.engine, depth=args.depth, multipv=args.multipv)
    with Analyzer(conn, base) as an:
        analysed = analyze_game(an, gid)

    plies = conn.execute("SELECT * FROM plies WHERE game_id = ? ORDER BY ply", (gid,)).fetchall()
    asset = {
        "id": args.name,
        "headers": {**{k: g[k] for k in ("event", "site", "date", "round", "white", "black", "result")},
                    "termination": termination(args.pgn)},
        "start_fen": g["start_fen"],
        "engine": {"name": "Stockfish 16", "depth": args.depth, "multipv": base.multipv,
                   "trivial_depth": base.trivial_depth},
        "plies": [{
            "san": p["san"], "uci": p["uci"], "fen_before": p["fen_before"],
            "lines": [line_json(ln) for ln in a.lines],
            "played": line_json(a.played),
            "all_lines": [line_json(ln) for ln in a.all_lines] if a.all_lines is not None else None,
        } for p, a in zip(plies, analysed)],
    }

    expected = {"settings_version": base.version, "units": {}}
    for unit in ("both", "pawns", "wdl"):
        s = replace(base, unit=unit)
        records = classify_analysed(analysed, s)
        ideas = find_ideas(analysed, records, s)
        expected["units"][unit] = {
            "records": [record_json(r) for r in records],
            "ideas": [{**i.to_json(), "signature_text": i.signature.text()} for i in ideas],
        }

    out_asset = ROOT / "app" / "assets" / "games" / f"{args.name}.json"
    out_expected = ROOT / "app" / "test" / "fixtures" / f"{args.name}.expected.json"
    out_asset.parent.mkdir(parents=True, exist_ok=True)
    out_expected.parent.mkdir(parents=True, exist_ok=True)
    out_asset.write_text(json.dumps(asset, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    out_expected.write_text(json.dumps(expected, ensure_ascii=False, indent=1), encoding="utf-8")
    book = ROOT / "app" / "assets" / "openings_book.json"
    book.write_bytes(BOOK.read_bytes())
    (ROOT / "app" / "assets" / "openings_weights.json").write_bytes(WEIGHTS.read_bytes())
    print(f"{out_asset} ({out_asset.stat().st_size // 1024} КБ), {out_expected}, {book.name}")


if __name__ == "__main__":
    main()
