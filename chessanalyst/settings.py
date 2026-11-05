"""Настройки порогов и анализа (разделы 6.1, 6.7, 7, 8.2 концепции).

Все числа здесь — стартовые значения, их подбирают по реальным прогонам.
Версия настроек (хэш) записывается в каждую запись хода.
"""

from __future__ import annotations

import hashlib
import json
import tomllib
from dataclasses import asdict, dataclass, field, replace
from pathlib import Path

# Пять категорий позиции с точки зрения ходящего, от худшей к лучшей.
CATEGORIES = ("loss", "worse", "equal", "better", "win")
LOSS, WORSE, EQUAL, BETTER, WIN = range(5)

UNITS = ("pawns", "wdl", "both")


@dataclass(frozen=True)
class UnitParams:
    """Пороги в одной единице измерения (пешки или ожидаемый результат WDL)."""

    center: float          # оценка «ровно»
    b1: float              # граница равно/лучше (симметрично вниз)
    b2: float              # граница лучше/выигрыш
    eps1: float            # зона A «лучший»
    eps2: float            # зона B «практически равен лучшему»
    g_significant: float   # G считается значимым
    lax_threshold: float   # D заметно ниже нуля (laxity) / D около нуля (неточность)
    neutral_eps: float     # G около нуля (флаг «нейтральный»)
    pass_step: float       # T_pass как шаг, если категория не сменилась
    inaccuracy_loss: float = 0.1  # потеря L больше — неточность (до — нейтральный ход)
    laxity_loss: float = 0.5      # больше — слабость (laxity)
    mistake_loss: float = 1.0     # больше — ошибка


PAWNS = UnitParams(
    center=0.0, b1=0.7, b2=2.0,
    eps1=0.01, eps2=0.05,
    g_significant=0.3, lax_threshold=0.2, neutral_eps=0.1,
    pass_step=1.0,
)

WDL = UnitParams(
    center=0.5, b1=0.10, b2=0.30,
    eps1=0.002, eps2=0.01,
    g_significant=0.05, lax_threshold=0.03, neutral_eps=0.02,
    pass_step=0.15, inaccuracy_loss=0.02, laxity_loss=0.06, mistake_loss=0.12,
)


# Поля вне версии настроек: не влияют на метки, или (depth) хранятся отдельным
# ключом записи — прогоны на глубинах 18 и 20 должны иметь одну версию порогов.
NON_LABEL_FIELDS = (
    "engine_path", "threads", "hash_mb", "time_per_position", "depth",
    "play_depth", "play_multipv", "play_deviation_rate", "play_max_loss_pawns",
    "human_temperature", "human_engine_path",
    "puzzle_base_seconds", "probe_size", "probe_offset_min", "probe_offset_max",
    "probe_history_min", "mastery_required",
)


@dataclass(frozen=True)
class Settings:
    # Единица классификации. "both" классифицирует по WDL, а пешки выводит рядом.
    unit: str = "both"

    # Движок (8.2, шаг 2)
    engine_path: str = "stockfish"
    depth: int = 18
    multipv: int = 5
    time_per_position: float | None = None  # сек, ограничитель бюджета; None — только глубина
    threads: int = 1
    hash_mb: int = 128

    # Нормализация (8.2, шаг 4)
    cp_clamp_pawns: float = 40.0  # обычная оценка обрезается до ±40 пешек
    mate_base_pawns: float = 100.0  # мат в n ходов = ±(100 − n), не ниже 50
    mate_floor_pawns: float = 50.0

    # Классификация (раздел 7)
    excellent_ratio: float = 0.7
    good_ratio: float = 0.3
    pass_ratio: float = 0.3

    # Brilliant (8.2, шаг 8): минимальная жертва в пешках
    brilliant_material: int = 2
    brilliant_hold_replies: int = 2   # столько ответов соперника материал не возвращается

    # Тип хода (8.2, шаг 7)
    tactical_window_plies: int = 4
    tactical_min_forcing: int = 2
    attack_threshold: int = 1
    only_window_plies: int = 8          # only move: окно форсировки
    only_min_forcing: int = 3           # больше стольких форсирующих полуходов — тактический only
    defense_threshold: int = 1          # атакованные незащищённые фигуры, которые ход защитил
    threats_removed_threshold: int = 1  # или число снятых угроз

    # Стадия (8.2, шаг 9)
    opening_max_move: int = 12
    opening_min_undeveloped: int = 3  # дебют, пока на месте не меньше стольких лёгких фигур
    endgame_material: int = 26        # сумма материала без королей и пешек

    # Расширение анализа (вопрос из раздела 13: хватит ли пяти линий)
    multipv_max: int = 10        # если все 5 линий в зоне B, поиск повторяется с 10
    trivial_depth: int = 8       # все легальные ходы на малой глубине
    trivial_share: float = 0.8   # «почти все» ходы сохраняют категорию

    # Теория: первые N полуходов получают флаг theory и не идут в статистику ошибок
    theory_plies: int = 0

    # Идейная цепочка (8.3)
    idea_window_plies: int = 10  # K: за сколько полуходов фигура достигает цели
    idea_scan_plies: int = 10    # где в PV наказания искать ключевое событие
    idea_min_gain: int = 2       # выигрыш материала, который считается наказанием

    # Не влияют на метки ходов (исключены из версии настроек) ↓
    # Свободная игра (9.3)
    play_depth: int = 12
    play_multipv: int = 8
    play_deviation_rate: float = 0.5   # доля ходов, где компьютер уходит с главной линии
    play_max_loss_pawns: float = 0.6   # насколько хуже лучшего может быть уход
    human_temperature: float = 0.0     # >0: ход выбирается softmax по оценкам (имитация человека)
    human_engine_path: str = ""        # lc0 с весами Maia, если есть (ход по nodes=1)

    # Задачи и проба (5, 9.4)
    puzzle_base_seconds: float = 40.0  # ожидаемое время на задачу своего рейтинга
    probe_size: int = 3
    probe_offset_min: int = 300
    probe_offset_max: int = 400
    probe_history_min: int = 10        # после стольких проб показывается сравнение

    # Освоение (10)
    mastery_required: int = 5

    pawns: UnitParams = field(default=PAWNS)
    wdl: UnitParams = field(default=WDL)

    def __post_init__(self) -> None:
        if self.unit not in UNITS:
            raise ValueError(f"unit must be one of {UNITS}, got {self.unit!r}")

    @property
    def class_unit(self) -> str:
        """Единица, в которой считаются категории и пороги."""
        return "pawns" if self.unit == "pawns" else "wdl"

    @property
    def params(self) -> UnitParams:
        return self.pawns if self.class_unit == "pawns" else self.wdl

    def classification_dict(self) -> dict:
        """Параметры, влияющие на метки (без пути к движку и потоков)."""
        d = asdict(self)
        for k in NON_LABEL_FIELDS:
            d.pop(k)
        return d

    @property
    def version(self) -> str:
        raw = json.dumps(self.classification_dict(), sort_keys=True).encode()
        return hashlib.sha1(raw).hexdigest()[:10]

    def with_overrides(self, **kw) -> "Settings":
        kw = {k: v for k, v in kw.items() if v is not None}
        return replace(self, **kw)


def load_settings(path: str | Path | None = None) -> Settings:
    """Читает TOML: верхний уровень — поля Settings, секции [pawns] и [wdl] — UnitParams."""
    if path is None:
        return Settings()
    data = tomllib.loads(Path(path).read_text(encoding="utf-8"))
    pawns = replace(PAWNS, **data.pop("pawns", {}))
    wdl = replace(WDL, **data.pop("wdl", {}))
    return Settings(pawns=pawns, wdl=wdl, **data)
