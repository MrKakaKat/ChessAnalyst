# ChessAnalyst for developers

## Repository

- `app/` — the Flutter app (Dart): `lib/analysis/` is the analysis core, `lib/engine/` runs Stockfish on the device, `lib/ui/` is the interface.
- `chessanalyst/` — the reference analysis in Python. The Dart analysis is checked against it move by move.
- `tools/`
  - `export_flutter_fixture.py` — engine data for a showcase game, plus its Python reference labels;
  - `refresh_fixtures.py` — rewrites the reference labels from the stored engine data, no engine needed;
  - `engine_game.py` — plays a Stockfish game from an opening;
  - `app_icon.py` — draws the app icon.
- `examples/` — source PGNs of the showcase games, and `examples/user/` — a test game kept outside the app.
- `docs/analysis_guide.md` — the guide shown in the app (a copy lives in `app/assets/docs/`; a test keeps them equal).

## How the analysis works

1. **Engine data.**
   - Each position is analysed by Stockfish: MultiPV lines, the played move's line, and all legal moves at a small depth.
   - On the device, this runs in `AnalysisJob`, a quick pass first and then the chosen depth.
   - For the showcase games it is done once with `export_flutter_fixture.py` (depth 18, ten lines) and stored in `app/assets/games/`.
2. **Classification.** Every time a game is opened, it is rebuilt from the stored engine data:
   - grades, move types and kinds, ideas;
   - character, AAC.

   Changing the rules therefore changes every game at once.
3. **Port check.** `app/test/analysis_port_test.dart` compares the Dart labels and ideas with the Python ones (`app/test/fixtures/`) for every game and unit.

   After changing a rule:
   - in Python: change `chessanalyst/`, then run `python3 tools/refresh_fixtures.py`;
   - in Dart: make the same change until the test passes.

   Dart-only parts (kinds of moves, character, AAC, weaknesses) have their own tests.

## Versions of the analysis rules

`analysisRules` in `app/lib/analysis/settings.dart` is the version of the rules. Raise it when an update changes how games are judged. Analyses made with an older version are then marked "Re-analyse" in the history, and a notice explains the update once.

The statistics keep a snapshot of each analysis's mistake traits, so kinds of moves dropped by a later version are still counted.

## Tests

```
cd app && flutter test
pip install -e ".[dev]" && pytest -q   # needs stockfish on PATH
```

## Releases

- **Push to `main`.** Only the tests run.
- **Release.** Run the *Flutter* workflow by hand with a version number (Actions → Flutter → Run workflow → `1.3`), or push a tag `v1.3`. CI builds:
  - `ChessAnalyst-arm64-v8a.apk` — arm64-v8a only;
  - `ChessAnalyst-web.zip` — WebAssembly.

  It publishes both in a release with that tag.
- **APK build number.** It is `1000 + run number`, so a new APK installs over an older one.
- **Signing key.** Updates require the same key: `app/android/app/prototype.keystore`.

The app's Android id stays `dev.chessideas.chess_ideas_app`.
