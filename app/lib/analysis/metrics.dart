/// Game summary: accuracy of each side (overall and by stage) and the game's
/// difficulty.
///
/// Accuracy of a move follows the common win-percentage formula: the drop of
/// the expected result (W + D/2, in percent) from before to after the move,
/// 103.17·e^(−0.0435·drop) − 3.17, clamped to 0…100. [простое решение] A side's
/// accuracy is the plain mean over its moves; forced moves are left out (no
/// choice), book moves count as played.
///
/// [авторское] Difficulty asks how much the game demanded, from five parts,
/// each 0…1:
/// - tactics: share of positions where the best move is tactical;
/// - depth: how long the forcing sequences of those best moves run;
/// - precision: share of positions where only one move held (the second
///   line half a pawn worse or more);
/// - ideas: idea chains, ten of them count as full;
/// - length: a short game (a quick mate) cannot be demanding.
/// The overall score is their weighted sum, 0…100, with a level name.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;

import 'classify.dart';
import 'features.dart' as features;
import 'game.dart';
import 'pos.dart';
import 'settings.dart';

const stages = ['opening', 'middlegame', 'endgame'];

double moveAccuracy(MoveRecord r) {
  final drop = math.max(0.0, (r.wdl.e1 - r.wdl.ep) * 100);
  return (103.1668 * math.exp(-0.04354 * drop) - 3.1669).clamp(0.0, 100.0);
}

class SideAccuracy {
  const SideAccuracy(this.overall, this.byStage, this.moves);

  final double? overall;

  /// Stage -> accuracy (null when the side made no move in that stage).
  final Map<String, double?> byStage;
  final int moves;
}

class DifficultyPart {
  const DifficultyPart(this.name, this.value, this.weight, this.note);

  final String name;

  /// 0..1.
  final double value;
  final double weight;
  final String note;
}

class GameSummary {
  const GameSummary(this.accuracy, this.difficulty, this.parts);

  final Map<Side, SideAccuracy> accuracy;

  /// 0..100.
  final double difficulty;
  final List<DifficultyPart> parts;

  String get level => switch (difficulty) {
        < 20 => 'Easy',
        < 35 => 'Below average',
        < 50 => 'Average',
        < 65 => 'Above average',
        < 80 => 'Hard',
        _ => 'Very hard',
      };
}

GameSummary summarize(GameAnalysis a) {
  final records = a.records;
  double? mean(Iterable<double> xs) => xs.isEmpty ? null : xs.reduce((x, y) => x + y) / xs.length;

  final accuracy = <Side, SideAccuracy>{};
  for (final side in Side.values) {
    final own = records.where((r) => r.side == side && r.step != 'forced').toList();
    accuracy[side] = SideAccuracy(
      mean(own.map(moveAccuracy)),
      {for (final st in stages) st: mean(own.where((r) => r.stage == st).map(moveAccuracy))},
      own.length,
    );
  }

  // позиции с выбором: не книга и не вынужденный ход
  final choice = [for (final r in records) if (r.step != 'book' && r.step != 'forced' && r.bestMoves.isNotEmpty) r];
  final n = math.max(choice.length, 1);
  final tactical = choice.where((r) => r.bestMoves.first.type == 'tactical').toList();
  final tacticsShare = tactical.length / n;

  var forcing = 0.0;
  for (final r in tactical) {
    final p = a.game.plies[r.ply];
    final line = p.lines.firstWhere((l) => l.move == r.bestMoves.first.uci, orElse: () => p.lines.first);
    forcing += features.forcingCount(Pos.fromFen(p.fenBefore), line.pv, 12);
  }
  final depth = tactical.isEmpty ? 0.0 : math.min(1.0, forcing / tactical.length / 6);

  // точность требовалась, если второй ход хуже лучшего хотя бы на полпешки
  const s = Settings();
  final single = choice.where((r) {
        final lines = a.game.plies[r.ply].lines;
        return lines.length < 2 || lines[0].eval.pawns(s) - lines[1].eval.pawns(s) >= 0.5;
      }).length /
      n;

  final plies = records.length;
  // [авторское] 10 идей — уже 100 % (все идеи длиннее одного хода)
  final ideas = math.min(1.0, a.ideas.length / 10);

  final length = math.min(1.0, plies / 60);

  final parts = [
    DifficultyPart('Tactics', tacticsShare * 2 > 1 ? 1 : tacticsShare * 2, 0.3,
        '${tactical.length} of ${choice.length} positions asked for a tactical move'),
    DifficultyPart('Depth', depth, 0.2,
        tactical.isEmpty ? 'No tactics' : 'Forcing lines of about ${(forcing / tactical.length).toStringAsFixed(1)} plies'),
    DifficultyPart('Precision', math.min(1.0, single * 1.5), 0.25,
        '${(single * 100).round()}% of positions had one good move (the next is half a pawn worse or more)'),
    DifficultyPart('Ideas', ideas, 0.15, '${a.ideas.length} idea chains (10 count as full)'),
    DifficultyPart('Length', length, 0.1, '$plies plies'),
  ];
  // короткая партия не может быть сложной: длина ограничивает итог
  final raw = parts.fold(0.0, (s, p) => s + p.value * p.weight) * 100;
  final score = raw * (0.4 + 0.6 * length);
  return GameSummary(accuracy, score, parts);
}

/// [простое решение] A rough playing strength from a side's accuracy and the
/// game's difficulty: 55% ≈ 400, 75% ≈ 1200, 90% ≈ 2100, 97% ≈ 2700, then
/// ±8 points per difficulty point away from 50. Only a hint: one game says
/// little, and the scale is not calibrated on rated players yet.
int? ratingEstimate(double? accuracy, double difficulty) {
  if (accuracy == null) return null;
  final x = ((accuracy - 55) / 42).clamp(0.0, 1.0);
  final r = 400 + 2300 * math.pow(x, 1.3) + (difficulty - 50) * 8;
  return ((r / 50).round() * 50).clamp(100, 3200);
}

/// Sharpness of the game, 0..100 (docs/plan_next.md 3.3), from three parts:
/// - the expected chance of a draw (WDL) is low;
/// - many positions are sharp (few positive moves, see character.dart);
/// - many moves are tactical with an attack or a counterattack.
class GameSharpness {
  const GameSharpness(this.score, this.drawShare, this.sharpShare, this.attackShare);

  final double score, drawShare, sharpShare, attackShare;
}

GameSharpness sharpnessOf(GameAnalysis a, double Function(int ply) sharpAt) {
  final records = a.records;
  if (records.isEmpty) return const GameSharpness(0, 0, 0, 0);
  final n = records.length;
  final draw = records.map((r) => a.game.plies[r.ply].lines.first.eval.wdl.$2 / 1000).reduce((x, y) => x + y) / n;
  final sharp = [for (final r in records) sharpAt(r.ply)].reduce((x, y) => x + y) / n;
  final attack = records
          .where((r) =>
              r.moveType == 'tactical' &&
              (r.typeSubtypes.contains('attacking') || r.typeSubtypes.contains('counterattacking')))
          .length /
      n;
  final score = 100 * (0.35 * (1 - draw) + 0.35 * sharp + 0.3 * math.min(1.0, attack * 2.5));
  return GameSharpness(score, draw, sharp, attack);
}

