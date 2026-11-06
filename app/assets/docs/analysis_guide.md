# Analysis guide

ChessAnalyst looks at a game the way a coach would. It does not only ask
how much the evaluation dropped. It also asks where the mistake began, what
the move was trying to do, and what the better move would have done. This
guide explains every mark you see.

Evaluations are always from the side to move. "Advantage" means +0.7 pawns
or more, "winning" means +2 or more, and "equal" is in between.

---

## Move grades

Each move is compared with the best move in the position. The loss is how
much the move gives away against the best one.

| Grade | When |
|---|---|
| Best | one of the best moves |
| Excellent | almost the best: keeps most of what the position offered, or a slower mate |
| Good | keeps a fair part of what the position offered |
| Neutral | the position barely changes (loss up to 0.1 pawn) |
| Inaccuracy | loss over 0.1 pawn |
| Laxity | loss over 0.5 pawn: a real weakness |
| Mistake | loss over 1 pawn |
| Blunder | a won position thrown away, a mate allowed, or a drop of two categories |
| Pass | the opponent offered a chance and it was missed, but the position is no worse than before |

**Steps in percent** (quick settings). Moves are graded by how much of the
expected result they lose instead: best up to 1%, excellent 1–2%, good
2–5%, inaccuracy 5–10%, laxity 10–15%, mistake 15–25%, blunder over 25%.
In a decided position the percent barely moves, so the stricter of this
grade and the grade by pawns lost (0.1 / 0.5 / 1) is taken; a lost win or
an allowed mate stays a blunder. A move is neutral only when it loses up to
1% and up to 0.1 pawn.

**Special marks**
- **Brilliant** — a best move that gives up material, and the material does
  not come back at once. A desperado piece (a rook giving check after check
  that cannot be taken without stalemate) is brilliant only on its first
  check, and only when the draw is certain; otherwise the first check is
  an only move. The checks after it are plain only moves.
- **Only move** — every other move spoils the position. There are two kinds:
  - **Only move** (blue, the sign jumps): a long forcing line follows,
    found only by calculation;
  - **Only move** (mint, a plain sign): the only move is obvious, such as taking back
    or taking a piece left hanging.
- **Book** — a known opening move.
- **Forced** — the only legal move.
- **Worst move** — the move of each side that cost the most. After it the
  game is usually lost.
- **Trick** (a white sign next to the move's sign; off by default, turn it
  on in the quick settings) — the position is lost, but after this move
  some of the opponent's moves let the game slip to a draw: stalemate,
  perpetual check or another drawing line. Tap it to see how many.

---

## Move types

A move has a base and one or two directions. Example: "Tactical · Attack +
Defence".

**Base**
- **Tactical** — the result depends on a forcing sequence of checks,
  captures and threats.
- **Positional** — no forcing sequence: the move improves pieces, pawns or
  squares.

**Direction**
- **Attack** — the move creates a new threat: a check, a piece left under
  attack, an extra attacker on a piece, or pressure on the king. A capture by
  itself is not an attack.
- **Defence** — the move removes a threat: it leaves a check, takes the
  danger away from another piece, or adds a defender to an attacked piece
  that had no more defenders than attackers. Moving the attacked piece
  itself away is a retreat, not a defence.
- **Counterattack** — the move answers a threat with a threat of its own,
  while the first threat is still there.

Attack and counterattack never go together: a counterattack already is an
attack, made in reply.

---

## Kinds of moves

The kind says what a move does. When a move goes wrong, the card shows the
kind of the best move that was **missed** and the stage of the game. For
example: "Missed: Exchange (Bxd5) in the middlegame". Most mistakes begin
with a good move that was not seen.

A mistake also has a second trait: what it was **punished by**. That is the
first sharp move (mate, fork, pin, sacrifice, tempo attack…) in the
opponent's best line after the mistake. It is not always the next move: the
punishment can come after a quiet preparation. Puzzles are chosen first by
what you missed, then by what you were punished with.

| Kind | What it is |
|---|---|
| Mate, Promotion | mates, or promotes a pawn |
| Fork | the piece attacks two valuable pieces at once |
| Discovered check | a piece steps away and opens a line of another piece onto the king |
| Discovered attack on the queen | the same, the opened line hits the queen |
| Discovered attack | the same, the opened line hits another piece |
| Escape from check | the answer to a check: taking the checking piece, a king move or a block |
| Pin | an enemy piece can no longer move without losing something behind it |
| Overloaded piece | an enemy piece is the only defender of two attacked pieces: taking one loses the other |
| Sacrifice | material given away for an attack or a position |
| Tempo attack | attacks a more valuable or undefended piece, gaining a move |
| Free material | takes a piece that no one defends |
| Retreat from attack | a piece that could be taken for free steps away to a safe square |
| Exchange | an equal trade of pieces |
| Barter | an unequal trade (e.g. two minor pieces for a rook) |
| Choice of trade | two or more trades are possible and only this one is right |
| Exchange offer | a quiet move that puts a piece face to face with an equal enemy piece, ready to trade |
| Barter offer | the same with an enemy piece of another value |
| Simplification | a trade while winning, towards an easy ending |
| Pawn break | a pawn moves into contact with enemy pawns |
| Undermining | a pawn attacks the base of an enemy pawn chain |
| Pawn push | any other pawn advance; in the opening and middlegame split into a centre push (files c–f) and a flank push |
| Development | a knight or bishop leaves its home square in the opening |
| King safety | castling |
| Open file | a rook or queen goes to a file without own pawns |
| Outpost | a knight to a square in enemy territory that no pawn can attack |
| Reroute | a piece starts a manoeuvre over several moves |
| Poisoned material | a capture that loses: taking was the mistake |
| Wrong piece | the right capture, made with the wrong piece |
| Missed again | the same best move was there on the player's previous move as well, and was missed both times |

**What a mistake cost** (shown for negative moves)
- **Loss** — *worse from equal*: an equal position became worse. If there was
  an advantage: *advantage reduced* (+1 or more is left), *advantage lost*
  (down to about equal, not below −0.5), *advantage given away* (the
  opponent is better now).
- **Irreversibility** — how much there was to lose: low in an equal
  position, medium with an advantage, high in a winning one.
- **Weight** — how hard the punishment was to see, 0–100. A piece simply
  left hanging is 0; a one-move tactic (fork, pin) 20; two moves 35, three
  50, four or five 60, six or more 70; a positional punishment 40. A quiet
  first move of the punishment and a single good reply for the opponent
  add 10 each. Harder and repeated misses weigh more in your weakness
  profile.
- **Intuitive** — how natural the best move is for a human, 0–100.
  Captures, recaptures and checks are easy to see; sacrifices, quiet moves
  in tactical positions, retreats and long forcing lines are not.
- **Underline: not clear to me why** — mark a mistake you did not
  understand. It counts double in your weakness profile, so puzzles like it
  come up more often.

---

## Character of a position

Shown under the move card. It describes the position the move was played
in.

**Trivial, middle or sharp: how many good continuations there are**

A move is *positive* when it keeps the category of the position (equal,
advantage, winning) and loses at most 0.3 pawns against the best move.
- **Sharp** — at most two positive moves. Every other move spoils the
  position.
- **Trivial** — the side to move has an advantage, and at least a tenth of
  all legal moves keep it. The advantage is easy to convert.
- **Middle** — in between. This is not marked.

**Quiet** — the best line has no checks, captures or direct threats for the
next two moves of each side, and there is more than one good move. Plans
matter more than calculation here.

---

## Evaluation: Pawns, WDL, AAC

- **Pawns** — the engine's evaluation in pawns.
- **WDL** — the chances to win, draw or lose, as an expected result.
- **AAC** — counterplay instead of the engine score. Each side gets three
  parts:
  - **Abilities**: its threats and the checks it can give. Only good checks
    count: ones that keep the position (by the engine) or at least do not
    lose the checking piece;
  - **Activity**: the free squares its pieces control;
  - **Complication**: how hard the position is for the opponent, that is how
    few good replies they have.

  The AAC graph compares both sides at every move. The move card shows the
  activity of both sides after the move. "More graphs" in the
  Game tab shows each part separately, together with the character of the
  positions along the game.

---

## Ideas

An idea is a chain of moves behind a tactic. It starts where the plan
began and ends with the move that wins material or mates.
- **Error**, **Miss** and **Punishment** mark the moves of the chain.
- A plain one-move blunder is not an idea. The "Serious tactics" filter
  hides such cases.
- **Why?** under a bad move opens its idea, or shows the opponent's best
  line after it, so you can see what the move allowed.
- **Play** runs the idea in order: the game up to the error, then how it
  was punished, then — after a quick rewind move by move to the position
  before the error — the line the player missed there. Each line goes
  on (with the engine on the device past the analysis) until the side to
  move has three positive moves (neutral ones count), or two positive moves
  and two inaccuracies close to neutral — where the calculation ends. Under the idea's title the card says which part is shown. Pause keeps the position; next
  and back move inside the idea; play goes on from where you are; the
  arrow button returns to the idea's start; a move of your own leaves the
  idea. The speed is in Settings. An idea also shows the earlier inaccuracy
  it began with.
- When a forced chain of only moves led to the error, the idea starts where
  that chain began ("Only move since"). The mistake was missing the only
  path, not just the last move.
- A **brilliant** move has its idea too: the chain shows from which move the
  chance was there, and playing the idea shows its consequences in the
  game.

---

## Working on mistakes

- **Step through mistakes** (Game tab) — the arrows jump only between
  negative moves. Their icons are shown next to the arrows.
- **Start to improve** (tap the title at the start of a game) — the
  mistakes of the game, from blunders to inaccuracies:
  - **Fix and survive**: find a positive move without hints. Then hold the
    position against the strongest engine with positive moves only, until it
    is quiet, clearly winning, or eight moves have been played.
  - **Foresight**: from the mistake's position, play the plan of both sides
    for four plies. It counts as understood when your ideas match the
    engine's line: the same kinds of moves, pieces and squares. The exact
    moves do not have to match.
  - Each position keeps its history: whether you solved it before, whether
    the last attempt was without an error, and for Foresight how accurate
    the last prediction was.
  - A positive move gets the dartboard, as in puzzles. After a fix, the
    branch icon next to the title shows why the game move was a mistake.
    "Show the consequences" plays the opponent's best line after your wrong
    move; the arrows under the board step through it.

---

## Statistics

The Statistics screen sums up your own analysed games:
- results and negative moves for each colour;
- mistakes by stage;
- the kinds of best moves you miss most;
- what the mistakes cost.

The **weakness profile** weighs these traits by how bad the mistakes were.
With **Consider weaknesses** on, puzzles that share them come first. For
each weak spot, the screen shows how many such puzzles you solved and how
hard they were: the more and the harder, the better the pattern is learnt.

Set your name with the badge button if the app does not find you in the
games.

---

## Game summary

- **Accuracy** — 0–100% for each side. It weighs how much each move lowered
  the expected result (lively stretches of the game count more, and one bad
  move pulls the result down), how often the engine's first choice was
  found, and serious mistakes in a row. Next to it: a rough playing
  strength for this one game, the share of best moves, and how many
  hard-to-see best moves (intuitiveness under 30) were found. Finding
  almost all of them is shown in red: unusual precision, though one game
  proves nothing.
- **Moves by kind** — how many best moves, inaccuracies, mistakes and so on
  each side made.
- **Difficulty** — how much the game demanded: tactics, the depth of the
  forcing lines, positions with a single good move, ideas, and length.
- **Sharpness** — how sharp the game was: a low chance of a draw, many sharp
  positions, many tactical attacks.

---

## Puzzles

Puzzles come from analysed games, your own included. A position becomes a
puzzle when one move stands out:
- a mate;
- a winning or advantage-gaining blow;
- the only defence that holds.

The solution goes on while the tactic does. In attacking puzzles any move
that keeps the goal counts as correct. In defensive puzzles only the one
saving line counts.

Puzzles do not overlap: when two puzzles share positions, the longer one
is kept.

The rating of a puzzle comes from the engine. It is computed when the
game's analysis ends, and again when the analysis is sent deeper. It
depends on how deep the engine must search before it keeps choosing the
solution, how many other moves look as good at a glance, whether the key
move is quiet, the length of the solution and a defensive goal. It also
counts the opponent's counter-chances: replies with check or capture that
nearly hold and have to be calculated, and how long the forcing play lasts. Puzzles
that were not rated yet (the showcase games) are rated in the background
while the Puzzles screen is open.

A solved puzzle is recorded as a hit by itself. After a wrong move,
"Show the consequences" plays the engine's punishment of it, and "Record"
saves the attempt with the number of mistakes; such puzzles go to the
Positions screen. The list of attempts is clickable: a puzzle opens again
with your mistakes from last time and the solution button.

---

## Positions

The Positions screen keeps the positions you missed in puzzles and the
moves you underlined. Search by game, player or trait, and filter by trait
chips and a rating range. "By trait" sums the positions up from the most
general traits to the most particular: colour, stage, type, direction,
character, the kinds missed, the kinds you were punished by, and the cost.

---

## Games and analyses

- The home screen holds your last five analysed games on top, then the
  showcase games in decks: the masters, AlphaZero against Stockfish 8, and
  engine games made for the app. Swipe
  the top card away to see the next one. Below the decks is the list of all
  games.
- **Copy PGN** (quick settings of a game) puts the game on the clipboard.
- In the move list, hold a move to select it and drag to select a range;
  the round buttons at the top copy the moves. Holding a branch move also
  offers to delete it, with every move and branch after it. Under a move with an idea, "Better" and
  "Punished" open the idea's lines as branches.
- Branch moves are coloured by where they come from: blue — the game's
  analysis (not recalculated), grey — the engine on the device continuing a
  line, purple — a move you played. "Next" at the end of a branch goes on
  with the device engine; a step back drops a grey continuation that may be
  stale. "Next" between your own (purple) moves opens a new branch with the
  engine's best move instead of your next move. A move of yours in the
  middle of a branch that goes on with blue or
  purple moves opens a new branch from it; going back past your move
  returns to the old branch. The number at the edge of a move counts its
  branches; tap it to fold them.
- The analysis window shows the engine power modes; the mode can be
  changed while the analysis runs. A finished analysis offers to open the
  game or to close the window.
- On the free analysis board, hold a move to select it: the round buttons
  copy the line up to it or delete it with every move after it.
- While a game is being analysed, only the Game tab with the move list
  works; the other tabs and the graphs open when the analysis is done.
- The rings at the bottom right show the analyses in the queue; the inner
  circle glows while the engine computes and goes dark while it rests.
  With more than three, the fourth ring ("+X") opens the history.
- A star marks a finished analysis as a favourite; the history can show
  the favourites only. Analysing a game again keeps its star.
- Once a day at start the app looks for a new version of ChessAnalyst on
  GitHub and offers it. Only that request is sent.
- When a game is analysed, its puzzles can be switched off; the game still
  counts for the weakness profile.
- The app can notify you when an analysis is finished (it asks once, after
  your first analysis).
