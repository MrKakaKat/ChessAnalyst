"""SQLite-хранилище (этап 0: формат хранения, раздел 8.4).

Разделение на три слоя:
  games / plies   — сырые партии и позиции (FEN до каждого хода);
  engine_cache    — результаты движка по позиции и глубине, переиспользуются
                    между партиями и прогонами;
  move_records    — метки хода для конкретной версии настроек. Переклассификация
                    с новыми порогами не требует движка.
"""

from __future__ import annotations

import json
import sqlite3
from pathlib import Path

SCHEMA_VERSION = 1

SCHEMA = """
CREATE TABLE IF NOT EXISTS meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS games (
    id         INTEGER PRIMARY KEY,
    event      TEXT, site TEXT, date TEXT, round TEXT,
    white      TEXT, black TEXT, result TEXT,
    start_fen  TEXT NOT NULL,
    pgn        TEXT NOT NULL,
    pgn_hash   TEXT NOT NULL UNIQUE,
    added_at   TEXT NOT NULL DEFAULT (datetime('now')),
    status     TEXT NOT NULL DEFAULT 'queued'   -- queued | analyzed | classified
);

CREATE TABLE IF NOT EXISTS plies (
    game_id    INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    ply        INTEGER NOT NULL,          -- 0 — первый ход партии
    side       TEXT NOT NULL,             -- white | black
    move_no    INTEGER NOT NULL,          -- номер хода в нотации
    san        TEXT NOT NULL,
    uci        TEXT NOT NULL,
    fen_before TEXT NOT NULL,
    PRIMARY KEY (game_id, ply)
);

-- Кэш движка: ключ — позиция без счётчиков ходов (EPD) и глубина.
CREATE TABLE IF NOT EXISTS engine_cache (
    epd        TEXT NOT NULL,
    depth      INTEGER NOT NULL,
    multipv    INTEGER NOT NULL,
    engine     TEXT NOT NULL,
    lines      TEXT NOT NULL,             -- JSON: [{move, eval, pv}]
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (epd, depth)
);

-- Оценка сыгранного хода, если его не было среди MultiPV.
CREATE TABLE IF NOT EXISTS played_cache (
    epd        TEXT NOT NULL,
    depth      INTEGER NOT NULL,
    move       TEXT NOT NULL,
    engine     TEXT NOT NULL,
    eval       TEXT NOT NULL,             -- JSON Eval, рамка «до хода»
    pv         TEXT NOT NULL,             -- JSON [uci], начиная с самого хода
    PRIMARY KEY (epd, depth, move)
);

CREATE TABLE IF NOT EXISTS move_records (
    game_id          INTEGER NOT NULL,
    ply              INTEGER NOT NULL,
    settings_version TEXT NOT NULL,
    depth            INTEGER NOT NULL,
    unit             TEXT NOT NULL,
    side             TEXT NOT NULL,
    san              TEXT NOT NULL,
    uci              TEXT NOT NULL,
    fen_before       TEXT NOT NULL,
    -- исходные оценки (JSON Eval) и производные в обеих единицах
    e0 TEXT, e1 TEXT NOT NULL, ep TEXT NOT NULL,
    e0_pawns REAL, e1_pawns REAL, ep_pawns REAL,
    g_pawns REAL, d_pawns REAL, l_pawns REAL,
    e0_wdl REAL, e1_wdl REAL, ep_wdl REAL,
    g_wdl REAL, d_wdl REAL, l_wdl REAL,
    cat_e0 TEXT, cat_e1 TEXT NOT NULL, cat_ep TEXT NOT NULL,
    step             TEXT NOT NULL,       -- ступень шкалы (6.2)
    decided_by       TEXT NOT NULL,       -- единица, давшая вердикт (pawns | wdl)
    unit_steps       TEXT NOT NULL,       -- JSON {pawns: step, wdl: step}
    subtype          TEXT,                -- only_move | only_light | brilliant | underpress
    move_type        TEXT NOT NULL,       -- tactical | attacking | defensive | positional
    type_subtypes    TEXT NOT NULL,       -- JSON: доп. тип ([defensive] при attacking)
    flags            TEXT NOT NULL,       -- JSON [pass, neutral, near_best, ...]
    best_moves       TEXT NOT NULL,       -- JSON зона A
    near_best_moves  TEXT NOT NULL,       -- JSON зона B
    stage            TEXT NOT NULL,
    opening          TEXT,                -- название дебюта, если ход по книге
    engine_step      TEXT,                -- вердикт движка, заменённый на book
    -- идейный слой (этап 3), пока пусто
    idea_signature   TEXT,
    idea_start_ply   INTEGER,
    miss_ply         INTEGER,
    distance         INTEGER,
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (game_id, ply, settings_version, depth)
);

-- Идейные цепочки (8.3). Одна строка связывает обе стороны: владелец идеи и жертва.
CREATE TABLE IF NOT EXISTS ideas (
    id               INTEGER PRIMARY KEY,
    game_id          INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
    settings_version TEXT NOT NULL,
    depth            INTEGER NOT NULL,
    kind             TEXT NOT NULL,       -- punishment | pass
    punish_ply       INTEGER NOT NULL,
    owner            TEXT NOT NULL,
    victim           TEXT NOT NULL,
    signature        TEXT NOT NULL,       -- JSON
    start_ply        INTEGER NOT NULL,
    miss_ply         INTEGER,
    distance         INTEGER,
    chain            TEXT NOT NULL,       -- JSON [{ply, present, attacker, target}]
    builder_plies    TEXT NOT NULL,       -- JSON: ходы владельца, строившие идею
    chunk            TEXT NOT NULL        -- запись активного чанка
);

-- Пользовательские настройки: рейтинг, имя на chess.com (для «моих» ходов).
CREATE TABLE IF NOT EXISTS prefs (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

-- Параллельные партии (9.6): где остановился в каждой.
CREATE TABLE IF NOT EXISTS game_state (
    game_id    INTEGER PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
    cursor_ply INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- «Покажи своё продолжение» (9.2)
CREATE TABLE IF NOT EXISTS continuations (
    id            INTEGER PRIMARY KEY,
    source        TEXT NOT NULL,          -- game | play
    ref           TEXT,                   -- game_id:ply или play_session_id
    fen           TEXT NOT NULL,          -- позиция после своего хода
    user_line     TEXT NOT NULL,          -- JSON [uci]
    engine_line   TEXT NOT NULL,          -- JSON [uci]
    diverge_index INTEGER,                -- NULL — совпало целиком
    diverge_side  TEXT,                   -- opponent | self
    diverge_kind  TEXT,                   -- capture | check | defense | quiet | match
    user_move     TEXT,
    engine_move   TEXT,
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Свободная игра против компьютера (9.3)
CREATE TABLE IF NOT EXISTS play_sessions (
    id          INTEGER PRIMARY KEY,
    start_fen   TEXT NOT NULL,
    human_color TEXT NOT NULL,
    moves       TEXT NOT NULL DEFAULT '[]',   -- JSON [{uci, san, by, step, deviated}]
    status      TEXT NOT NULL DEFAULT 'active',
    source      TEXT,
    created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Библиотека идей (9.5)
CREATE TABLE IF NOT EXISTS library (
    id         INTEGER PRIMARY KEY,
    title      TEXT NOT NULL,
    fen        TEXT NOT NULL,
    key_line   TEXT NOT NULL,             -- JSON [uci]
    game_id    INTEGER REFERENCES games(id) ON DELETE SET NULL,
    ply        INTEGER,
    signature  TEXT,
    chunk      TEXT,
    stage      TEXT,
    note       TEXT,
    locus      TEXT,                      -- место во «дворце памяти»
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS library_reviews (
    id           INTEGER PRIMARY KEY,
    library_id   INTEGER NOT NULL REFERENCES library(id) ON DELETE CASCADE,
    line_score   REAL NOT NULL,           -- доля верных ходов ключевой линии
    recall_score REAL,                    -- точность воспроизведения позиции
    given        TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Освоение: определение метки хода без подсказки (10)
CREATE TABLE IF NOT EXISTS quiz_attempts (
    id               INTEGER PRIMARY KEY,
    game_id          INTEGER NOT NULL,
    ply              INTEGER NOT NULL,
    settings_version TEXT NOT NULL,
    answer           TEXT NOT NULL,
    truth            TEXT NOT NULL,
    correct          INTEGER NOT NULL,
    created_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Награды за процесс; ничего не сгорает (10)
CREATE TABLE IF NOT EXISTS events (
    id         INTEGER PRIMARY KEY,
    kind       TEXT NOT NULL,
    points     INTEGER NOT NULL,
    ref        TEXT,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- День = сюжет, итог дня = одна главная находка (10)
CREATE TABLE IF NOT EXISTS stories (
    day        TEXT PRIMARY KEY,          -- YYYY-MM-DD
    game_id    INTEGER,
    idea_id    INTEGER,
    finding    TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Задачи Lichess (9.4)
CREATE TABLE IF NOT EXISTS puzzles (
    id         TEXT PRIMARY KEY,
    fen        TEXT NOT NULL,
    moves      TEXT NOT NULL,             -- uci через пробел; первый — ход соперника
    rating     INTEGER NOT NULL,
    rating_dev INTEGER,
    popularity INTEGER,
    nb_plays   INTEGER,
    themes     TEXT NOT NULL,             -- через пробел
    game_url   TEXT,
    opening    TEXT
);
CREATE INDEX IF NOT EXISTS puzzles_rating ON puzzles(rating);

CREATE TABLE IF NOT EXISTS probes (
    id          INTEGER PRIMARY KEY,
    started_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime')),
    hour        INTEGER NOT NULL,         -- время суток (поле «сон» сознательно не ведётся)
    puzzle_ids  TEXT NOT NULL,            -- JSON
    ease        INTEGER,                  -- субъективная лёгкость 1–5
    interest    INTEGER,                  -- желание играть 1–5
    mean_norm   REAL,
    finished    INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS puzzle_attempts (
    id          INTEGER PRIMARY KEY,
    puzzle_id   TEXT NOT NULL REFERENCES puzzles(id),
    probe_id    INTEGER REFERENCES probes(id),
    seconds     REAL NOT NULL,
    solved      INTEGER NOT NULL,
    player_rating INTEGER NOT NULL,
    normalized  REAL NOT NULL,            -- время / ожидаемое для рейтинга задачи
    difficulty  INTEGER,                  -- 1–5
    reasons     TEXT NOT NULL DEFAULT '[]',
    created_at  TEXT NOT NULL DEFAULT (datetime('now', 'localtime'))
);
"""


def connect(path: str | Path, check_same_thread: bool = True) -> sqlite3.Connection:
    conn = sqlite3.connect(str(path), check_same_thread=check_same_thread, timeout=30)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    conn.execute("PRAGMA journal_mode = WAL")  # фоновый анализ и интерфейс пишут одновременно
    conn.executescript(SCHEMA)
    _migrate(conn)
    conn.execute(
        "INSERT OR IGNORE INTO meta(key, value) VALUES ('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    conn.commit()
    return conn


def _migrate(conn: sqlite3.Connection) -> None:
    """Столбцы, добавленные после первой версии схемы."""
    cols = {r["name"] for r in conn.execute("PRAGMA table_info(move_records)")}
    for name in ("opening", "engine_step"):
        if name not in cols:
            conn.execute(f"ALTER TABLE move_records ADD COLUMN {name} TEXT")


def dumps(obj) -> str:
    return json.dumps(obj, ensure_ascii=False, separators=(",", ":"))


def get_pref(conn: sqlite3.Connection, key: str, default: str | None = None) -> str | None:
    row = conn.execute("SELECT value FROM prefs WHERE key = ?", (key,)).fetchone()
    return row["value"] if row else default


def set_pref(conn: sqlite3.Connection, key: str, value: str) -> None:
    conn.execute("INSERT OR REPLACE INTO prefs(key, value) VALUES (?, ?)", (key, value))
    conn.commit()


def award(conn: sqlite3.Connection, kind: str, points: int, ref: str | None = None) -> None:
    """Очки за процесс (10). Не сгорают и не зависят от результата партий."""
    conn.execute("INSERT INTO events(kind, points, ref) VALUES (?,?,?)", (kind, points, ref))
    conn.commit()
