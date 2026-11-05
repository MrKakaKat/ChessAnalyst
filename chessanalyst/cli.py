"""Командная строка.

  python -m chessanalyst load partii.pgn            # PGN → очередь в базе
  python -m chessanalyst list                       # очередь партий
  python -m chessanalyst analyze 1 2                # движок + классификация
  python -m chessanalyst run partii.pgn -o out.txt  # всё сразу
  python -m chessanalyst serve                      # веб-интерфейс
  python -m chessanalyst stability 1 --depths 18 20 # стабильность меток
  python -m chessanalyst puzzles lichess_db_puzzle.csv.zst --themes pawnEndgame rookEndgame
  python -m chessanalyst chesscom <ник> --months 3
"""

from __future__ import annotations

import argparse
import shutil
import sys

from . import chesscom, db, pgn_io, puzzles, report
from .engine import Analyzer
from .pipeline import classify_game, stability, timed
from .settings import UNITS, load_settings


def _settings(args):
    s = load_settings(args.settings)
    engine = args.engine or s.engine_path
    if shutil.which(engine) is None and engine == "stockfish" and shutil.which("/usr/games/stockfish"):
        engine = "/usr/games/stockfish"
    return s.with_overrides(unit=args.unit, depth=args.depth, multipv=args.multipv,
                            time_per_position=args.time, engine_path=engine)


def _add_common(p: argparse.ArgumentParser) -> None:
    p.add_argument("--db", default="chessanalyst.sqlite", help="файл базы SQLite")
    p.add_argument("--settings", help="TOML с порогами (см. settings.example.toml)")
    p.add_argument("--engine", help="путь к Stockfish")
    p.add_argument("--unit", choices=UNITS, help="единица: pawns, wdl или both")
    p.add_argument("--depth", type=int, help="глубина анализа (по умолчанию 18)")
    p.add_argument("--multipv", type=int, help="число линий (по умолчанию 5)")
    p.add_argument("--time", type=float, help="ограничение секунд на позицию")
    p.add_argument("-o", "--out", help="файл вывода: .txt, .csv или .json "
                                       "(для нескольких партий к имени добавляется id)")
    p.add_argument("-q", "--quiet", action="store_true", help="не печатать таблицу ходов")


def _progress(done: int, total: int) -> None:
    print(f"\r  позиция {done}/{total}", end="" if done < total else "\n", file=sys.stderr, flush=True)


def _analyze(conn, s, game_ids: list[int], args) -> None:
    with Analyzer(conn, s) as an:
        for gid in game_ids:
            g = conn.execute("SELECT * FROM games WHERE id = ?", (gid,)).fetchone()
            if g is None:
                print(f"партия {gid} не найдена", file=sys.stderr)
                continue
            title = pgn_io.game_label(g)
            print(f"Анализ {title}", file=sys.stderr)
            records, secs = timed(classify_game, an, gid, None if args.quiet else _progress)
            print(f"  готово за {secs:.0f} с (поисков {an.stats['searches']}, "
                  f"из кэша {an.stats['cache_hits']})", file=sys.stderr)
            ideas = conn.execute(
                "SELECT * FROM ideas WHERE game_id = ? AND settings_version = ? AND depth = ? "
                "ORDER BY punish_ply", (gid, s.version, s.depth)).fetchall()
            if not args.quiet:
                print(report.format_text(records, s, title))
                print()
                print(report.format_ideas(ideas, records))
                print()
            if args.out:
                out = args.out
                if len(game_ids) > 1:
                    stem, dot, ext = out.rpartition(".")
                    out = f"{stem}_{gid}.{ext}" if dot else f"{out}_{gid}"
                report.write_file(records, s, out, title, ideas)
                print(f"  записано в {out}", file=sys.stderr)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="chessanalyst", description="ChessAnalyst")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_load = sub.add_parser("load", help="загрузить PGN в очередь")
    p_load.add_argument("pgn", nargs="+")
    p_load.add_argument("--db", default="chessanalyst.sqlite")

    p_list = sub.add_parser("list", help="показать очередь партий")
    p_list.add_argument("--db", default="chessanalyst.sqlite")

    p_an = sub.add_parser("analyze", help="анализ и классификация партий из базы")
    p_an.add_argument("game_ids", nargs="*", type=int, help="id партий (по умолчанию — все в очереди)")
    _add_common(p_an)

    p_run = sub.add_parser("run", help="загрузить PGN и сразу разобрать")
    p_run.add_argument("pgn", nargs="+")
    _add_common(p_run)

    p_srv = sub.add_parser("serve", help="локальное веб-приложение")
    _add_common(p_srv)
    p_srv.add_argument("--host", default="127.0.0.1")
    p_srv.add_argument("--port", type=int, default=8765)

    p_st = sub.add_parser("stability", help="сравнить метки на двух глубинах (6.7)")
    p_st.add_argument("game_id", type=int)
    p_st.add_argument("--depths", type=int, nargs=2, default=[18, 20])
    _add_common(p_st)

    p_pz = sub.add_parser("puzzles", help="импорт базы задач Lichess (csv или csv.zst)")
    p_pz.add_argument("path")
    p_pz.add_argument("--db", default="chessanalyst.sqlite")
    p_pz.add_argument("--themes", nargs="*", help="оставить задачи с любой из тем")
    p_pz.add_argument("--min-rating", type=int, default=0)
    p_pz.add_argument("--max-rating", type=int, default=4000)
    p_pz.add_argument("--min-popularity", type=int, default=-100)
    p_pz.add_argument("--limit", type=int)

    p_cc = sub.add_parser("chesscom", help="импорт партий игрока с chess.com в очередь")
    p_cc.add_argument("user")
    p_cc.add_argument("--db", default="chessanalyst.sqlite")
    p_cc.add_argument("--months", type=int, default=1)
    p_cc.add_argument("--time-classes", nargs="*", default=["rapid"])
    p_cc.add_argument("--results", nargs="*", choices=["win", "draw", "loss"], default=["loss", "draw"])
    p_cc.add_argument("--min-moves", type=int, default=20)
    p_cc.add_argument("--with-easy", action="store_true", help="не отсекать партии против слабых")
    p_cc.add_argument("--limit", type=int)

    p_pref = sub.add_parser("prefs", help="рейтинг задач и ник игрока")
    p_pref.add_argument("--db", default="chessanalyst.sqlite")
    p_pref.add_argument("--rating", type=int)
    p_pref.add_argument("--name")

    args = ap.parse_args(argv)
    conn = db.connect(args.db)

    if args.cmd == "puzzles":
        n = puzzles.import_puzzles(conn, args.path, themes=set(args.themes) if args.themes else None,
                                   min_rating=args.min_rating, max_rating=args.max_rating,
                                   min_popularity=args.min_popularity, limit=args.limit)
        print(f"импортировано задач: {n}")
        return 0

    if args.cmd == "chesscom":
        ids = chesscom.import_user(conn, args.user, months=args.months, time_classes=set(args.time_classes),
                                   results=set(args.results), min_moves=args.min_moves,
                                   skip_easy=not args.with_easy, limit=args.limit)
        db.set_pref(conn, "player_name", args.user)
        print(f"в очередь добавлено партий: {len(ids)}")
        return 0

    if args.cmd == "prefs":
        if args.rating:
            db.set_pref(conn, "player_rating", str(args.rating))
        if args.name is not None:
            db.set_pref(conn, "player_name", args.name)
        print(f"рейтинг задач: {db.get_pref(conn, 'player_rating', '1500')}, "
              f"игрок: {db.get_pref(conn, 'player_name', '') or '—'}")
        return 0

    if args.cmd == "load":
        for path in args.pgn:
            ids = pgn_io.load_pgn_file(conn, path)
            print(f"{path}: партий {len(ids)} (id {', '.join(map(str, ids))})")
        return 0

    if args.cmd == "list":
        for g in conn.execute("SELECT * FROM games ORDER BY id"):
            n = conn.execute("SELECT COUNT(*) FROM plies WHERE game_id = ?", (g["id"],)).fetchone()[0]
            print(f"{pgn_io.game_label(g)}  [{g['result']}, полуходов {n}, {g['status']}]")
        return 0

    s = _settings(args)
    if args.cmd == "serve":
        from .web.server import serve
        conn.close()
        serve(args.db, s, args.host, args.port)
        return 0
    if args.cmd == "stability":
        with Analyzer(conn, s) as an:
            res = stability(an, args.game_id, tuple(args.depths), None if args.quiet else _progress)
        print(f"глубины {res['depths'][0]} и {res['depths'][1]}, полуходов {res['plies']}: "
              f"ступени совпали в {res['step_agreement']:.0%}, состав лучших — в {res['best_set_agreement']:.0%}")
        for d in res["diffs"]:
            print(f"  {report._ply_text(d['ply'])} {d['san']}: {d['steps'][0]} → {d['steps'][1]}, "
                  f"лучшие {' '.join(d['best'][0])} → {' '.join(d['best'][1])}")
        return 0
    if args.cmd == "run":
        ids = []
        for path in args.pgn:
            ids += pgn_io.load_pgn_file(conn, path)
    else:
        ids = args.game_ids or [r["id"] for r in conn.execute(
            "SELECT id FROM games WHERE status = 'queued' ORDER BY id")]
    if not ids:
        print("нет партий для анализа", file=sys.stderr)
        return 1
    _analyze(conn, s, ids, args)
    return 0
