# ChessAnalyst

Chess game analysis that looks for where a mistake began. A unique system for selecting chunks — the positions that matter — finds the right puzzles and closes the gaps in your game. Android and web, with Stockfish running on the device.

## Download

- [ChessAnalyst-1.3.5.apk](https://github.com/MrKakaKat/ChessAnalyst/releases/download/v1.3.5/ChessAnalyst-1.3.5.apk) (arm64-v8a)
- [ChessAnalyst-1.3.5-web.zip](https://github.com/MrKakaKat/ChessAnalyst/releases/download/v1.3.5/ChessAnalyst-1.3.5-web.zip)

> Install only from this repository's Releases. The signing key is public (so anyone can build the app themselves), which means an APK from anywhere else could be a modified copy that still installs over yours. 

Unzip the web version and serve the folder over HTTP, for example `python3 -m http.server`. Needs a browser with WebAssembly GC: Chrome or Edge 119+, Firefox 120+, Safari 18.2+.

The app tells you when a new version is out. All versions: [Releases](https://github.com/MrKakaKat/ChessAnalyst/releases).

## What it does

- **Game analysis.** Import a PGN and analyse it with Stockfish on the device, in the background, several games in a queue. Each move gets a grade from best to blunder, including brilliant.
- **Kinds of moves.** The analysis names what a move does: fork, pin, overloaded piece, exchange offer, retreat, pawn break and more. For a mistake it shows what the player missed and how it was punished.
- **Ideas.** An idea traces a mistake back to where it began. It plays the punishment and the missed line until the forced play ends.
- **Evaluation in three ways.** Pawns, WDL and AAC (abilities, activity, complication). Graphs of position character, sharpness and difficulty.
- **Puzzles.** Puzzles come from the analysed games and get an engine rating. They are chosen by your weaknesses, and the target rating can be set automatically.
- **Working on mistakes.** In *Start to improve* you find a better move, hold the position against the engine, or foresee the plan.
- **Statistics.** A weakness profile for your own games (several names supported), and a list of positions you missed or did not understand.

The full description of every mark is in the [analysis guide](docs/analysis_guide.md); the same guide is in the app.

For developers: [DEVELOPERS.md](DEVELOPERS.md).
