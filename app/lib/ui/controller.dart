/// Game screen state: game, unit, selected move, own variations, idea chain
/// playback, locks.
///
/// The board shows the position *after* the selected move: the move's mark,
/// the navigation label and the evaluation all refer to the move just made.
///
/// Own variations: a move on the board that differs from the game starts a
/// branch after the current position. There is no engine in the app yet, so a
/// branch move gets an evaluation only when the branch follows one of the
/// game's engine lines (MultiPV) from the branch point.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/foundation.dart';

import '../analysis/eval.dart';
import '../analysis/aac.dart';
import '../analysis/character.dart';
import '../analysis/kinds.dart';
import '../analysis/classify.dart';
import '../analysis/game.dart';
import '../analysis/ideas.dart';
import '../analysis/locks.dart';
import '../analysis/openings.dart';
import '../analysis/pos.dart';
import '../analysis/settings.dart';
import '../engine/bot.dart';
import 'prefs.dart';
import 'step_icons.dart';
import 'widgets/arrows.dart';

class SelectedLock {
  const SelectedLock(this.anchor, this.slider, this.target);

  final int anchor;
  final Square slider, target;
}

/// A move of an own variation.
class VarMove {
  const VarMove({
    required this.move,
    required this.san,
    required this.before,
    required this.after,
    this.eval,
    required this.root,
    this.record,
    this.moveType,
    this.auto = false,
    this.live = false,
  });

  /// Computed on the device now (an own move, or the engine's continuation
  /// past the analysed lines): grey, and judged again when needed. Moves of
  /// the game's analysis (blue) are not.
  final bool live;

  /// Added by stepping on along the engine's line (or by Why?), not played
  /// by hand: replaced when the user plays another move before it.
  final bool auto;

  final NormalMove move;
  final String san;
  final Pos before, after;

  /// Evaluation of the engine line this branch follows, from [root]'s side;
  /// null when the branch left the analysed lines.
  final Eval? eval;
  final Side root;

  /// Full verdict, for a branch's first move played in an analysed position.
  final MoveRecord? record;

  /// Move type, for deeper moves that follow the engine line.
  final String? moveType;

  /// Follows the analysed engine lines of the game (blue).
  bool get inLines => eval != null && !live;

  /// Played by hand outside the analysed lines (purple): it starts its own
  /// branch and is never replaced by a recalculation.
  bool get manual => !auto && !inLines;

  /// The engine's continuation computed on the device (grey): the only moves
  /// that a recalculation may replace.
  bool get engineLive => auto && live;

  /// Icon kind: the verdict's, best for a move along the engine line, null
  /// for an own move outside the lines.
  String? get kind {
    if (record case final r?) return iconKindOf(r.step, r.subtype);
    return eval != null ? 'best' : null;
  }
}

/// An engine line of a game position, judged as if it had been played.
class AltMove {
  const AltMove({required this.uci, required this.san, required this.eval, required this.side, required this.kind,
      required this.type});

  final String uci, san;

  /// Line evaluation from [side]'s point of view.
  final Eval eval;
  final Side side;
  final String kind;
  final String type;
}

/// How the game ended, shown as a last pseudo-move: resignation (graded by the
/// position the loser gave up) or loss on time.
class GameEnd {
  const GameEnd({required this.kind, required this.loser, this.step, this.category});

  /// 'resign' or 'timeout'.
  final String kind;
  final Side loser;

  /// Grade of a resignation: lost position — neutral, slightly worse —
  /// inaccuracy, equal — mistake, better or winning — blunder.
  final String? step;
  final String? category;

  String get label => kind == 'resign' ? 'Resign' : 'Time out';
}

/// A branch from the game: starts after main-line ply [anchor] (−1: from the
/// initial position).
class Variation {
  Variation(this.anchor, {this.parent, this.forkAt = 0});

  final int anchor;
  final moves = <VarMove>[];

  /// A branch forked from another one by a move played by hand: its first
  /// [forkAt] moves are the parent's.
  final Variation? parent;
  final int forkAt;
}

/// Colours of branch moves: blue — the game's analysis, grey — the device
/// engine's continuation, purple — a move played by hand.
const branchAnalysisColor = Color(0xFF3B82F6);
const branchEngineColor = Color(0xFF8A8F98);
const branchManualColor = Color(0xFF8E5CD9);

Color branchColor(VarMove m) =>
    m.inLines ? branchAnalysisColor : (m.manual ? branchManualColor : branchEngineColor);

class AnalysisController extends ChangeNotifier {
  /// [analysis]: an analysis made beforehand in pawns (analysis_cache.dart),
  /// so the screen does not wait for it.
  AnalysisController(this.game,
      {this.book, Unit unit = Unit.pawns, bool percentSteps = false, GameAnalysis? analysis})
      : _unit = unit,
        _percent = percentSteps {
    _analysis = analysis != null && unit == Unit.pawns && !percentSteps
        ? analysis
        : analyzeGame(game, Settings(unit: unit, percentSteps: percentSteps), book: book);
    for (final p in game.plies) {
      final b = Pos.fromFen(p.fenBefore);
      before.add(b);
      after.add(b.push(Pos.move(p.uci)));
      moves.add(Pos.move(p.uci));
    }
  }

  /// The game with its engine data; replaced while the device analyses it.
  GameData game;
  final OpeningBook? book;

  /// Positions before and after each ply, and the played moves.
  final before = <Pos>[];
  final after = <Pos>[];
  final moves = <NormalMove>[];

  late GameAnalysis _analysis;
  Unit _unit;
  int _ply = -1; // −1: начальная позиция
  int _previousPly = -1;
  bool _flipped = false;
  bool _busy = false;

  Idea? _idea;
  Timer? _player;
  SelectedLock? _lock;

  final variations = <Variation>[];
  Variation? _var;
  int _varIndex = -1;

  GameAnalysis get analysis => _analysis;
  Unit get unit => _unit;
  int get ply => _ply;
  int get previousPly => _previousPly;
  bool get flipped => _flipped;
  bool get busy => _busy;
  int get length => game.plies.length;

  /// Shown at the initial position, before the first move.
  bool get atStart => _var == null && _ply < 0;

  /// Shown at the game's end pseudo-move (resign / time out).
  bool get atEnd => _var == null && _ply >= length;

  /// Last selectable ply: the end pseudo-move when there is one.
  int get lastPly => length - 1 + (end != null ? 1 : 0);

  /// The game move whose analysis the panels show.
  int get recordPly => _ply.clamp(0, length - 1);

  /// Whether game move [ply] gives checkmate.
  bool isMate(int ply) => ply >= 0 && ply < length && after[ply].isCheckmate;

  /// Icon kind of game move [ply]: checkmate first, then the verdict.
  String kindAt(int ply) {
    if (isMate(ply)) return 'mate';
    final r = _analysis.records[ply];
    return iconKindOf(r.step, r.subtype);
  }

  /// Colour of [kind] for game move [ply]: checkmate is green seen from the
  /// winner's side of the board, red from the loser's.
  Color kindColorAt(int ply, String kind) {
    if (kind != 'mate') return markColor(kind);
    final viewer = _flipped ? Side.black : Side.white;
    return markColor(_analysis.records[ply].side == viewer ? 'best' : 'blunder');
  }

  /// Record of the shown game move; null at the start and the end.
  MoveRecord? get record => _var != null || atStart || atEnd ? null : _analysis.records[_ply];

  GameEnd? _end;
  bool _endDone = false;
  final _alts = <int, List<AltMove>>{};

  /// Engine lines of the position before game move [ply], each judged as if
  /// played (step icon, type), best first.
  List<AltMove> alternatives(int ply) => _alts.putIfAbsent(ply, () {
        final p = game.plies[ply];
        final board = before[ply];
        final s = Settings(unit: _unit, percentSteps: _percent, multipv: (game.engine['multipv'] as num?)?.toInt() ?? 5);
        final prev = ply > 0 ? game.plies[ply - 1].lines.first.eval : null;
        return [
          for (final ln in p.lines)
            () {
              final r = classify(board, p.lines, ln, prev, s,
                  ply: ply, allLines: p.allLines, continuation: ln.pv.skip(1).take(6).toList());
              final m = Pos.move(ln.move);
              return AltMove(
                uci: ln.move,
                san: board.san(m),
                eval: ln.eval,
                side: board.turn,
                kind: board.push(m).isCheckmate ? 'mate' : iconKindOf(r.step, r.subtype),
                type: r.moveType,
              );
            }(),
        ];
      });

  /// The game's end as a pseudo-move, if it ended by resignation or on time.
  GameEnd? get end {
    if (_endDone) return _end;
    _endDone = true;
    final h = game.headers;
    final result = h['result'];
    final how = h['termination'] ?? '';
    if ((result != '1-0' && result != '0-1') || length == 0) return _end = null;
    final loser = result == '1-0' ? Side.black : Side.white;
    if (how == 'time') return _end = GameEnd(kind: 'timeout', loser: loser);
    if (how != 'resign') return _end = null;
    final r = _analysis.records.last;
    const cats = ['loss', 'worse', 'equal', 'better', 'win'];
    var i = cats.indexOf(r.catEp);
    if (r.side != loser) i = 4 - i; // оценка — с точки зрения сдавшегося
    final step = switch (i) { 0 => 'neutral', 1 => 'inaccuracy', 2 => 'mistake', _ => 'blunder' };
    return _end = GameEnd(kind: 'resign', loser: loser, step: step, category: cats[i]);
  }
  Idea? get selectedIdea => _idea;
  bool get playing => _playingIdea;
  SelectedLock? get selectedLock => _lock;

  /// +1 when moving forward through the game, −1 backward (for animations).
  int get direction => _ply >= _previousPly ? 1 : -1;

  void select(int ply) {
    final p = ply.clamp(-1, lastPly);
    if (p == _ply && _var == null) return;
    _var = null;
    _previousPly = _ply;
    _ply = p;
    // ушли за пределы выбранной идеи — она снимается (и синий контур доски)
    final idea = _idea;
    if (idea != null && !_playingIdea && !_ideaNav) {
      final plies = chainPlies(idea);
      final last = math.max(plies.reduce(math.max), idea.punishPly + 1);
      if (p < plies.reduce(math.min) - 1 || p > last) _idea = null;
    }
    notifyListeners();
  }

  /// "Step through mistakes": next / previous go only to negative moves
  /// (inaccuracy and worse, not book moves).
  bool errorsOnly = false;

  void setErrorsOnly(bool on) {
    errorsOnly = on;
    notifyListeners();
  }

  static const _negative = {'inaccuracy', 'pass', 'laxity', 'mistake', 'blunder'};

  bool isNegativeAt(int ply) => ply >= 0 && ply < length && _negative.contains(_analysis.records[ply].step);

  int? nextNegative([int? from]) {
    for (var p = (from ?? _ply) + 1; p < length; p++) {
      if (isNegativeAt(p)) return p;
    }
    return null;
  }

  int? prevNegative([int? from]) {
    for (var p = (from ?? _ply) - 1; p >= 0; p--) {
      if (isNegativeAt(p)) return p;
    }
    return null;
  }

  void next() {
    // в блоке идеи — только по её кадрам
    if (_ideaStep(1)) return;
    final v = _var;
    if (v == null && errorsOnly) {
      final p = nextNegative();
      if (p != null) select(p);
      return;
    }
    if (v == null) return select(_ply + 1);
    if (_varIndex < v.moves.length - 1) return selectVar(v, _varIndex + 1);
    // в конце ветки, идущей по линии движка, «далее» продолжает эту линию
    final m = _lineContinuation();
    if (m != null) return _enter(v.anchor, [for (final x in v.moves) x.move, m], auto: true);
    // за линиями анализа — лучший ход движка на устройстве (серый)
    _liveContinuation(v);
  }

  /// Engine continuations computed on the device, by position.
  final _liveLines = <String, Line>{};
  bool _liveBusy = false;

  /// Appends the device engine's best move after the end of [v] (depth 14);
  /// its evaluation is the line's.
  Future<void> _liveContinuation(Variation v) async {
    if (_liveBusy || v.moves.isEmpty) return;
    final last = v.moves.last;
    final pos = last.after;
    if (pos.p.isGameOver) return;
    _liveBusy = true;
    notifyListeners();
    try {
      final key = pos.fen;
      var line = _liveLines[key];
      if (line == null) {
        final bot = await EngineBot.shared();
        final lines = await bot.analyse(pos.fen, depth: 14, multipv: 1);
        if (lines.isEmpty) return;
        line = lines.first;
        _liveLines[key] = line;
      }
      if (!identical(_var, v) || !identical(v.moves.last, last)) return;
      final m = Pos.move(line.move);
      if (!pos.isLegal(m)) return;
      v.moves.add(VarMove(
        move: m,
        san: pos.san(m),
        before: pos,
        after: pos.push(m),
        eval: pos.turn == last.root ? line.eval : line.eval.negate(),
        root: last.root,
        auto: true,
        live: true,
      ));
      selectVar(v, v.moves.length - 1);
    } catch (_) {
      // движок недоступен
    } finally {
      _liveBusy = false;
      notifyListeners();
    }
  }

  /// Next move of the engine line the shown branch follows, if any.
  NormalMove? _lineContinuation() {
    final v = _var;
    if (v == null || _varIndex != v.moves.length - 1 || !v.moves.last.inLines) return null;
    final ucis = [for (final x in v.moves) x.move.uci];
    final line = _line(v.anchor + 1, ucis);
    if (line == null || line.pv.length <= ucis.length) return null;
    final m = Pos.move(line.pv[ucis.length]);
    return v.moves.last.after.isLegal(m) ? m : null;
  }

  void prev() {
    if (_ideaStep(-1)) return;
    final v = _var;
    // назад с первого своего хода ответвления — в ветку, от которой оно
    // ответвилось: «далее» поведёт по ней, а не по ответвлению
    if (v != null && v.parent != null && _varIndex == v.forkAt && variations.contains(v.parent)) {
      if (v.forkAt == 0) return exitVariation();
      return selectVar(v.parent!, v.forkAt - 1);
    }
    if (v == null && errorsOnly) {
      final p = prevNegative();
      if (p != null) select(p);
      return;
    }
    if (v == null) return select(_ply - 1);
    if (_varIndex > 0) {
      // шаг назад: пролистанное на устройстве продолжение после этого места
      // устарело (ход могли переоценить) — убирается, «далее» посчитает заново
      final rest = v.moves.skip(_varIndex);
      if (rest.isNotEmpty && rest.every((x) => x.auto && x.live)) {
        for (final x in rest) {
          _liveLines.remove(x.before.fen);
        }
        v.moves.removeRange(_varIndex, v.moves.length);
      }
      return selectVar(v, _varIndex - 1);
    }
    exitVariation();
  }

  // --- own variations ---

  Variation? get variation => _var;
  int get varIndex => _varIndex;
  bool get inVariation => _var != null;
  VarMove? get varMove => _var?.moves[_varIndex];

  /// Position on the board.
  Pos get position => varMove?.after ?? (_ply < 0 ? before[0] : after[recordPly]);

  /// The move that led to [position]; none at the start and the end.
  NormalMove? get lastMove => varMove?.move ?? (atStart || atEnd ? null : moves[_ply]);

  /// Identifies the shown position: main ply, or variation and index.
  Object get positionKey => _var == null ? _ply : (variations.indexOf(_var!), _varIndex);

  /// Ply index of the shown move (in a variation: as if it were the game).
  int get shownPlyIndex => _var == null ? _ply : _var!.anchor + 1 + _varIndex;

  Pos _base(int anchor) => anchor < 0 ? before[0] : after[anchor];

  List<Variation> variationsAt(int anchor) => [for (final v in variations) if (v.anchor == anchor) v];

  void selectVar(Variation v, int index) {
    if (!variations.contains(v)) return;
    _var = v;
    _varIndex = index.clamp(0, v.moves.length - 1);
    // панели показывают ход партии, который ветка заменяет (та же позиция,
    // те же лучшие ходы)
    final replaced = math.min(v.anchor + 1, length - 1);
    if (replaced != _ply) {
      _previousPly = _ply;
      _ply = replaced;
    }
    notifyListeners();
  }

  void exitVariation() {
    final v = _var;
    if (v == null) return;
    _var = null;
    _ply = v.anchor;
    notifyListeners();
  }

  /// Where the user is in the game, to come back to it next time: the move,
  /// the unit, the own branches and the shown branch move.
  Map<String, dynamic> saveState() => {
        'ply': _ply,
        'unit': _unit.name,
        'vars': [
          for (final v in variations) {'anchor': v.anchor, 'moves': [for (final m in v.moves) m.move.uci]},
        ],
        if (_var != null) 'var': variations.indexOf(_var!),
        if (_var != null) 'varIndex': _varIndex,
      };

  Future<void> restoreState(Map<String, dynamic> s) async {
    final unit = Unit.values.asNameMap()[s['unit']];
    if (unit != null && unit != _unit) await setUnit(unit);
    for (final v in (s['vars'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final anchor = v['anchor'] as int;
      if (anchor >= length) continue;
      var pos = _base(anchor);
      final seq = <NormalMove>[];
      for (final uci in (v['moves'] as List).cast<String>()) {
        final m = Pos.move(uci);
        if (!pos.isLegal(m)) break;
        seq.add(m);
        pos = pos.push(m);
      }
      if (seq.isNotEmpty) _enter(anchor, seq);
    }
    _var = null;
    final vi = s['var'] as int?;
    if (vi != null && vi >= 0 && vi < variations.length) {
      selectVar(variations[vi], s['varIndex'] as int? ?? 0);
    } else {
      select((s['ply'] as int? ?? -1).clamp(-1, lastPly));
    }
    notifyListeners();
  }

  /// Removes every own branch of the game.
  void clearVariations() {
    exitVariation();
    variations.clear();
    notifyListeners();
  }

  void removeVariation(Variation v) {
    if (identical(v, _var)) exitVariation();
    variations.remove(v);
    notifyListeners();
  }

  /// A move made on the board from the shown position.
  void playMove(NormalMove m) {
    m = _normalize(position, m);
    // свой ход — выход из идеи
    if (_idea != null) {
      stopChain();
      _idea = null;
      _framesToken++;
      _frames.clear();
    }
    final v = _var;
    if (v == null) {
      final p = math.min(_ply, length - 1);
      if (p + 1 < length && moves[p + 1] == m) return select(p + 1);
      return _enter(p, [m]);
    }
    final at = _varIndex + 1;
    // тот же ход, что дальше в ветке, — просто шаг
    if (at < v.moves.length && v.moves[at].move == m) return selectVar(v, at);
    // [авторское] дальше только серые ходы (продолжение движка телефона) —
    // они заменяются; если дальше есть синие или свои (фиолетовые), ветка
    // остаётся как есть, а свой ход открывает от неё новое ответвление
    final rest = v.moves.skip(at);
    if (rest.isEmpty || rest.every((x) => x.engineLive)) {
      if (rest.isNotEmpty) v.moves.removeRange(at, v.moves.length);
      _enter(v.anchor, [for (final x in v.moves) x.move, m]);
      return;
    }
    _fork(v, at, m);
  }

  /// A new branch from [v]: its first [at] moves and the move [m] played by
  /// hand (an existing fork with the same move is reused).
  void _fork(Variation v, int at, NormalMove m) {
    for (final x in variations) {
      if (identical(x.parent, v) && x.forkAt == at && x.moves.length > at && x.moves[at].move == m) {
        return selectVar(x, at);
      }
    }
    final f = Variation(v.anchor, parent: v, forkAt: at);
    f.moves.addAll(v.moves.take(at));
    final pos = at == 0 ? _base(v.anchor) : v.moves[at - 1].after;
    f.moves.add(_varMove(v.anchor, f.moves, pos, m));
    variations.insert(variations.indexOf(v) + 1, f);
    selectVar(f, at);
    if (prefs.analyzeOwnMoves && f.moves[at].manual) _judge(f, at);
  }

  /// How the opponent profits from move [ply]: the engine's best line after
  /// it, as a branch, shown from its first move.
  /// [простое решение] The line is cut after [punishPlies] plies (or where
  /// it ends): far enough for the gain to show, before it turns into play
  /// of its own.
  static const punishPlies = 8;

  bool canShowPunishment(int ply) =>
      ply >= 0 && ply + 1 < length && game.plies[ply + 1].lines.first.pv.isNotEmpty;

  void showPunishment(int ply) {
    if (!canShowPunishment(ply)) return;
    stopChain();
    var pos = after[ply];
    final seq = <NormalMove>[];
    for (final uci in game.plies[ply + 1].lines.first.pv.take(punishPlies)) {
      final m = Pos.move(uci);
      if (!pos.isLegal(m)) break;
      seq.add(m);
      pos = pos.push(m);
    }
    if (seq.isEmpty) return;
    _enter(ply, seq, auto: true);
    final v = _var;
    if (v != null) selectVar(v, 0);
  }

  /// Opens an engine line after main-line ply [anchor] as a branch (up to
  /// [plies] moves), shown from its first move.
  void showLine(int anchor, List<String> pv, {int plies = 12}) {
    var pos = _base(anchor);
    final seq = <NormalMove>[];
    for (final uci in pv.take(plies)) {
      final m = Pos.move(uci);
      if (!pos.isLegal(m)) break;
      seq.add(m);
      pos = pos.push(m);
    }
    if (seq.isEmpty) return;
    _enter(anchor, seq, auto: true);
    final v = _var;
    if (v != null) selectVar(v, 0);
  }

  /// SAN of game plies [from]…[to] with move numbers ("4. Bb5 a6 5. Bxc6+").
  String movesText(int from, int to) {
    final a = math.min(from, to), b = math.max(from, to);
    final words = <String>[];
    for (var p = a; p <= b && p < length; p++) {
      final n = p ~/ 2 + 1;
      if (p.isEven) {
        words.add('$n.');
      } else if (p == a) {
        words.add('$n...');
      }
      words.add(game.plies[p].san);
    }
    return words.join(' ');
  }

  /// SAN of [pv] played from the position before main-line ply [ply].
  List<String> lineSans(int ply, List<String> pv, {int plies = 8}) {
    var pos = before[ply];
    final out = <String>[];
    for (final uci in pv.take(plies)) {
      final m = Pos.move(uci);
      if (!pos.isLegal(m)) break;
      final n = (ply + out.length) ~/ 2 + 1;
      final white = pos.turn == Side.white;
      out.add('${white ? '$n. ' : (out.isEmpty ? '$n... ' : '')}${pos.san(m)}');
      pos = pos.push(m);
    }
    return out;
  }

  /// Plays an alternative to main-line move [ply] (a best or a book move).
  void playAlternative(int ply, String uci) {
    final m = Pos.move(uci);
    if (m == moves[ply]) return select(ply);
    _enter(ply - 1, [m]);
  }

  /// King moves onto its rook (chessground) → e1g1 / e1c1, as in the game data.
  static NormalMove _normalize(Pos pos, NormalMove m) {
    final piece = pos.pieceAt(m.from);
    if (piece?.role != Role.king) return m;
    final target = pos.pieceAt(m.to);
    final ontoRook = target != null && target.color == piece!.color && target.role == Role.rook;
    if (!ontoRook && (m.from.file - m.to.file).abs() < 2) return m;
    final file = m.to.file > m.from.file ? File.g : File.c;
    return NormalMove(from: m.from, to: Square.fromCoords(file, m.from.rank));
  }

  void _enter(int anchor, List<NormalMove> seq, {bool auto = false}) {
    bool startsWith(Variation v, List<NormalMove> s) =>
        v.moves.length >= s.length && [for (var i = 0; i < s.length; i++) v.moves[i].move == s[i]].every((x) => x);
    for (final v in variationsAt(anchor)) {
      if (startsWith(v, seq)) return selectVar(v, seq.length - 1);
    }
    // продолжение ветки с её конца — дописывается в ту же ветку
    Variation? target;
    for (final v in variationsAt(anchor)) {
      if (v.moves.length == seq.length - 1 && startsWith(v, seq.sublist(0, seq.length - 1))) target = v;
    }
    if (target == null) {
      target = Variation(anchor);
      var pos = _base(anchor);
      for (final m in seq.take(seq.length - 1)) {
        target.moves.add(_varMove(anchor, target.moves, pos, m, auto: auto));
        pos = pos.push(m);
      }
      variations.add(target);
    }
    final pos = target.moves.isEmpty ? _base(anchor) : target.moves.last.after;
    target.moves.add(_varMove(anchor, target.moves, pos, seq.last, auto: auto));
    selectVar(target, target.moves.length - 1);
    if (prefs.analyzeOwnMoves) {
      // пересчитываются только свои (фиолетовые) ходы: синие — из анализа,
      // серые — уже лучшие ходы движка
      for (var i = 0; i < target.moves.length; i++) {
        if (target.moves[i].record == null && target.moves[i].manual) _judge(target, i);
      }
    }
  }

  /// Engine verdicts of own moves (by position and move), shared by branches.
  final _judged = <String, (MoveRecord, Eval)>{};
  final _judging = <String>{};

  /// Judges branch move [i] of [v] with the engine on the device: the lines
  /// of the position before it (depth 12, five lines), the move's own line,
  /// then the usual verdict. [простое решение] Without the previous
  /// position's evaluation the verdict misses E0 (pass, only move by gain).
  Future<void> _judge(Variation v, int i) async {
    final vm = v.moves[i];
    final key = '${vm.before.fen}|${vm.move.uci}';
    void apply((MoveRecord, Eval) hit) {
      final k = v.moves.indexWhere((x) => identical(x, vm));
      if (k < 0) return;
      final (record, eval) = hit;
      v.moves[k] = VarMove(
        move: vm.move,
        san: vm.san,
        before: vm.before,
        after: vm.after,
        eval: vm.before.turn == vm.root ? eval : eval.negate(),
        root: vm.root,
        record: record,
        moveType: record.moveType,
        auto: vm.auto,
        live: true,
      );
      notifyListeners();
    }

    if (_judged[key] case final hit?) return apply(hit);
    if (!_judging.add(key)) return;
    try {
      final bot = await EngineBot.shared();
      final fen = vm.before.fen;
      final lines = await bot.analyse(fen, depth: 12, multipv: 5);
      if (lines.isEmpty) return;
      final played = lines.where((l) => l.move == vm.move.uci).firstOrNull ??
          (await bot.analyse(fen, depth: 12, searchMove: vm.move.uci)).firstOrNull;
      if (played == null) return;
      final record = classify(vm.before, lines, played, null, Settings(unit: _unit, percentSteps: _percent));
      final hit = (record, played.eval);
      _judged[key] = hit;
      apply(hit);
    } catch (_) {
      // движок недоступен — ход остаётся без вердикта
    } finally {
      _judging.remove(key);
    }
  }

  VarMove _varMove(int anchor, List<VarMove> prefix, Pos pos, NormalMove m, {bool auto = false}) {
    final ucis = [for (final x in prefix) x.move.uci, m.uci];
    final root = _base(anchor).turn;
    final ply = anchor + 1;
    final line = _line(ply, ucis);
    MoveRecord? record;
    String? type;
    if (line != null && prefix.isEmpty) {
      // первый ход ветки сыгран в разобранной позиции — полный вердикт
      final p = game.plies[ply];
      record = classify(pos, p.lines, line, ply > 0 ? game.plies[ply - 1].lines.first.eval : null,
          Settings(unit: _unit, percentSteps: _percent, multipv: (game.engine['multipv'] as num?)?.toInt() ?? 5),
          ply: ply, allLines: p.allLines, continuation: line.pv.skip(1).take(6).toList());
    } else if (line != null) {
      // дальше по линии движка: ход лучший, тип — по остатку линии
      final rest = line.pv.sublist(prefix.length);
      final own = pos.turn == root ? line.eval : line.eval.negate();
      type = moveType(pos, Line(move: m.uci, eval: own, pv: rest), const [], const Settings()).$1;
    }
    return VarMove(
      move: m,
      san: pos.san(m),
      before: pos,
      after: pos.push(m),
      eval: line?.eval,
      root: root,
      record: record,
      moveType: type,
      auto: auto,
      live: line == null,
    );
  }

  /// Engine line of ply [ply] that starts with [ucis].
  Line? _line(int ply, List<String> ucis) {
    if (ply < 0 || ply >= length) return null;
    final p = game.plies[ply];
    for (final ln in [...p.lines, p.played, ...?p.allLines]) {
      final pv = ln.pv.isEmpty ? [ln.move] : ln.pv;
      if (pv.length < ucis.length) continue;
      var ok = true;
      for (var i = 0; i < ucis.length && ok; i++) {
        ok = pv[i] == ucis[i];
      }
      if (ok) return ln.pv.isEmpty ? Line(move: ln.move, eval: ln.eval, pv: [ln.move]) : ln;
    }
    return null;
  }
  void first() => select(-1);
  void last() => select(lastPly);
  bool get canNext => (_idea != null && ideaFrameAt >= 0)
      ? _ideaCanNext
      : _var == null
      ? (errorsOnly ? nextNegative() != null : _ply < lastPly)
      : (_varIndex < _var!.moves.length - 1 ||
          _lineContinuation() != null ||
          (_var!.moves.isNotEmpty && !_var!.moves.last.after.p.isGameOver));
  bool get canPrev {
    if (_idea != null && ideaFrameAt >= 0) return ideaFrameAt > 0;
    return _var != null || (errorsOnly ? prevNegative() != null : _ply > -1);
  }

  void flip() {
    _flipped = !_flipped;
    notifyListeners();
  }

  List<AacPoint>? _aac;
  Object? _aacOf;

  /// AAC after every ply (recomputed when the device analysis brings new
  /// data). Shown when the unit switch is on AAC ([Unit.both]: the moves are
  /// still judged in pawns and WDL together).
  List<AacPoint> get aac {
    if (_aac == null || !identical(_aacOf, game)) {
      _aac = aacOf(game);
      _aacOf = game;
    }
    return _aac!;
  }

  /// The trick of the game move at [ply]: in a lost position, the
  /// winner's moves that let the game slip to a draw after it.
  Trick? trickAt(int ply) => ply >= 0 && ply + 1 < game.plies.length ? trickOf(game.plies[ply + 1]) : null;

  final _worst = <(Side, int), int?>{};

  /// The side's worst move: the largest drop of the expected result (WDL),
  /// after which the game is most often lost. Null when no move dropped it
  /// by 10% or more.
  int? worstPly(Side side) => _worst.putIfAbsent((side, identityHashCode(_analysis)), () {
        int? best;
        var drop = 0.10;
        for (final r in _analysis.records.where((r) => r.side == side)) {
          final d = r.wdl.e1 - r.wdl.ep;
          if (d >= drop) {
            drop = d;
            best = r.ply;
          }
        }
        return best;
      });

  final _kinds = <(int, int), (List<String>, List<String>)>{};

  /// Kinds of move [ply] (what it does) and, for a negative move, the kinds of
  /// the best move it missed.
  (List<String> played, List<String> missed) kindsAt(int ply) =>
      _kinds.putIfAbsent((ply, identityHashCode(game)), () {
        const s = Settings();
        final p = game.plies[ply];
        final board = before[ply];
        final best = p.lines.first;
        final played = playedKinds(board, moves[ply], p.played.pv.isEmpty ? [p.uci] : p.played.pv, p.played.eval,
            Pos.move(best.move), s);
        final missed =
            isNegativeAt(ply) && best.move != p.uci
                ? kindsOf(board, Pos.move(best.move), best.pv, best.eval, s, lines: p.lines)
                : <String>[];
        return (played, missed);
      });

  final _characters = <(int, int), PositionCharacter>{};

  /// Character of the position before move [ply] (trivial / sharp, quiet).
  PositionCharacter characterAt(int ply) {
    final p = game.plies[ply];
    return _characters.putIfAbsent(
        (ply, identityHashCode(game)),
        () => characterOf(Pos.fromFen(p.fenBefore), p.lines, p.allLines, const Settings()));
  }

  bool _percent;

  /// Steps by the percent of the expected result lost (quick settings).
  bool get percentSteps => _percent;

  void setPercentSteps(bool on) {
    if (on == _percent) return;
    _percent = on;
    _analysis = analyzeGame(game, Settings(unit: _unit, percentSteps: _percent), book: book);
    _refresh();
    _updatingData = true;
    notifyListeners();
    _updatingData = false;
  }

  /// Re-runs the Dart analysis in another unit.
  Future<void> setUnit(Unit u) async {
    if (u == _unit || _busy) return;
    _busy = true;
    // без индикатора: пересчёт занимает кадр-два, а полоса сдвигала экран
    await Future<void>.delayed(Duration.zero);
    _analysis = analyzeGame(game, Settings(unit: u, percentSteps: _percent), book: book);
    _unit = u;
    _busy = false;
    _refresh();
    notifyListeners();
  }

  bool _updatingData = false;

  /// True while listeners hear about new engine data (not a navigation):
  /// cards cross-fade instead of sliding.
  bool get updatingData => _updatingData;

  /// New engine data for the same moves (the device analysis went on).
  void updateGame(GameData g) {
    game = g;
    _analysis = analyzeGame(game, Settings(unit: _unit, percentSteps: _percent), book: book);
    _refresh();
    _updatingData = true;
    notifyListeners();
    _updatingData = false;
  }

  /// Derived data after a new analysis.
  void _refresh() {
    _endDone = false; // оценка сдачи зависит от единицы
    _alts.clear();
    // вердикты своих веток — в новой единице
    for (final v in variations) {
      final seq = [for (final m in v.moves) m.move];
      v.moves.clear();
      var pos = _base(v.anchor);
      for (final m in seq) {
        v.moves.add(_varMove(v.anchor, v.moves, pos, m));
        pos = pos.push(m);
      }
    }
    if (_idea != null) _idea = _analysis.ideaAt(_idea!.punishPly);
  }

  // --- idea chain ---

  void selectIdea(Idea? idea) {
    stopChain();
    _idea = idea;
    _lock = null;
    _framesToken++;
    _frames.clear();
    _framesDone = false;
    if (idea != null) {
      _ideaNav = true;
      select(chainPlies(idea).first);
      _ideaNav = false;
      _buildFrames(idea);
    }
    notifyListeners();
  }

  /// Plies to show for an idea. A chain entry j is the owner's position before
  /// move j, i.e. the position after move j−1; then the miss, the error and the
  /// punishing reply.
  List<int> chainPlies(Idea idea) {
    final out = <int>{
      for (final c in idea.chain)
        if (c.present && c.ply >= 1 && c.ply - 1 < length) c.ply - 1,
      if (idea.missPly != null) idea.missPly!,
      idea.punishPly,
      if (punishes(idea)) idea.punishPly + 1,
      // блестящий ход: последствия — следующие ходы партии
      if (idea.kind == 'brilliant')
        for (var p = idea.punishPly + 1; p <= idea.punishPly + 4 && p < length; p++) p,
      if (onlySince(idea) case final p? when p >= 1) p - 1,
      // с чего ошибка началась: предыдущий негативный ход той же стороны
      if (beganWith(idea) case final p? when p >= 1) p - 1,
    }.toList()
      ..sort();
    return out;
  }

  /// [авторское] The move the error grew from: the nearest earlier negative
  /// move of the same side, at most three own moves back, with only
  /// non-negative own moves in between (4. Bb5?! a6 5. Bxc6+ bxc6 6. O-O —
  /// the weakness began with 4. Bb5). Null when there is none.
  int? beganWith(Idea idea) {
    if (idea.kind == 'brilliant') return null;
    for (var p = idea.punishPly - 2; p >= 0 && p >= idea.punishPly - 6; p -= 2) {
      if (isNegativeAt(p)) return p;
    }
    return null;
  }

  /// [авторское] Where the error really began: going back from the error,
  /// the earliest of the erring side's moves from which every move had a
  /// single positive continuation (an only move in a forced chain). Null
  /// when the position before the error itself had more than one.
  int? onlySince(Idea idea) {
    int? since;
    for (var p = idea.punishPly; p >= 0; p -= 2) {
      if (characterAt(p).positive > 1) break;
      since = p;
    }
    return since != null && since < idea.punishPly ? since : null;
  }

  /// Whether the reply to the error really punishes it: a good move of the
  /// opponent. A reply that is itself a mistake is a missed chance, not a
  /// punishment, and is not shown as one.
  bool punishes(Idea idea) {
    final p = idea.punishPly + 1;
    if (idea.kind != 'punishment' || p >= length) return false;
    return const {'best', 'excellent', 'good', 'book', 'forced'}.contains(_analysis.records[p].step);
  }

  /// Chain entry drawn on the board at the selected ply (position after it).
  ChainEntry? chainEntryShown() {
    final idea = _idea;
    if (idea == null) return null;
    for (final e in idea.chain) {
      if (e.ply == _ply + 1) return e;
    }
    return null;
  }

  // --- проигрывание идеи ---
  //
  // [авторское] Идея — заранее построенный список кадров (позиция партии или
  // ход ветки), в таком порядке:
  // 1. партия от начала идеи до ошибки включительно;
  // 2. наказание — лучшая линия соперника после ошибки;
  // 3. лучшее продолжение, упущенное в позиции перед ошибкой.
  // Линии идут, пока у стороны на ходу не будет трёх приемлемых ходов подряд
  // среди лучших (см. [_calm]); дальше анализа их продолжает движок телефона.
  // Пауза оставляет позицию; «далее» и «назад» ходят только по кадрам идеи;
  // проигрывание продолжается с показанного кадра; свой ход выходит из идеи.

  final _frames = <IdeaFrame>[];
  bool _framesDone = false;
  int _framesToken = 0;
  int _playToken = 0;
  bool _playingIdea = false;
  bool _disposed = false;
  bool _ideaNav = false;

  /// Frames of the selected idea built so far (all of them when
  /// [ideaFramesDone]).
  List<IdeaFrame> get ideaFrames => _frames;
  bool get ideaFramesDone => _framesDone;

  /// The frame shown now, or −1 when the board is elsewhere.
  int get ideaFrameAt {
    for (var i = 0; i < _frames.length; i++) {
      final f = _frames[i];
      if (f.variation == null ? (_var == null && _ply == f.ply) : (identical(_var, f.variation) && _varIndex == f.index)) {
        return i;
      }
    }
    return -1;
  }

  /// What is being shown: the game, the punishment or the better line.
  String? get ideaPhase {
    final i = ideaFrameAt;
    return i < 0 ? null : _frames[i].phase;
  }

  /// Builds the frames of [idea]: the game part at once, the lines as the
  /// engine gives them.
  Future<void> _buildFrames(Idea idea) async {
    final token = ++_framesToken;
    _frames.clear();
    _framesDone = false;
    final k = idea.punishPly;
    final brilliant = idea.kind == 'brilliant';
    final first = chainPlies(idea).reduce(math.min);
    final lastGame = brilliant ? k - 1 : k;
    for (var p = first; p <= lastGame; p++) {
      _frames.add(IdeaFrame(ply: p, phase: 'game'));
    }
    notifyListeners();
    final mover = before[k].turn;
    // наказание: линия соперника после ошибки
    if (!brilliant && k + 1 < length && game.plies[k + 1].lines.first.pv.isNotEmpty) {
      final v = await _ideaBranch(k, game.plies[k + 1].lines.first.pv, mover, token);
      if (token != _framesToken) return;
      if (v != null) {
        for (var i = 0; i < v.moves.length; i++) {
          _frames.add(IdeaFrame(variation: v, index: i, phase: 'punishment'));
        }
        notifyListeners();
      }
    }
    // лучшее продолжение (у brilliant — его линия), с позиции перед ошибкой
    final p = game.plies[k];
    final better = brilliant ? p.played.pv : p.lines.first.pv;
    if (better.isNotEmpty && (brilliant || better.first != p.uci)) {
      final v = await _ideaBranch(k - 1, better, mover.opposite, token);
      if (token != _framesToken) return;
      if (v != null) {
        for (var i = 0; i < v.moves.length; i++) {
          _frames.add(IdeaFrame(variation: v, index: i, phase: brilliant ? 'brilliant' : 'better'));
        }
      }
    }
    // у brilliant после его линии — партия: как он сработал
    if (brilliant) {
      for (var q = k; q <= math.min(k + 4, length - 1); q++) {
        _frames.add(IdeaFrame(ply: q, phase: 'game'));
      }
    }
    _framesDone = true;
    notifyListeners();
  }

  /// The branch of a line of the idea after main-line ply [anchor]: [pv]
  /// (analysed, blue), then the device engine (grey), until [stopSide] is
  /// calm (or 30 plies). Built without being selected.
  Future<Variation?> _ideaBranch(int anchor, List<String> pv, Side stopSide, int token) async {
    var pos = _base(anchor);
    final v = Variation(anchor);
    var i = 0;
    while (v.moves.length < 30 && !pos.p.isGameOver) {
      if (pos.turn == stopSide && v.moves.isNotEmpty && await _calm(pos)) break;
      if (token != _framesToken || _disposed) return null;
      NormalMove? m;
      if (i < pv.length) {
        m = Pos.move(pv[i]);
        if (!pos.isLegal(m)) m = null;
      }
      if (m != null) {
        v.moves.add(_varMove(anchor, v.moves, pos, m, auto: true));
      } else {
        final live = await _bestLine(pos);
        if (token != _framesToken || _disposed) return null;
        if (live == null) break;
        m = Pos.move(live.move);
        if (!pos.isLegal(m)) break;
        final root = _base(anchor).turn;
        v.moves.add(VarMove(
          move: m,
          san: pos.san(m),
          before: pos,
          after: pos.push(m),
          eval: pos.turn == root ? live.eval : live.eval.negate(),
          root: root,
          auto: true,
          live: true,
        ));
      }
      i++;
      pos = pos.push(m);
    }
    if (v.moves.isEmpty) return null;
    // та же линия уже есть веткой — берётся она
    for (final x in variationsAt(anchor)) {
      if (x.moves.length == v.moves.length &&
          [for (var j = 0; j < v.moves.length; j++) x.moves[j].move == v.moves[j].move].every((e) => e)) {
        return x;
      }
    }
    variations.add(v);
    return v;
  }

  void _showFrame(int i) {
    if (i < 0 || i >= _frames.length) return;
    final f = _frames[i];
    _ideaNav = true;
    try {
      if (f.variation == null) {
        select(f.ply!);
      } else {
        selectVar(f.variation!, f.index);
      }
    } finally {
      _ideaNav = false;
    }
  }

  /// Within an idea "next" and "back" move through its frames only.
  bool _ideaStep(int d) {
    if (_idea == null || _frames.isEmpty) return false;
    final at = ideaFrameAt;
    if (at < 0) return false;
    final to = at + d;
    if (to >= 0 && to < _frames.length) _showFrame(to);
    return true;
  }

  bool get _ideaCanNext {
    final at = ideaFrameAt;
    return at >= 0 && at + 1 < _frames.length;
  }

  /// Back to the idea's first frame.
  void restartIdea() {
    stopChain();
    _showFrame(0);
  }

  /// Plays the idea from the frame shown (from its start when the board is
  /// elsewhere or at the end), one frame per [prefs.ideaStepMs].
  Future<void> playChain() async {
    if (_idea == null || _frames.isEmpty) return;
    stopChain();
    final token = ++_playToken;
    _playingIdea = true;
    notifyListeners();
    try {
      var at = ideaFrameAt;
      if (at < 0 || (at >= _frames.length - 1 && _framesDone)) {
        at = 0;
        _showFrame(0);
      }
      while (true) {
        await Future<void>.delayed(Duration(milliseconds: prefs.ideaStepMs));
        if (token != _playToken || _disposed) return;
        // кадры линий ещё считаются — подождать их
        while (at + 1 >= _frames.length && !_framesDone) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          if (token != _playToken || _disposed) return;
        }
        if (at + 1 >= _frames.length) break;
        at++;
        _showFrame(at);
      }
    } finally {
      if (token == _playToken) {
        _playingIdea = false;
        notifyListeners();
      }
    }
  }

  /// [авторское] The line of an idea stops where the side to move is calm:
  /// three positive moves (neutral ones included: the category kept, at most
  /// 0.3 pawns lost to the best), or two positive moves and two inaccuracies
  /// close to neutral (the category kept, at most 0.5 pawns lost) — two such
  /// inaccuracies stand in for one positive move.
  Future<bool> _calm(Pos pos) async {
    final (positive, nearNeutral) = await _choices(pos);
    return positive >= 3 || (positive >= 2 && nearNeutral >= 2);
  }

  final _choicesCache = <String, (int, int)>{};

  /// The positive moves of the side to move in [pos] and its inaccuracies
  /// close to neutral (see [_calm]), by the device engine: depth 12, five
  /// lines.
  Future<(int, int)> _choices(Pos pos) async {
    final key = pos.fen;
    if (_choicesCache[key] case final c?) return c;
    try {
      final bot = await EngineBot.shared();
      final lines = await bot.analyse(pos.fen, depth: 12, multipv: 5);
      if (lines.isEmpty) return (3, 0);
      const s = Settings();
      final best = lines.first.eval.pawns(s);
      var positive = 0, near = 0;
      for (final l in lines) {
        final v = l.eval.pawns(s);
        if (category(v, s.pawns) < category(best, s.pawns)) continue;
        final loss = best - v;
        if (loss <= positiveLoss) {
          positive++;
        } else if (loss <= 0.5) {
          near++;
        }
      }
      // все ходы позиции позитивны, но их меньше трёх — тоже спокойно
      if (lines.length < 3 && positive == lines.length) positive = 3;
      return _choicesCache[key] = (positive, near);
    } catch (_) {
      return (3, 0);
    }
  }

  Future<Line?> _bestLine(Pos pos) async {
    final key = pos.fen;
    if (_liveLines[key] case final l?) return l;
    try {
      final bot = await EngineBot.shared();
      final lines = await bot.analyse(pos.fen, depth: 14, multipv: 1);
      if (lines.isEmpty) return null;
      return _liveLines[key] = lines.first;
    } catch (_) {
      return null;
    }
  }

  void stopChain() {
    _playToken++;
    _playingIdea = false;
    _player?.cancel();
    _player = null;
    notifyListeners();
  }

  // --- user arrows ---

  bool _pen = false;
  final _userArrows = <Object, List<BoardArrow>>{};
  final _userMarks = <Object, List<BoardMark>>{};

  /// User marks of the shown position.
  List<BoardMark> get marksShown => _userMarks[positionKey] ?? const [];

  /// Marks the square, or unmarks it when tapped again.
  void toggleMark(Square s) {
    final list = _userMarks.putIfAbsent(positionKey, () => []);
    final m = BoardMark(s, prefs.userMarkColor);
    if (!list.remove(m)) list.add(m);
    notifyListeners();
  }

  /// Pen mode: dragging on the board draws arrows instead of moving pieces.
  bool get pen => _pen;

  void togglePen() {
    _pen = !_pen;
    notifyListeners();
  }

  /// User arrows of the shown position.
  List<BoardArrow> get arrowsShown => _userArrows[positionKey] ?? const [];

  bool get hasArrows => _userArrows.values.any((l) => l.isNotEmpty) || _userMarks.values.any((l) => l.isNotEmpty);

  /// Adds the arrow, or removes it when drawn again.
  void toggleArrow(Square from, Square to) {
    final list = _userArrows.putIfAbsent(positionKey, () => []);
    final a = BoardArrow(from, to, prefs.userArrowColor, sketched: true);
    if (!list.remove(a)) list.add(a);
    notifyListeners();
  }

  void clearArrows() {
    _userArrows.clear();
    _userMarks.clear();
    notifyListeners();
  }

  // --- locks ---

  List<LineOfAttack> linesAt(int ply) {
    final pos = ply < 0 ? before[0] : after[math.min(ply, length - 1)];
    return [...findLines(pos, Side.white), ...findLines(pos, Side.black)];
  }

  void selectLock(LineOfAttack? line) {
    if (line != null) {
      _player?.cancel();
      _player = null;
      _idea = null;
    }
    _lock = line == null ? null : SelectedLock(recordPly, line.slider, line.target);
    notifyListeners();
  }

  List<LockPoint> lockTimelineFor(SelectedLock lock) =>
      lockTimeline(before, after, moves, lock.anchor, lock.slider, lock.target);

  /// The selected line as it stands at the current ply, if it is followed there.
  LineOfAttack? lockShown() {
    final lock = _lock;
    if (lock == null) return null;
    for (final p in lockTimelineFor(lock)) {
      if (p.ply == _ply) return p.line;
    }
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _playToken++;
    _player?.cancel();
    super.dispose();
  }
}

/// One frame of an idea's playback: a game position (after [ply]) or a move
/// of a branch, with the part of the idea it belongs to.
class IdeaFrame {
  const IdeaFrame({this.ply, this.variation, this.index = 0, required this.phase});

  final int? ply;
  final Variation? variation;
  final int index;

  /// 'game', 'punishment', 'better' or 'brilliant'.
  final String phase;
}
