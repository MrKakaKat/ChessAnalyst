/// A game against the engine: setup, moves, the engine's replies, the result.
///
/// Friendly mode adds takebacks, the evaluation after every move and the
/// engine's best continuation (as an arrow and a line).
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../analysis/pos.dart';
import '../analysis/eval.dart';
import '../engine/bot.dart';
import '../engine/rated_play.dart';
import 'prefs.dart';
import 'widgets/arrows.dart';

/// [blunder]: friendly game, the player's move is a serious blunder — the
/// game waits: take it back, or play on and meet the engine's reply.
enum PlayStatus { setup, starting, playing, thinking, blunder, over, failed }

class PlayController extends ChangeNotifier {
  PlayStatus _status = PlayStatus.setup;
  BotLevel level = botLevels[2];

  /// Play at a rating instead of a level (rated_play.dart); null: by level.
  int? rating;

  /// The rated engine of the current game: its running accuracy.
  RatedPlay? rated;

  /// Friendly game: the engine's reply that punishes the player's blunder,
  /// and how much the blunder lost (pawns).
  NormalMove? threat;
  double blunderLoss = 0;
  Side? chosenSide = Side.white; // null — случайный цвет
  bool friendly = false;
  Side player = Side.white;

  /// Positions: the start and after every move.
  final positions = <Pos>[Pos(Chess.initial)];
  final moves = <NormalMove>[];
  final sans = <String>[];
  String? result; // 1-0, 0-1, 1/2-1/2
  String? reason;
  String? error;

  /// Shown position (index into [positions]); null — the live one.
  int? _view;

  /// Friendly mode: evaluation of the live position.
  EngineEval? eval;
  int _evalAt = -1;

  EngineBot? _bot;
  bool _disposed = false;
  final _arrows = <int, List<BoardArrow>>{};

  PlayStatus get status => _status;
  Pos get live => positions.last;
  int get shownIndex => _view ?? positions.length - 1;
  Pos get position => positions[shownIndex];
  bool get browsing => _view != null;
  bool get myTurn => _status == PlayStatus.playing && live.turn == player && !browsing;
  NormalMove? get lastMove => shownIndex == 0 ? null : moves[shownIndex - 1];

  /// Evaluation of the shown position, if it is the evaluated one.
  EngineEval? get shownEval => _evalAt == shownIndex ? eval : null;

  void setLevel(BotLevel l) {
    level = l;
    notifyListeners();
  }

  void setRating(int? r) {
    rating = r;
    notifyListeners();
  }

  void setSide(Side? s) {
    chosenSide = s;
    notifyListeners();
  }

  void setFriendly(bool v) {
    friendly = v;
    notifyListeners();
  }

  Future<void> start() async {
    player = chosenSide ?? (math.Random().nextBool() ? Side.white : Side.black);
    positions
      ..clear()
      ..add(Pos(Chess.initial));
    moves.clear();
    sans.clear();
    _arrows.clear();
    _view = null;
    eval = null;
    _evalAt = -1;
    threat = null;
    rated = rating == null ? null : RatedPlay(rating!);
    result = reason = error = null;
    _set(PlayStatus.starting);
    try {
      _bot ??= await EngineBot.shared();
      await _bot!.newGame();
    } catch (e) {
      error = '$e';
      _set(PlayStatus.failed);
      return;
    }
    _set(PlayStatus.playing);
    if (live.turn != player) {
      await _engineMove();
    } else {
      _evaluate();
    }
  }

  /// The player's move from the board.
  Future<void> play(NormalMove m) async {
    if (!myTurn) return;
    m = _normalize(m);
    if (!live.isLegal(m)) return;
    final before = live;
    _push(m);
    if (_checkEnd()) return;
    // [авторское] дружеская партия: весомый зевок — партия ждёт; видно, чем
    // ответит движок (и этот ответ он не пропустит)
    if (friendly && await _blunderCheck(before)) return;
    await _engineMove();
  }

  /// Whether the player's last move (from [before]) is a serious blunder:
  /// it loses two pawns or more, or lets the engine mate. Sets [threat].
  Future<bool> _blunderCheck(Pos before) async {
    _set(PlayStatus.thinking);
    try {
      final bot = _bot!;
      double pawns(Line l) {
        final e = l.eval;
        if (e.mate != null) return e.mate! > 0 ? 30 : -30;
        return e.cp! / 100;
      }

      final was = await bot.analyse(before.fen, depth: 12, multipv: 1);
      final now = await bot.analyse(live.fen, depth: 12, multipv: 1);
      if (_disposed || was.isEmpty || now.isEmpty) return false;
      final v0 = pawns(was.first), v1 = -pawns(now.first);
      final mated = now.first.eval.mate != null && now.first.eval.mate! > 0 && (was.first.eval.mate ?? 1) > 0;
      if ((v0 - v1 >= 2.0 && v1 < 3) || (mated && v0 > -25)) {
        threat = NormalMove.fromUci(now.first.move);
        blunderLoss = mated ? 99 : v0 - v1;
        _set(PlayStatus.blunder);
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Friendly game after a blunder: the engine plays its punishing reply.
  Future<void> playOn() async {
    if (_status != PlayStatus.blunder) return;
    final m = threat;
    threat = null;
    if (m == null || !live.isLegal(m)) {
      _set(PlayStatus.playing);
      return _engineMove();
    }
    rated?.choose([Line(move: m.uci, eval: const Eval(cp: 0, wdl: (0, 1000, 0)), pv: [m.uci])]);
    _push(m);
    if (!_checkEnd()) {
      _set(PlayStatus.playing);
      _evaluate();
    }
  }

  Future<void> _engineMove() async {
    _set(PlayStatus.thinking);
    final watch = Stopwatch()..start();
    try {
      // по рейтингу: из лучших ходов — тот, что держит точность движка у
      // точности выбранного рейтинга
      final r = rated;
      final uci = r == null
          ? await _bot!.bestMove(live.fen, level)
          : r.choose(await _bot!.analyse(live.fen, depth: 12, multipv: 8)).move;
      // [авторское] ответ не раньше выбранной задержки: ход виден и не
      // мелькает сразу за своим
      final wait = prefs.playReplyMs - watch.elapsedMilliseconds;
      if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
      if (_disposed || _status != PlayStatus.thinking) return;
      _push(NormalMove.fromUci(uci));
    } catch (e) {
      error = '$e';
      _set(PlayStatus.failed);
      return;
    }
    if (!_checkEnd()) {
      _set(PlayStatus.playing);
      _evaluate();
    }
  }

  /// Friendly mode: evaluation and best line of the live position.
  Future<void> _evaluate() async {
    if (!friendly || _bot == null) return;
    final at = positions.length - 1;
    try {
      final e = await _bot!.evaluate(live.fen);
      if (_disposed || positions.length - 1 != at) return;
      eval = e;
      _evalAt = at;
      notifyListeners();
    } catch (_) {}
  }

  /// Friendly mode: takes back the player's last move (and the engine's reply).
  void takeback() {
    if (!friendly || _status == PlayStatus.thinking || _status == PlayStatus.starting) return;
    var n = live.turn == player ? 2 : 1;
    if (_status == PlayStatus.over) n = live.turn == player ? 2 : 1;
    n = math.min(n, moves.length);
    // нельзя вернуть ход до первого хода игрока
    if (moves.length - n < (player == Side.white ? 0 : 1)) return;
    for (var i = 0; i < n; i++) {
      // ход движка снят — и его точность тоже
      if (positions[positions.length - 2].turn != player) rated?.undo();
      moves.removeLast();
      sans.removeLast();
      positions.removeLast();
    }
    result = reason = null;
    threat = null;
    _view = null;
    _status = PlayStatus.playing;
    notifyListeners();
    _evaluate();
  }

  bool get canTakeback =>
      friendly && moves.length >= (player == Side.white ? 1 : 2) && _status != PlayStatus.thinking;

  // --- browsing past positions ---

  void view(int i) {
    i = i.clamp(0, positions.length - 1);
    _view = i == positions.length - 1 ? null : i;
    notifyListeners();
  }

  void back() => view(shownIndex - 1);
  void forward() => view(shownIndex + 1);
  void toStart() => view(0);
  void toLive() => view(positions.length - 1);

  // --- user arrows ---

  List<BoardArrow> get arrowsShown => _arrows[shownIndex] ?? const [];
  final _marks = <int, List<BoardMark>>{};
  List<BoardMark> get marksShown => _marks[shownIndex] ?? const [];

  void toggleMark(Square s) {
    final list = _marks.putIfAbsent(shownIndex, () => []);
    final m = BoardMark(s, prefs.userMarkColor);
    if (!list.remove(m)) list.add(m);
    notifyListeners();
  }

  void toggleArrow(Square from, Square to) {
    final list = _arrows.putIfAbsent(shownIndex, () => []);
    final a = BoardArrow(from, to, prefs.userArrowColor, sketched: true);
    if (!list.remove(a)) list.add(a);
    notifyListeners();
  }

  void resign() {
    if (_status != PlayStatus.playing && _status != PlayStatus.thinking) return;
    result = player == Side.white ? '0-1' : '1-0';
    reason = 'You resigned';
    _set(PlayStatus.over);
  }

  void newGame() {
    _view = null;
    _set(PlayStatus.setup);
  }

  void _push(NormalMove m) {
    sans.add(live.san(m));
    moves.add(m);
    positions.add(live.push(m));
    notifyListeners();
  }

  bool _checkEnd() {
    final p = live.p;
    if (p.isCheckmate) {
      result = p.turn == Side.white ? '0-1' : '1-0';
      reason = 'Checkmate';
    } else if (p.isStalemate) {
      result = '1/2-1/2';
      reason = 'Stalemate';
    } else if (p.isInsufficientMaterial) {
      result = '1/2-1/2';
      reason = 'Insufficient material';
    } else if (p.halfmoves >= 100) {
      result = '1/2-1/2';
      reason = 'Fifty-move rule';
    } else if (_threefold()) {
      result = '1/2-1/2';
      reason = 'Threefold repetition';
    } else {
      return false;
    }
    _set(PlayStatus.over);
    return true;
  }

  /// The current position has occurred three times.
  bool _threefold() {
    String key(Pos p) => p.fen.split(' ').take(4).join(' ');
    final now = key(live);
    return positions.where((p) => key(p) == now).length >= 3;
  }

  /// King onto its rook (chessground) → e1g1 / e1c1.
  NormalMove _normalize(NormalMove m) {
    final piece = live.pieceAt(m.from);
    final target = live.pieceAt(m.to);
    if (piece?.role == Role.king && target != null && target.color == piece!.color && target.role == Role.rook) {
      final file = m.to.file > m.from.file ? File.g : File.c;
      return NormalMove(from: m.from, to: Square.fromCoords(file, m.from.rank));
    }
    return m;
  }

  void _set(PlayStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true; // движок общий — остаётся для анализа
    super.dispose();
  }
}
