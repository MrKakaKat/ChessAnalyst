/// Оценки и их нормализация (chessanalyst/evals.py).
library;

import 'dart:math' as math;

import 'settings.dart';

class Eval {
  const Eval({this.cp, this.mate, required this.wdl})
      : assert((cp == null) != (mate == null)),
        assert(mate != 0);

  Map<String, dynamic> toJson() => {'cp': cp, 'mate': mate, 'wdl': [wdl.$1, wdl.$2, wdl.$3]};

  factory Eval.fromJson(Map<String, dynamic> j) {
    final w = (j['wdl'] as List).cast<int>();
    return Eval(cp: j['cp'] as int?, mate: j['mate'] as int?, wdl: (w[0], w[1], w[2]));
  }

  /// Сантипешки (null, если мат).
  final int? cp;

  /// Ходов до мата: > 0 игрок матует, < 0 игрока матуют.
  final int? mate;

  /// (win, draw, loss) в промилле.
  final (int, int, int) wdl;

  Eval negate() => Eval(cp: cp == null ? null : -cp!, mate: mate == null ? null : -mate!, wdl: (wdl.$3, wdl.$2, wdl.$1));

  double pawns(Settings s) {
    if (mate != null) {
      final v = math.max(s.mateBasePawns - mate!.abs(), s.mateFloorPawns);
      return mate! > 0 ? v : -v;
    }
    return math.max(-s.cpClampPawns, math.min(s.cpClampPawns, cp! / 100.0));
  }

  /// Ожидаемый результат W + D/2, от 0 до 1.
  double get expected => (wdl.$1 + wdl.$2 / 2) / 1000.0;

  double value(Unit unit, Settings s) => unit == Unit.pawns ? pawns(s) : expected;

  bool structurallyEqual(Eval other) {
    if (mate != null || other.mate != null) return mate == other.mate;
    return cp == other.cp && wdl == other.wdl;
  }

  @override
  String toString() {
    if (mate != null) return '#$mate';
    final v = cp! / 100;
    return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(2)}';
  }
}

/// Оценку после прошлого своего хода (E0) переводит в рамку следующего хода.
Eval previousAfterMoveToRoot(Eval e) {
  if (e.mate != null && e.mate! < -1) return Eval(mate: e.mate! + 1, wdl: e.wdl);
  return e;
}

int category(double value, UnitParams p) {
  final d = value - p.center;
  if (d >= p.b2) return 4;
  if (d >= p.b1) return 3;
  if (d < -p.b2) return 0;
  if (d < -p.b1) return 1;
  return 2;
}

class Line {
  const Line({required this.move, required this.eval, required this.pv});

  Map<String, dynamic> toJson() => {'move': move, 'eval': eval.toJson(), 'pv': pv};

  factory Line.fromJson(Map<String, dynamic> j) => Line(
        move: j['move'] as String,
        eval: Eval.fromJson(j['eval'] as Map<String, dynamic>),
        pv: (j['pv'] as List).cast<String>(),
      );

  final String move;
  final Eval eval;
  final List<String> pv;
}
