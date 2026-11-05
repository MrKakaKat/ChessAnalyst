"""Классификация хода (разделы 6 и 7).

Величины с точки зрения ходящего, в рамке позиции, где он на ходу:
  E0 — оценка после его предыдущего хода (база), E1 — лучший ход сейчас,
  Ep — сыгранный ход.  G = E1 − E0,  D = Ep − E0,  L = E1 − Ep.

Порядок проверки (первое совпадение побеждает):
  blunder → mistake → лучший (зона A) → отличный/хороший → laxity → неточность.
Метки pass, neutral, near_best, only_move, brilliant, underpress ставятся отдельно.

Единица "both": ход классифицируется в пешках и в WDL независимо, в запись идёт
более строгий вердикт. WDL насыщается в решённых позициях (0 или 1 при любом
перевесе), пешки — нет; так ошибка видна, если она видна хотя бы в одной единице.
"""

from __future__ import annotations

from dataclasses import dataclass, field

import chess

from . import features
from .engine import Line
from .evals import Eval, category, previous_after_move_to_root
from .settings import CATEGORIES, EQUAL, LOSS, WIN, Settings

# От лучшего к худшему; при unit="both" выбирается ступень с большим индексом.
# Допуск на плавающую точку: −0,35 − (−0,36) не должно превышать ε1 = 0,01.
_TOL = 1e-9

# «Вынужденный» (единственный легальный ход) — вне шкалы качества: выбора не было.
FORCED = "forced"
# Ход по книге дебютов (openings.py): теория вместо вердикта движка.
BOOK = "book"

STEPS = ("best", "excellent", "good", "neutral", "inaccuracy", "pass", "laxity", "mistake", "blunder")


@dataclass
class Values:
    """E0/E1/Ep и производные в одной единице."""

    e0: float
    e1: float
    ep: float

    @property
    def g(self) -> float:
        return self.e1 - self.e0

    @property
    def d(self) -> float:
        return self.ep - self.e0

    @property
    def l(self) -> float:
        return self.e1 - self.ep

    @property
    def drop(self) -> float:
        """Падение относительно базы. Если соперник сам улучшил позицию (G < 0),
        базой служит E1: иначе его хороший ход записался бы игроку в laxity."""
        return self.ep - min(self.e0, self.e1)


@dataclass
class MoveRecord:
    ply: int
    side: str
    san: str
    uci: str
    fen_before: str
    e0: Eval | None
    e1: Eval
    ep: Eval
    pawns: Values
    wdl: Values
    cat_e0: str | None
    cat_e1: str
    cat_ep: str
    step: str
    subtype: str | None
    move_type: str
    type_subtypes: list[str]
    flags: list[str] = field(default_factory=list)
    best_moves: list[dict] = field(default_factory=list)
    near_best_moves: list[dict] = field(default_factory=list)
    stage: str = "middlegame"
    decided_by: str = "wdl"                                    # единица, давшая вердикт
    unit_steps: dict[str, str] = field(default_factory=dict)  # ступень в каждой единице
    opening: str | None = None      # название дебюта, если ход по книге
    engine_step: str | None = None  # вердикт движка, заменённый на book


@dataclass
class _UnitVerdict:
    unit: str
    step: str
    flags: list[str]
    zone_a: list[Line]
    zone_b: list[Line]
    played_zone: str | None
    only_move: bool
    c0: int | None
    c1: int
    cp: int


def _zone(best: Eval, cand: Eval, l: float, eps1: float, eps2: float) -> str | None:
    """Зона A («лучший»), B («практически равен лучшему») или None (6.7).

    Если в сравнении участвует мат, допусков нет: лучший — только мат за то же
    число ходов (быстрейший), иначе WDL уравнял бы мат в 3 и мат в 10.
    """
    if best.mate is not None or cand.mate is not None:
        return "A" if best.structurally_equal(cand) else None
    if best.structurally_equal(cand) or l <= eps1 + _TOL:
        return "A"
    if l <= eps2 + _TOL:
        return "B"
    return None


def _verdict(unit: str, e0: Eval | None, e1: Eval, ep: Eval, lines: list[Line], played: Line,
             n_legal: int, s: Settings) -> _UnitVerdict:
    p = s.pawns if unit == "pawns" else s.wdl
    base = e0 if e0 is not None else e1
    v = Values(base.value(unit, s), e1.value(unit, s), ep.value(unit, s))

    c0 = category(v.e0, p) if e0 is not None else None
    c1 = category(v.e1, p)
    cp = category(v.ep, p)

    def zone_of(line: Line) -> str | None:
        return _zone(e1, line.eval, v.e1 - line.eval.value(unit, s), p.eps1, p.eps2)

    zone_a = [ln for ln in lines if zone_of(ln) == "A"]
    zone_b = [ln for ln in lines if zone_of(ln) == "B"]
    played_zone = zone_of(played)
    mated_now = ep.mate is not None and ep.mate < 0 and not (e1.mate is not None and e1.mate < 0)

    flags: list[str] = []
    # [авторское] по потере L: > 1 пешки — ошибка, > 0,5 — слабость (laxity),
    # > 0,1 — неточность, колебания до 0,1 — нейтральный ход
    if (c1 == WIN and cp <= EQUAL) or (c1 == LOSS and mated_now) or (c1 - cp >= 2):
        step = "blunder"
    elif e1.mate is not None and e1.mate > 0 and ep.mate is not None and ep.mate > e1.mate:
        step = "excellent"  # более медленный мат (6.7)
    elif v.l > p.mistake_loss + _TOL:
        step = "mistake"
    elif played_zone == "A":
        step = "best"
    elif v.g >= p.g_significant and v.d / v.g >= s.excellent_ratio:
        step = "excellent"
    elif v.g >= p.g_significant and v.d / v.g >= s.good_ratio:
        step = "good"
    elif v.l > p.laxity_loss + _TOL:
        step = "laxity"
    elif v.l > p.inaccuracy_loss + _TOL:
        step = "inaccuracy"
    else:
        step = "neutral"
    if played_zone == "B":
        flags.append("near_best")

    # Pass: соперник ошибся (G ≥ T_pass), а шанс не использован (D/G < 0,3).
    if c0 is not None:
        gift = c1 > c0 or v.g >= p.pass_step
        if gift and v.d / v.g < s.pass_ratio:
            flags.append("pass")
            # пропуск значимой идеи — pass, а не неточность (6.3); и не
            # ошибка, если своя позиция не стала хуже, чем до подарка соперника
            if step in ("inaccuracy", "neutral") or (step in ("laxity", "mistake") and v.d >= -p.lax_threshold):
                step = "pass"

    if played_zone in ("A", "B") and abs(v.g) <= p.neutral_eps:
        flags.append("neutral")

    # Only move: единственный ход, улучшающий позицию — поднимает оценку над E0
    # (до ошибки соперника) хотя бы на значимое G; все остальные — нет.
    # Удержание: единственный ход, сохраняющий категорию лучшей линии, —
    # все остальные её роняют (остальное — ошибки или зевки).
    only_move = False
    if e0 is not None and len(zone_a) == 1 and n_legal > 1:
        improving = [ln for ln in lines if ln.eval.value(unit, s) - v.e0 >= p.g_significant]
        only_move = len(improving) == 1 and improving[0] is zone_a[0]
    if not only_move and len(zone_a) == 1 and len(lines) >= 2 and n_legal > 1:
        only_move = all(category(ln.eval.value(unit, s), p) < c1 for ln in lines if ln is not zone_a[0])

    return _UnitVerdict(unit, step, flags, zone_a, zone_b, played_zone, only_move, c0, c1, cp)


def _keeps_extreme(e1: Eval, lines: list[Line], unit: str, s: Settings, share: float) -> bool:
    p = s.pawns if unit == "pawns" else s.wdl
    c1 = category(e1.value(unit, s), p)
    if c1 not in (WIN, LOSS) or not lines:
        return False
    keep = sum(category(ln.eval.value(unit, s), p) == c1 for ln in lines)
    return keep / len(lines) >= share - _TOL


def trivial_candidate(lines: list[Line], n_legal: int, s: Settings) -> bool:
    """Все линии MultiPV в той же крайней категории, что и лучшая: стоит проверить все ходы."""
    units = ("pawns", "wdl") if s.unit == "both" else (s.class_unit,)
    return len(lines) >= min(s.multipv, n_legal) \
        and all(_keeps_extreme(lines[0].eval, lines, u, s, 1.0) for u in units)


def _is_trivial(e1: Eval, lines: list[Line], all_lines: list[Line] | None, n_legal: int,
                unit: str, s: Settings) -> bool:
    """Почти все легальные ходы сохраняют крайнюю категорию (8.2, шаг 10).

    Если оценены все ходы (all_lines, малая глубина), нужна доля trivial_share;
    иначе — приближение по MultiPV: все линии в той же категории."""
    if all_lines is not None and len(all_lines) >= n_legal:
        return _keeps_extreme(e1, all_lines, unit, s, s.trivial_share)
    return len(lines) >= min(s.multipv, n_legal) and _keeps_extreme(e1, lines, unit, s, 1.0)


def move_type(board: chess.Board, line: Line, lines: list[Line], s: Settings) -> tuple[str, list[str]]:
    """Tactical: в PV хода не меньше tactical_min_forcing форсированных полуходов
    в первых tactical_window_plies, и результат от них зависит — оценка линии
    заметно (на g_significant) отличается от лучшей тихой альтернативы или тихих
    альтернатив среди MultiPV нет.

    Остальные ходы — positional. Второй элемент — направления хода
    (features.positional_subtypes): attacking, counterattacking, defensive;
    их можно совмещать с любой основой (tactical + attacking, positional +
    defensive, defensive вместе с attacking или counterattacking)."""
    move = chess.Move.from_uci(line.move)
    tactical = False
    if features.forcing_count(board, line.pv, s.tactical_window_plies) >= s.tactical_min_forcing:
        quiet = [ln for ln in lines if ln.move != line.move
                 and not features.is_forcing(board, chess.Move.from_uci(ln.move))]
        if not quiet:
            tactical = True
        else:
            best_quiet = quiet[0].eval
            tactical = line.eval.mate is not None or best_quiet.mate is not None \
                or abs(line.eval.pawns(s) - best_quiet.pawns(s)) >= s.pawns.g_significant \
                or abs(line.eval.expected - best_quiet.expected) >= s.wdl.g_significant
    sub = features.positional_subtypes(board, move, s)
    names = {"attack": "attacking", "counterattack": "counterattacking", "defense": "defensive"}
    return ("tactical" if tactical else "positional"), [names[x] for x in sub if x in names]


def _is_brilliant(board: chess.Board, line: Line, s: Settings, continuation: list[str] | None = None) -> bool:
    """Работающая жертва: ход оставляет фигуру под боем, материал не возвращается
    первые ответы соперника, а позиция после хода не хуже равной.

    Материал проверяется по главному варианту и, для сыгранного хода, по самой
    партии (continuation — следующие ходы): движок часто показывает, что жертву
    лучше не брать (24.Лxd4!! Каспаров — Топалов, 24...Крb6), а принятие видно
    только из партии."""
    move = chess.Move.from_uci(line.move)
    if line.eval.value("pawns", s) <= -s.pawns.b1:
        return False
    if not features.leaves_material_en_prise(board, move):
        return False
    if features.is_sacrifice_line(board, line.pv, s):
        return True
    return bool(continuation) and features.is_sacrifice_line(board, [line.move, *continuation], s)


def classify(
    board: chess.Board,
    lines: list[Line],
    played: Line,
    prev_root: Eval | None,
    s: Settings,
    ply: int = 0,
    all_lines: list[Line] | None = None,
    opening: str | None = None,
    continuation: list[str] | None = None,
) -> MoveRecord:
    """prev_root — корневая оценка предыдущего полухода с точки зрения соперника
    (его E1). None для первого хода стороны: тогда E0 = E1 и G = 0.
    all_lines — все легальные ходы на малой глубине (для «тривиальной позиции»)."""
    move = chess.Move.from_uci(played.move)
    n_legal = board.legal_moves.count()

    e1 = lines[0].eval
    ep = played.eval
    e0 = previous_after_move_to_root(prev_root.negate()) if prev_root is not None else None
    base = e0 if e0 is not None else e1

    units = ("pawns", "wdl") if s.unit == "both" else (s.class_unit,)
    verdicts = {u: _verdict(u, e0, e1, ep, lines, played, n_legal, s) for u in units}
    # Более строгий вердикт; при равенстве — WDL (основная единица категорий).
    chosen = max(verdicts.values(), key=lambda vd: (STEPS.index(vd.step), vd.unit == "wdl"))

    # Зоны при "both" — пересечение: лучший ход должен быть лучшим в обеих единицах.
    # Иначе в решённой позиции насыщенный WDL объявлял бы «лучшими» десяток ходов.
    def zone(move: str) -> str | None:
        rank = {"A": 0, "B": 1, None: 2}
        worst = None
        for vd in verdicts.values():
            z = "A" if any(l.move == move for l in vd.zone_a) else \
                "B" if any(l.move == move for l in vd.zone_b) else None
            if worst is None or rank[z] > rank[worst[0]]:
                worst = (z,)
        return worst[0]

    zone_a = [ln for ln in lines if zone(ln.move) == "A"]
    zone_b = [ln for ln in lines if zone(ln.move) == "B"]
    played_zone = zone(played.move)
    only_move = all(vd.only_move for vd in verdicts.values()) and len(zone_a) == 1

    flags = list(chosen.flags)
    if all(_is_trivial(e1, lines, all_lines, n_legal, u, s) for u in units):
        flags.append("trivial")
    if ply < s.theory_plies:
        flags.append("theory")

    # В безнадёжной позиции (проигрыш, почти все ходы проигрывают) переход к
    # форсированному мату — не зевок: игрок лишь ускоряет неизбежное.
    step = chosen.step
    if step == "blunder" and "trivial" in flags and chosen.c1 == LOSS and chosen.cp == LOSS:
        step = "laxity"
        flags.append("hopeless")

    # Единственный легальный ход — отдельная ступень: ни качества, ни упущенных
    # возможностей у него нет, в статистику, викторину и пропуски идей он не идёт.
    forced = n_legal == 1
    if forced:
        step = FORCED
        flags = [f for f in flags if f in ("trivial", "theory")]

    # Ход по книге: теория, а не оценка движка (гамбиты в начале — не неточности).
    engine_step = None
    if opening is not None:
        engine_step, step = step, BOOK
        flags = ["book"]

    subtype: str | None = None
    best_type, _ = move_type(board, lines[0], lines, s)
    if chosen.step == "inaccuracy" and best_type == "tactical" \
            and features.is_forcing(board, chess.Move.from_uci(lines[0].move)) \
            and not features.is_forcing(board, move):
        subtype = "underpress"  # недожим: лучший ход продолжал форсированную линию
    if played_zone == "A" and not forced and opening is None:
        if _is_brilliant(board, played, s, continuation):
            subtype = "brilliant"
        elif only_move:
            # тактический only: за ходом длинная форсировка (больше трёх
            # форсирующих полуходов); иначе — лёгкий, очевидный (размен
            # обратно, единственный отход)
            # взятие крупной фигуры с выигрышем материала очевидно — лёгкий only
            deep = features.forcing_count(board, played.pv, s.only_window_plies) > s.only_min_forcing \
                and not features.obvious_capture(board, move)
            subtype = "only_move" if deep else "only_light"

    mtype, msub = move_type(board, played, lines, s)

    def describe(ln: Line) -> dict:
        t, sub = move_type(board, ln, lines, s)
        return {
            "uci": ln.move,
            "san": board.san(chess.Move.from_uci(ln.move)),
            "eval": str(ln.eval),
            "type": t,
            "subtypes": sub,
            "only_move": only_move and ln is zone_a[0],
            "brilliant": _is_brilliant(board, ln, s),
        }

    return MoveRecord(
        ply=ply,
        side="white" if board.turn == chess.WHITE else "black",
        san=board.san(move),
        uci=played.move,
        fen_before=board.fen(),
        e0=e0, e1=e1, ep=ep,
        pawns=Values(base.pawns(s), e1.pawns(s), ep.pawns(s)),
        wdl=Values(base.expected, e1.expected, ep.expected),
        cat_e0=CATEGORIES[chosen.c0] if chosen.c0 is not None else None,
        cat_e1=CATEGORIES[chosen.c1],
        cat_ep=CATEGORIES[chosen.cp],
        step=step,
        subtype=subtype,
        move_type=mtype,
        type_subtypes=msub,
        flags=flags,
        best_moves=[describe(ln) for ln in zone_a],
        near_best_moves=[describe(ln) for ln in zone_b],
        stage=features.stage(board, s),
        decided_by=chosen.unit,
        unit_steps={u: (FORCED if forced else vd.step) for u, vd in verdicts.items()},
        opening=opening,
        engine_step=engine_step,
    )
