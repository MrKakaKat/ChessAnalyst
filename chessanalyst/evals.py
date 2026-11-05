"""Оценки позиции и их нормализация (8.2, шаг 4).

Все оценки хранятся с точки зрения игрока, чей ход разбирается, и приводятся
к одной «рамке» — позиции, где этот игрок на ходу (E1). Это важно для матов:
движок считает мат в ходах от текущей позиции, поэтому оценка после хода
(соперник на ходу) и оценка до хода отличаются на один ход при той же линии.
"""

from __future__ import annotations

from dataclasses import dataclass

from .settings import CATEGORIES, Settings, UnitParams


@dataclass(frozen=True)
class Eval:
    """Оценка с точки зрения игрока.

    cp   — сантипешки (None, если мат);
    mate — число ходов до мата: > 0 игрок матует, < 0 игрока матуют;
    wdl  — (win, draw, loss) в промилле.
    """

    cp: int | None
    mate: int | None
    wdl: tuple[int, int, int]

    def __post_init__(self) -> None:
        if (self.cp is None) == (self.mate is None):
            raise ValueError("exactly one of cp / mate must be set")
        if self.mate == 0:
            raise ValueError("mate distance 0 is ambiguous; use ±1 after projection")

    # --- представление ---

    def negate(self) -> "Eval":
        w, d, l = self.wdl
        return Eval(
            cp=None if self.cp is None else -self.cp,
            mate=None if self.mate is None else -self.mate,
            wdl=(l, d, w),
        )

    def pawns(self, s: Settings) -> float:
        if self.mate is not None:
            v = max(s.mate_base_pawns - abs(self.mate), s.mate_floor_pawns)
            return v if self.mate > 0 else -v
        return max(-s.cp_clamp_pawns, min(s.cp_clamp_pawns, self.cp / 100.0))

    @property
    def expected(self) -> float:
        """Ожидаемый результат W + D/2, от 0 до 1."""
        w, d, _ = self.wdl
        return (w + d / 2) / 1000.0

    def value(self, unit: str, s: Settings) -> float:
        return self.pawns(s) if unit == "pawns" else self.expected

    def structurally_equal(self, other: "Eval") -> bool:
        """Одинаковая оценка и WDL, либо мат за одинаковое число ходов (6.7)."""
        if self.mate is not None or other.mate is not None:
            return self.mate == other.mate
        return self.cp == other.cp and self.wdl == other.wdl

    def to_json(self) -> dict:
        return {"cp": self.cp, "mate": self.mate, "wdl": list(self.wdl)}

    @classmethod
    def from_json(cls, d: dict) -> "Eval":
        return cls(cp=d["cp"], mate=d["mate"], wdl=tuple(d["wdl"]))

    def __str__(self) -> str:
        if self.mate is not None:
            return f"#{self.mate}"
        return f"{self.cp / 100:+.2f}"


# Терминальные позиции, для которых движок не даёт WDL.
DRAW = Eval(cp=0, mate=None, wdl=(0, 1000, 0))


def after_move_to_root(e: Eval) -> Eval:
    """Оценку после своего хода (соперник на ходу) переводит в рамку «до хода».

    Если игрок матует, его ход уже потрачен: мат в n после хода — это мат
    в n+1 до него. Если матуют игрока, счёт идёт ходами соперника и не меняется.
    """
    if e.mate is not None and e.mate > 0:
        return Eval(cp=None, mate=e.mate + 1, wdl=e.wdl)
    return e


def previous_after_move_to_root(e: Eval) -> Eval:
    """Оценку после прошлого своего хода (E0) переводит в рамку следующего хода.

    Между ними ходит соперник: если он матует, до мата становится на ход меньше.
    """
    if e.mate is not None and e.mate < -1:
        return Eval(cp=None, mate=e.mate + 1, wdl=e.wdl)
    return e


def category(value: float, p: UnitParams) -> int:
    """Индекс в CATEGORIES (0 — проигрыш, 4 — выигрыш)."""
    d = value - p.center
    if d >= p.b2:
        return 4
    if d >= p.b1:
        return 3
    if d < -p.b2:
        return 0
    if d < -p.b1:
        return 1
    return 2


def category_name(value: float, p: UnitParams) -> str:
    return CATEGORIES[category(value, p)]
