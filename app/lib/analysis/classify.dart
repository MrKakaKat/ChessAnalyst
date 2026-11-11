/// Классификация хода (разделы 6–7 концепции; chessanalyst/classify.py).
///
/// E0 — оценка после прошлого хода игрока, E1 — лучший ход, Ep — сыгранный.
/// G = E1 − E0, D = Ep − E0, L = E1 − Ep. Порядок: blunder → mistake →
/// лучший → отличный/хороший → laxity → неточность.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import 'eval.dart';
import 'features.dart' as features;
import 'pos.dart';
import 'settings.dart';

const _tol = 1e-9;
const forcedStep = 'forced';
const bookStep = 'book';
const steps = ['best', 'excellent', 'good', 'neutral', 'inaccuracy', 'pass', 'laxity', 'mistake', 'blunder'];

class Values {
  const Values(this.e0, this.e1, this.ep);

  final double e0, e1, ep;
  double get g => e1 - e0;
  double get d => ep - e0;
  double get l => e1 - ep;

  /// Падение от базы; при G < 0 база — E1 (сильный ход соперника не вина игрока).
  double get drop => ep - math.min(e0, e1);
}

class BestMove {
  const BestMove({
    required this.uci,
    required this.san,
    required this.eval,
    required this.type,
    required this.subtypes,
    required this.onlyMove,
    required this.brilliant,
  });

  final String uci, san, eval, type;
  final List<String> subtypes;
  final bool onlyMove, brilliant;
}

class MoveRecord {
  MoveRecord({
    required this.ply,
    required this.side,
    required this.san,
    required this.uci,
    required this.fenBefore,
    required this.e0,
    required this.e1,
    required this.ep,
    required this.pawns,
    required this.wdl,
    required this.catE0,
    required this.catE1,
    required this.catEp,
    required this.step,
    required this.subtype,
    required this.moveType,
    required this.typeSubtypes,
    required this.flags,
    required this.bestMoves,
    required this.nearBestMoves,
    required this.stage,
    required this.decidedBy,
    required this.unitSteps,
    this.opening,
    this.engineStep,
  });

  final int ply;
  final Side side;
  final String san, uci, fenBefore;
  final Eval? e0;
  final Eval e1, ep;
  final Values pawns, wdl;
  final String? catE0;
  final String catE1, catEp;
  final String step;
  /// Not final: [desperado] corrects it after the whole game is judged.
  String? subtype;
  final String moveType;
  final List<String> typeSubtypes;
  final List<String> flags;
  final List<BestMove> bestMoves, nearBestMoves;
  final String stage;
  final Unit decidedBy;
  final Map<Unit, String> unitSteps;

  /// Opening name when the move is a book move.
  final String? opening;

  /// Engine verdict replaced by "book".
  final String? engineStep;

  Values valuesFor(Unit u) => u == Unit.pawns ? pawns : wdl;
}

class _UnitVerdict {
  _UnitVerdict(this.unit, this.step, this.flags, this.zoneA, this.zoneB, this.playedZone, this.onlyMove,
      this.c0, this.c1, this.cp);

  final Unit unit;
  final String step;
  final List<String> flags;
  final List<Line> zoneA, zoneB;
  final String? playedZone;
  final bool onlyMove;
  final int? c0;
  final int c1, cp;
}

/// The step of a move by the percent of the expected result it loses
/// ([Settings.percentSteps]); [nearBest]: one of the best lines.
String percentStep(double lossPercent, bool nearBest) {
  final l = lossPercent;
  if (l <= 1) return nearBest ? 'best' : 'neutral';
  if (l <= 2) return 'excellent';
  if (l <= 5) return 'good';
  if (l <= 10) return 'inaccuracy';
  if (l <= 15) return 'laxity';
  if (l <= 25) return 'mistake';
  return 'blunder';
}

String? _zone(Eval best, Eval cand, double l, double eps1, double eps2) {
  if (best.mate != null || cand.mate != null) return best.structurallyEqual(cand) ? 'A' : null;
  if (best.structurallyEqual(cand) || l <= eps1 + _tol) return 'A';
  if (l <= eps2 + _tol) return 'B';
  return null;
}

_UnitVerdict _verdict(Unit unit, Eval? e0, Eval e1, Eval ep, List<Line> lines, Line played, int nLegal,
    Settings s) {
  final p = s.paramsFor(unit);
  final base = e0 ?? e1;
  final v = Values(base.value(unit, s), e1.value(unit, s), ep.value(unit, s));

  final c0 = e0 != null ? category(v.e0, p) : null;
  final c1 = category(v.e1, p);
  final cp = category(v.ep, p);

  String? zoneOf(Line line) => _zone(e1, line.eval, v.e1 - line.eval.value(unit, s), p.eps1, p.eps2);

  final zoneA = lines.where((ln) => zoneOf(ln) == 'A').toList();
  final zoneB = lines.where((ln) => zoneOf(ln) == 'B').toList();
  final playedZone = zoneOf(played);
  final matedNow = ep.mate != null && ep.mate! < 0 && !(e1.mate != null && e1.mate! < 0);

  final flags = <String>[];
  String step;
  if ((c1 == win && cp <= equal) || (c1 == loss && matedNow) || (c1 - cp >= 2)) {
    step = 'blunder';
  } else if (e1.mate != null && e1.mate! > 0 && ep.mate != null && ep.mate! > e1.mate!) {
    step = 'excellent'; // более медленный мат
  } else if (v.l > p.mistakeLoss + _tol) {
    // [авторское] по потере L: > 1 пешки — ошибка, > 0,5 — слабость (laxity),
    // > 0,1 — неточность, колебания до 0,1 — нейтральный ход
    step = 'mistake';
  } else if (playedZone == 'A') {
    step = 'best';
  } else if (v.g >= p.gSignificant && v.d / v.g >= s.excellentRatio) {
    step = 'excellent';
  } else if (v.g >= p.gSignificant && v.d / v.g >= s.goodRatio) {
    step = 'good';
  } else if (v.l > p.laxityLoss + _tol) {
    step = 'laxity';
  } else if (v.l > p.inaccuracyLoss + _tol) {
    step = 'inaccuracy';
  } else {
    step = 'neutral';
  }
  if (s.percentSteps && !(e1.mate != null && e1.mate! > 0 && ep.mate != null && ep.mate! > e1.mate!)) {
    // [авторское] шаг — только по процентам ожидаемого результата, без
    // примеси потери в пешках: в решённой позиции (−7 → −6 или +6 → +5)
    // результат не меняется, и ход не ошибка; зевок по категориям
    // (мат, потерянный выигрыш) остаётся зевком
    final byPercent = percentStep(math.max(0.0, e1.expected - ep.expected) * 100, playedZone != null);
    step = step == 'blunder' ? 'blunder' : byPercent;
  }
  if (playedZone == 'B') flags.add('near_best');

  if (c0 != null) {
    final gift = c1 > c0 || v.g >= p.passStep;
    if (gift && v.d / v.g < s.passRatio) {
      flags.add('pass');
      // и не ошибка, если своя позиция не стала хуже, чем до подарка соперника
      if (step == 'inaccuracy' ||
          step == 'neutral' ||
          ((step == 'laxity' || step == 'mistake') && v.d >= -p.laxThreshold)) {
        step = 'pass';
      }
    }
  }

  if ((playedZone == 'A' || playedZone == 'B') && v.g.abs() <= p.neutralEps) flags.add('neutral');

  // Only move: единственный ход, улучшающий позицию (над E0 на значимое G)
  var onlyMove = false;
  if (e0 != null && zoneA.length == 1 && nLegal > 1) {
    final improving = lines.where((ln) => ln.eval.value(unit, s) - v.e0 >= p.gSignificant).toList();
    onlyMove = improving.length == 1 && identical(improving.first, zoneA.first);
  }
  // удержание: единственный ход, сохраняющий категорию, — все остальные её роняют
  if (!onlyMove && zoneA.length == 1 && lines.length >= 2 && nLegal > 1) {
    onlyMove = lines.every((ln) => identical(ln, zoneA.first) || category(ln.eval.value(unit, s), p) < c1);
  }
  return _UnitVerdict(unit, step, flags, zoneA, zoneB, playedZone, onlyMove, c0, c1, cp);
}

bool _keepsExtreme(Eval e1, List<Line> lines, Unit unit, Settings s, double share) {
  final p = s.paramsFor(unit);
  final c1 = category(e1.value(unit, s), p);
  if ((c1 != win && c1 != loss) || lines.isEmpty) return false;
  final keep = lines.where((ln) => category(ln.eval.value(unit, s), p) == c1).length;
  return keep / lines.length >= share - _tol;
}

bool _isTrivial(Eval e1, List<Line> lines, List<Line>? allLines, int nLegal, Unit unit, Settings s) {
  if (allLines != null && allLines.length >= nLegal) return _keepsExtreme(e1, allLines, unit, s, s.trivialShare);
  return lines.length >= math.min(s.multipv, nLegal) && _keepsExtreme(e1, lines, unit, s, 1.0);
}

(String, List<String>) moveType(Pos board, Line line, List<Line> lines, Settings s) {
  final move = Pos.move(line.move);
  var tactical = false;
  if (features.forcingCount(board, line.pv, s.tacticalWindowPlies) >= s.tacticalMinForcing) {
    final quiet = lines.where((ln) => ln.move != line.move && !features.isForcing(board, Pos.move(ln.move))).toList();
    if (quiet.isEmpty) {
      tactical = true;
    } else {
      final bestQuiet = quiet.first.eval;
      tactical = line.eval.mate != null ||
          bestQuiet.mate != null ||
          (line.eval.pawns(s) - bestQuiet.pawns(s)).abs() >= s.pawns.gSignificant ||
          (line.eval.expected - bestQuiet.expected).abs() >= s.wdl.gSignificant;
    }
  }
  // основа (tactical / positional) и направления: attacking, counterattacking, defensive
  const names = {'attack': 'attacking', 'counterattack': 'counterattacking', 'defense': 'defensive'};
  final sub = features.positionalSubtypes(board, move, s);
  return (tactical ? 'tactical' : 'positional', [for (final x in sub) if (names[x] != null) names[x]!]);
}

/// Working sacrifice. Material is checked on the main line and, for the played
/// move, on the game itself ([continuation]): the engine often shows the
/// sacrifice is better declined, while the acceptance is only seen in the game.
bool _isBrilliant(Pos board, Line line, Settings s, [List<String>? continuation]) {
  final move = Pos.move(line.move);
  if (line.eval.value(Unit.pawns, s) <= -s.pawns.b1) return false;
  if (!features.leavesMaterialEnPrise(board, move)) return false;
  if (features.isSacrificeLine(board, line.pv, s)) return true;
  return continuation != null &&
      continuation.isNotEmpty &&
      features.isSacrificeLine(board, [line.move, ...continuation], s);
}

MoveRecord classify(Pos board, List<Line> lines, Line played, Eval? prevRoot, Settings s,
    {int ply = 0, List<Line>? allLines, String? opening, List<String>? continuation}) {
  final move = Pos.move(played.move);
  final nLegal = board.legalCount;

  final e1 = lines.first.eval;
  final ep = played.eval;
  final e0 = prevRoot != null ? previousAfterMoveToRoot(prevRoot.negate()) : null;
  final base = e0 ?? e1;

  final units = s.units;
  final verdicts = {for (final u in units) u: _verdict(u, e0, e1, ep, lines, played, nLegal, s)};
  // Более строгий вердикт; при равенстве — WDL.
  final chosen = verdicts.values.reduce((a, b) {
    final ka = steps.indexOf(a.step), kb = steps.indexOf(b.step);
    if (ka != kb) return ka > kb ? a : b;
    return b.unit == Unit.wdl ? b : a;
  });

  // Зоны при "both" — пересечение: лучший ход лучший в обеих единицах.
  String? zone(String m) {
    const rank = {'A': 0, 'B': 1, null: 2};
    String? worst;
    var first = true;
    for (final vd in verdicts.values) {
      final z = vd.zoneA.any((l) => l.move == m)
          ? 'A'
          : vd.zoneB.any((l) => l.move == m)
              ? 'B'
              : null;
      if (first || rank[z]! > rank[worst]!) worst = z;
      first = false;
    }
    return worst;
  }

  final zoneA = lines.where((ln) => zone(ln.move) == 'A').toList();
  final zoneB = lines.where((ln) => zone(ln.move) == 'B').toList();
  final playedZone = zone(played.move);
  final onlyMove = verdicts.values.every((vd) => vd.onlyMove) && zoneA.length == 1;

  var flags = List<String>.of(chosen.flags);
  if (units.every((u) => _isTrivial(e1, lines, allLines, nLegal, u, s))) flags.add('trivial');
  if (ply < s.theoryPlies) flags.add('theory');

  var step = chosen.step;
  if (step == 'blunder' && flags.contains('trivial') && chosen.c1 == loss && chosen.cp == loss) {
    step = 'laxity';
    flags.add('hopeless');
  }

  final forced = nLegal == 1;
  if (forced) {
    step = forcedStep;
    flags = flags.where((f) => f == 'trivial' || f == 'theory').toList();
  }

  // Book move: theory instead of the engine verdict (early gambits are not inaccuracies).
  String? engineStep;
  if (opening != null) {
    engineStep = step;
    step = bookStep;
    flags = ['book'];
  }

  String? subtype;
  final (bestType, _) = moveType(board, lines.first, lines, s);
  if (chosen.step == 'inaccuracy' &&
      bestType == 'tactical' &&
      features.isForcing(board, Pos.move(lines.first.move)) &&
      !features.isForcing(board, move)) {
    subtype = 'underpress';
  }
  if (playedZone == 'A' && !forced && opening == null) {
    if (_isBrilliant(board, played, s, continuation)) {
      subtype = 'brilliant';
    } else if (onlyMove) {
      // тактический only — за ходом длинная форсировка; иначе лёгкий
      // взятие крупной фигуры с выигрышем материала очевидно — лёгкий only
      final deep = features.forcingCount(board, played.pv, s.onlyWindowPlies) > s.onlyMinForcing &&
          !features.obviousCapture(board, move);
      subtype = deep ? 'only_move' : 'only_light';
    }
  }

  final (mtype, msub) = moveType(board, played, lines, s);

  BestMove describe(Line ln) {
    final (t, sub) = moveType(board, ln, lines, s);
    return BestMove(
      uci: ln.move,
      san: board.san(Pos.move(ln.move)),
      eval: ln.eval.toString(),
      type: t,
      subtypes: sub,
      onlyMove: onlyMove && identical(ln, zoneA.first),
      brilliant: _isBrilliant(board, ln, s),
    );
  }

  return MoveRecord(
    ply: ply,
    side: board.turn,
    san: board.san(move),
    uci: played.move,
    fenBefore: board.fen,
    e0: e0,
    e1: e1,
    ep: ep,
    pawns: Values(base.pawns(s), e1.pawns(s), ep.pawns(s)),
    wdl: Values(base.expected, e1.expected, ep.expected),
    catE0: chosen.c0 != null ? categories[chosen.c0!] : null,
    catE1: categories[chosen.c1],
    catEp: categories[chosen.cp],
    step: step,
    subtype: subtype,
    moveType: mtype,
    typeSubtypes: msub,
    flags: flags,
    bestMoves: zoneA.map(describe).toList(),
    nearBestMoves: zoneB.map(describe).toList(),
    stage: features.stage(board, s),
    decidedBy: chosen.unit,
    unitSteps: {for (final e in verdicts.entries) e.key: forced ? forcedStep : e.value.step},
    opening: opening,
    engineStep: engineStep,
  );
}
