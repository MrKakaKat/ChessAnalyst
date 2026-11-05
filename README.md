# ChessAnalyst

Chess game analysis that looks for where a mistake began, not only where the
evaluation dropped. Android and web, with Stockfish running on the device.

## Download

- **Android:** [ChessAnalyst-arm64-v8a.apk](https://github.com/MrKakaKat/ChessAnalyst/releases/latest/download/ChessAnalyst-arm64-v8a.apk) (arm64-v8a)
- **Web:** [ChessAnalyst-web.zip](https://github.com/MrKakaKat/ChessAnalyst/releases/latest/download/ChessAnalyst-web.zip). Unzip it and serve the folder over HTTP, for example `python3 -m http.server`. Needs a browser with WebAssembly GC: Chrome or Edge 119+, Firefox 120+, Safari 18.2+.

All versions: [Releases](https://github.com/MrKakaKat/ChessAnalyst/releases).

## What it does

- **Game analysis.** Import a PGN and analyse it with Stockfish on the device, in the background, several games in a queue.
- **Move grades.** Each move gets a grade from best to blunder, plus brilliant and only move. You can switch to grades in percent of the expected result.
- **Kinds of moves.** The analysis names what a move does: fork, pin, overloaded piece, exchange offer, retreat, pawn break and more. For a mistake it shows what the player missed and how it was punished.
- **Ideas.** An idea traces a mistake back to where it began. It plays the missed line and the punishment until the forced play ends.
- **Evaluation in three ways.**
  - Pawns, WDL and AAC (abilities, activity, complication).
  - Graphs of position character, sharpness and difficulty.
- **Your own branches.** Play moves on the board and the engine judges them. Copy moves or a whole game as PGN.
- **Puzzles.** Puzzles come from the analysed games and get an engine rating. They are chosen by your weaknesses, and the target rating can be set automatically.
- **Working on mistakes.** In *Start to improve* you find a better move, hold the position against the engine, or foresee the plan.
- **Statistics.** A weakness profile for your own games (several names supported), and a list of positions you missed or did not understand.
- **Showcase games.** Masters, AlphaZero against Stockfish 8, and engine games.

The full description of every mark is in the [analysis guide](docs/analysis_guide.md); the same guide is in the app.

## Repository

- `app/` — the Flutter app (Dart).
- `chessanalyst/` — the reference analysis in Python. The Dart analysis is checked against it move by move.
- `tools/`
  - `export_flutter_fixture.py` — engine data for the showcase games;
  - `refresh_fixtures.py` — reference labels;
  - `engine_game.py` — engine games;
  - `app_icon.py` — the app icon.
- `examples/` — source PGNs, including a test game outside the app.

Run the tests:

```
cd app && flutter test
pip install -e ".[dev]" && pytest -q
```

A release is built by pushing a version tag (`v1.0`, `v1.1`, …).
