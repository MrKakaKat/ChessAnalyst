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
| Blunder | a won position thrown away, a mate allowed, a missed mate in one, or a drop of two categories |
| Pass | the opponent offered a chance and it was missed, but the position is no worse than before |

**Steps in percent** (quick settings). Moves are graded by how much of the
expected result they lose instead: best up to 1%, excellent 1–2%, good
2–5%, inaccuracy 5–10%, laxity 10–15%, mistake 15–25%, blunder over 25%.
Only the percent counts: in a decided position (−7 → −6) the result does
not change, and the move is not a mistake. A lost win or an allowed mate
stays a blunder. A move off the best lines that loses up to 1% is neutral.

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
| Positional fork | the piece attacks two valuable pieces at once, here and now (often after a blunder, or after the tactical part of a fork was played) |
| Tactical fork | a forcing move (check, capture or sacrifice) whose line leads in up to three more forcing own moves to a fork; it comes before the positional fork, and the opponent's best play usually leads into it (otherwise it wins some other way) |
| Blocked king escape | a quiet move (no check, not in the opening) whose piece, often a bishop, takes a square from the enemy king for its next move and leaves it two squares or fewer; in the endgame also a king move that takes two squares from the other king — the start of a blockade, where neither king gets into the other's zone |
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
- **Significance** — how much the mistake says about the player, 0–100,
  from three equal parts: D, the drop of the evaluation (6 pawns or an
  allowed mate = 100); I, how intuitive the best move was (a natural move
  missed weighs more); C, how complex the position was (a mistake in a
  simple one weighs more). Significance = (D + I + (100 − C)) / 3. The
  accuracy window lists the mistakes of the game by what they missed, with
  the significance and its parts on the right.
- **Aim** — where it is more sensible to go from the position by WDL: play
  for the win (at least 30% to win and twice the chance to lose), aim for a
  draw (the other way round), or keep the balance. With it the human move:
  the engine line that serves the aim best (for a win the most chances with
  little risk, for a draw the fewest losing chances), marked "human" when
  it is not the engine's first. "More graphs" shows the aim of every move.
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

## Evaluation: Pawns, WDL, Diff

- **Pawns** — the engine's evaluation in pawns.
- **WDL** — the chances to win, draw or lose, as an expected result.
- **Diff** — the practical evaluation of the difficulty analysis (see
  Position difficulty): the bar, the graph and the Diff column of the
  accuracy window. Without that analysis the bar is all grey and the graph
  shows only a **Run this analysis** button (own games): the classic
  analysis stays, only the difficulty part runs.
- **AAC** (in More graphs) — counterplay instead of the engine score. Each side gets three
  parts:
  - **Abilities**: its threats and the checks it can give. Only good checks
    count: ones that keep the position (by the engine) or at least do not
    lose the checking piece;
  - **Activity**: the free squares its pieces control;
  - **Complication**: how hard the position is for the opponent, that is how
    few good replies they have.

  The AAC graph (More graphs) compares both sides at every move. The move card shows the
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
- rings of results (won, drawn, lost) for all games and each colour, the
  number of games in the middle and the negative moves under the ring;
- mistakes by stage;
- accuracy by kind of move: how many of your moves had the kind, their
  mean accuracy, and how often that kind was the best move and you missed
  it;
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

## Position difficulty

An optional second analysis, after the classic one: the **Position
difficulty** button in the analysis window (off by default, not recommended:
it takes much longer). It can also be added to an analysed game from the
history (Analyze again with the same depth and lines adds only this part).

The engine says how big an advantage is, not how hard it is to keep. This
analysis measures that:

- **Classes.** A position is a win from +3 (a mate counts as +8), a loss
  from −3, a draw between. Only the boundary 3 matters.
- **Only moves.** Along the best lines of each position the engine looks
  at every move with three candidates of its own. A move is good when it
  keeps the class and, in a position that is not won, loses no more than a
  pawn. When one move is good, it is an only move: tactical (check, capture,
  promotion) or positional (a quiet move; a forced draw is often a row of
  them). An only move weighs more the further it is: 0.15 on the first move
  of the line, +0.085 for each further own move, up to 1 — on the second
  move it is little, on the tenth a lot. An obvious only move — a recapture,
  or a piece taken away from an attack by a cheaper piece (or from an
  attack when it is not defended) — weighs 0.3 of that and is not marked
  blue.
- **Mates.** A mate line counts as one only move at the distance of the
  mate: a mate in 2 is easy, in 10 hard. A mate in one is a positional mate,
  the lightest only move — and missing it is always a blunder and the worst
  move of the game (the first one when there are several).
- **A line** is 0% hard when every move has several ways on and up to 100%
  with one far tactical only move.
- **A position** for the side to move: the mean difficulty of its good lines
  — the more of them, the easier — and its first move when it is the only
  good one. For the other side: its moves in the best line.
- **Percent** against the middle standard: the share of positions of
  reference games (masters, engines and our own, 1103 positions) that are
  easier, for each side separately. 50% is a usual position.
- **Practical evaluation**: E′ = E · (1.5 − difficulty of the side ahead).
  +6 at 80% gives +4.2, at 30% +7.2. A mate counts as +8. It is the
  **Diff** unit; AAC stays in More graphs.
- **Diff grades** (the accuracy window): a negative move is graded again by
  the practical evaluation it lost — a lost class is a blunder (and a missed
  mate in one), then over 1 pawn a mistake, 0.5 laxity, 0.1 inaccuracy, less
  neutral. A miss in a hard position costs less.

Where it shows:
- a line whose evaluation is **blue** needs an only move of the side to
  move (the first move from the classic analysis, the later ones from this
  one; on the free board — the first move);
- the move card: **Difficulty** for both sides and the practical evaluation
  next to the engine's; **Only move** — the only moves of the best line: the
  first move when it is the one good move, the later ones from this
  analysis, each with its move, tactical or positional, obvious or not and
  its difficulty by distance, a mate by its length, and how hard the whole
  line is;
- the accuracy window: how difficult each side's positions were and the
  accuracy **with difficulty** — a miss in a hard position costs less, in an
  easy one more;
- puzzles: from a game with this analysis an attacking puzzle is made only
  when the practical evaluation **after the key move** is +3 or more — the
  advantage holds once the move is found (below it the position is
  disputed). The difficulty before the move is the puzzle's own difficulty:
  it raises the rating (−150 for the easiest position, 0 for a usual one,
  up to +300 for the hardest) instead of dropping the puzzle. Your moves are
  checked by the practical evaluation too: a move counts when it keeps +3 or
  is no worse than the solution's.
  Such puzzles are marked **With position difficulty**, the others **Engine
  evaluation**.

---

## Puzzles

Puzzles come from analysed games, your own included. A position becomes a
puzzle when one move stands out:
- a mate;
- a winning blow (the best line reaches +4) or an advantage-gaining one
  (+3; +2 only in the opening and early middlegame when the position stays
  calm);
- the only defence that holds;
- combined: an attack whose line leads straight into a position where only
  a precise defence holds (or the other way round) — take the advantage,
  then hold it. The goal changes on the way.

The solution goes on while the tactic does. In attacking puzzles any move
that keeps the goal counts as correct. In defensive puzzles the first move
must be the one saving move; after it, another move counts too when it
holds as well (within half a pawn of the solution).

Puzzles are unbroken pieces: when a puzzle's line was played in the game
and the next puzzle starts right after the opponent's reply, they become
one puzzle (the same kind of goal goes on; an attack into a needed defence
becomes combined). A puzzle does not stop where the next one starts.
Puzzles do not overlap either: when two puzzles share positions, the longer
one is kept.

The rating of a puzzle comes from the engine. It is computed when the
game's analysis ends, and again when the analysis is sent deeper. Each of
your moves in the solution (up to three) is rated, and the hardest one
counts most: a puzzle that starts with a plain recapture and needs a deep
quiet move after it is as hard as that quiet move. A move's difficulty
depends on how deep the engine must search before it keeps choosing the
solution, how many other moves look as good at a glance, whether the key
move is quiet, the length of the solution and a defensive goal. It also
counts the opponent's counter-chances: replies with check or capture that
nearly hold and have to be calculated, and how long the forcing play lasts.
Two things make a move easier: a check that leaves the opponent one or two
replies (a long mate by checks alone is found by just giving checks), and,
in an attack, several moves that reach the goal at that step. Puzzles that
were not rated yet are rated in the background while the Puzzles screen is
open.

A puzzle's best line is not the only one: a deeper search often finds a
second good move. A move off the line is checked by the engine (depth 16,
the analysis of a game pauses meanwhile). It counts when it is no worse
than the solution's move at the same depth (within 0.3 pawn), or when it
keeps the goal: another mate or a crushing line (+5) in a mate
puzzle, a line at least 60% as strong in the others; in a defence, a move
that holds as well (within 0.3 pawn of the solution on the first move, 0.5
later).

Each game's puzzles and mistakes are saved once, when its analysis ends;
the Puzzles screen only reads them, so it opens fast however many games
there are. By default the puzzles come only from your own games; the
showcase games (masters, engines) can be switched on. New puzzles come
first, then the ones already opened, the ones solved cleanly last.

A solved puzzle is recorded as a hit by itself. After a wrong move,
"Show the consequences" plays the engine's punishment of it (the arrows go
through it move by move; it is kept for this puzzle), and "Record" saves
the attempt with the number of mistakes; such puzzles go to the Positions
screen. "Record mistakes automatically" does it without the button. The same
mistake is recorded only once, also after "Again". The list of attempts is
clickable: a puzzle opens again with your mistakes from last time and the
solution button. While a move is being checked, the analysis of a game
pauses.

**Weakness profile.** Puzzles like your mistakes come first. The mistakes
weigh, from the heaviest: the moves you underlined in your games (×2), the
other mistakes in your games by how serious they are (inaccuracy 1 …
blunder 4), mistakes in puzzles (1.25 for a try with a mistake, +0.25 for
each further one, up to 2), and mistakes when correcting your own games
(Start to improve) with the same weight as in puzzles. Enter your names in
the games (Statistics) so that the profile follows your own moves.

---

## Positions

The Positions screen keeps the positions you missed in puzzles (with the
number of mistakes and their weight in the profile) and the moves you
underlined. Search by game, player or trait, and filter by trait
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
- **Lines** tab: tap the evaluation of a line to walk it on the board —
  the whole line becomes a branch, the arrows step through it; tap the
  moves to play just the first one. In a branch the tab shows lines the
  device engine computes for that position (five lines, depth 14).
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
  copy the line up to it, make its branch the main line (or a side one), or
  delete it with every move after it. "Copy PGN" takes the whole tree with
  every branch. Tap the evaluation of an engine line to walk along it
  without a new analysis: the arrows step through it, the move on the board
  is blue. A session reopens where you stopped, from the same side.
- Sessions: openings (a clean board from the start; named by you, shown with
  the opening's name) and positions (opened with the analysis icon, from a
  puzzle or elsewhere), switched at the top of the list. Pin a session to
  the top or star it.
- A drawn game ends with a ½ badge: threefold repetition, stalemate,
  insufficient material, the fifty-move rule or agreement.
- The rating estimate in the accuracy window comes from the mean accuracy
  of the three stages of the game.
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

---

## Board settings

- **Icons on the board** (Settings): tap a kind of move to hide its icon on
  the board — for example book or neutral moves. The move list and the move
  card keep it.
- **Own squares** (Settings → Board): pick a picture for the light and one
  for the dark squares. Cut a square from it — drag to move, pinch or use
  the slider to zoom — and it becomes one board square. With both pictures
  the board uses them (the "Own" sample); the cross on a picture removes it.
