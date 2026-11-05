"""Вывод результатов в консоль и в файл (этап 2)."""

from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path

from .classify import MoveRecord
from .settings import Settings

STEP_LABELS = {
    "best": "лучший", "excellent": "отличный", "good": "хороший", "neutral": "нейтральный",
    "inaccuracy": "неточность", "pass": "pass", "laxity": "laxity",
    "mistake": "mistake", "blunder": "blunder", "forced": "вынужденный", "book": "книга",
}
STEP_MARKS = {
    "best": "!", "excellent": "!", "good": "", "neutral": "", "inaccuracy": "?!",
    "pass": "(pass)", "laxity": "!?", "mistake": "?", "blunder": "??", "forced": "□", "book": "",
}


def _move_text(r: MoveRecord) -> str:
    no = r.ply // 2 + 1
    return f"{no}. {r.san}" if r.side == "white" else f"{no}... {r.san}"


def _vals(r: MoveRecord, unit: str) -> str:
    def fmt_p(x):
        return f"{x:+6.2f}"

    def fmt_w(x):
        return f"{x:5.3f}"

    parts = []
    if unit in ("pawns", "both"):
        parts.append(f"E1 {fmt_p(r.pawns.e1)} Ep {fmt_p(r.pawns.ep)} L {r.pawns.l:5.2f}")
    if unit in ("wdl", "both"):
        parts.append(f"E1 {fmt_w(r.wdl.e1)} Ep {fmt_w(r.wdl.ep)} L {r.wdl.l:5.3f}")
    return " | ".join(parts)


def format_text(records: list[MoveRecord], s: Settings, title: str = "") -> str:
    out = []
    if title:
        out.append(title)
    out.append(f"глубина {s.depth}, MultiPV {s.multipv}, единица {s.unit}, настройки v{s.version}")
    out.append("")
    for r in records:
        step = STEP_LABELS[r.step] + STEP_MARKS[r.step]
        extra = []
        if r.subtype:
            extra.append(r.subtype)
        extra += r.flags
        typ = r.move_type + (f"({','.join(r.type_subtypes)})" if r.type_subtypes else "")
        best = ", ".join(b["san"] for b in r.best_moves)
        line = (f"{_move_text(r):<14} {step:<14} {typ:<26} {r.stage:<10} "
                f"{_vals(r, s.unit)}  [{r.cat_e1}→{r.cat_ep}]")
        if r.opening:
            line += f"  {{{r.opening}}}"
        if r.step not in ("best", "forced", "book"):
            line += f"  лучш.: {best}"
        if extra:
            line += f"  {{{', '.join(extra)}}}"
        if len(set(r.unit_steps.values())) > 1:
            line += "  (" + ", ".join(f"{u}: {STEP_LABELS[k]}" for u, k in r.unit_steps.items()) + ")"
        out.append(line)
    out.append("")
    out.append(summary(records))
    return "\n".join(out)


def summary(records: list[MoveRecord]) -> str:
    out = ["Итог по сторонам:"]
    for side in ("white", "black"):
        rs = [r for r in records if r.side == side]
        c = Counter(r.step for r in rs)
        passes = sum("pass" in r.flags for r in rs)
        parts = [f"{STEP_LABELS[k]} {c[k]}" for k in STEP_LABELS if c[k]]
        out.append(f"  {side:<6}: " + ", ".join(parts) + (f"; pass-флагов {passes}" if passes else ""))
    by_stage = Counter((r.stage, r.step) for r in records if r.step in ("laxity", "mistake", "blunder"))
    if by_stage:
        out.append("Ошибки по стадиям: " + ", ".join(f"{st}/{STEP_LABELS[k]} {n}"
                                                       for (st, k), n in sorted(by_stage.items())))
    return "\n".join(out)


def record_dict(r: MoveRecord) -> dict:
    return {
        "ply": r.ply, "move": _move_text(r), "side": r.side, "san": r.san, "uci": r.uci,
        "fen_before": r.fen_before,
        "e0": str(r.e0) if r.e0 else None, "e1": str(r.e1), "ep": str(r.ep),
        "pawns": {"e0": r.pawns.e0, "e1": r.pawns.e1, "ep": r.pawns.ep,
                  "g": r.pawns.g, "d": r.pawns.d, "l": r.pawns.l},
        "wdl": {"e0": r.wdl.e0, "e1": r.wdl.e1, "ep": r.wdl.ep,
                "g": r.wdl.g, "d": r.wdl.d, "l": r.wdl.l},
        "categories": {"e0": r.cat_e0, "e1": r.cat_e1, "ep": r.cat_ep},
        "step": r.step, "decided_by": r.decided_by, "unit_steps": r.unit_steps,
        "subtype": r.subtype,
        "move_type": r.move_type, "type_subtypes": r.type_subtypes,
        "flags": r.flags, "stage": r.stage,
        "best_moves": r.best_moves, "near_best_moves": r.near_best_moves,
    }


def idea_dict(row) -> dict:
    d = dict(row)
    for k in ("signature", "chain", "builder_plies"):
        d[k] = json.loads(d[k])
    return d


def write_file(records: list[MoveRecord], s: Settings, path: str | Path, title: str = "",
               ideas=()) -> None:
    path = Path(path)
    if path.suffix == ".json":
        payload = {"title": title, "settings_version": s.version, "depth": s.depth,
                   "unit": s.unit, "moves": [record_dict(r) for r in records],
                   "ideas": [idea_dict(i) for i in ideas]}
        path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    elif path.suffix == ".csv":
        with path.open("w", newline="", encoding="utf-8") as f:
            w = csv.writer(f)
            w.writerow(["ply", "move", "side", "uci", "step", "subtype", "type", "type_subtypes",
                        "flags", "stage", "cat_e1", "cat_ep",
                        "e0_pawns", "e1_pawns", "ep_pawns", "g_pawns", "d_pawns", "l_pawns",
                        "e0_wdl", "e1_wdl", "ep_wdl", "g_wdl", "d_wdl", "l_wdl", "best"])
            for r in records:
                w.writerow([r.ply, _move_text(r), r.side, r.uci, r.step, r.subtype or "", r.move_type,
                            ";".join(r.type_subtypes), ";".join(r.flags), r.stage, r.cat_e1, r.cat_ep,
                            *(round(x, 3) for x in (r.pawns.e0, r.pawns.e1, r.pawns.ep,
                                                    r.pawns.g, r.pawns.d, r.pawns.l)),
                            *(round(x, 4) for x in (r.wdl.e0, r.wdl.e1, r.wdl.ep,
                                                    r.wdl.g, r.wdl.d, r.wdl.l)),
                            " ".join(b["san"] for b in r.best_moves)])
    else:
        path.write_text(format_text(records, s, title) + "\n\n" + format_ideas(ideas, records) + "\n",
                        encoding="utf-8")


def _ply_text(ply: int) -> str:
    no = ply // 2 + 1
    return f"{no}." if ply % 2 == 0 else f"{no}..."


def format_ideas(rows, records: list[MoveRecord]) -> str:
    """Идейные цепочки (8.3) в виде текста: наказание, начало, пропуск, дистанция."""
    if not rows:
        return "Идейных цепочек нет."
    out = ["Идейные цепочки:"]

    def before(ply: int) -> str:
        if ply < len(records):
            return f"перед {_ply_text(ply)} {records[ply].san}"
        return "после последнего хода"

    for r in rows:
        k = r["punish_ply"]
        rec = records[k] if k < len(records) else None
        what = f"{_ply_text(k)} {rec.san}" if rec else f"полуход {k}"
        if r["kind"] == "pass":
            out.append(f"  pass {what} ({r['owner']}): упущена идея {r['chunk']}; "
                       f"идея доступна {before(r['start_ply'])}")
            continue
        miss = r["miss_ply"]
        miss_txt = f"{_ply_text(miss)} {records[miss].san}" if miss is not None and miss < len(records) else "—"
        out.append(f"  {what} ({r['victim']}) наказано идеей {r['chunk']}")
        out.append(f"      начало идеи: {before(r['start_ply'])}, пропуск: {miss_txt}, "
                   f"дистанция {r['distance']} полуход(а)")
    return "\n".join(out)
