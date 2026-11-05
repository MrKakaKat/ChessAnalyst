/// Пороги анализа — те же стартовые значения, что в chessanalyst/settings.py.
library;

const categories = ['loss', 'worse', 'equal', 'better', 'win'];
const loss = 0, worse = 1, equal = 2, better = 3, win = 4;

enum Unit { pawns, wdl, both }

class UnitParams {
  const UnitParams({
    required this.center,
    required this.b1,
    required this.b2,
    required this.eps1,
    required this.eps2,
    required this.gSignificant,
    required this.laxThreshold,
    required this.neutralEps,
    required this.passStep,
    this.inaccuracyLoss = 0.1,
    this.laxityLoss = 0.5,
    this.mistakeLoss = 1.0,
  });

  final double center, b1, b2, eps1, eps2, gSignificant, laxThreshold, neutralEps, passStep;

  /// Loss L above which a move is an inaccuracy, laxity (weakness), mistake.
  final double inaccuracyLoss, laxityLoss, mistakeLoss;
}

const pawnsParams = UnitParams(
  center: 0.0, b1: 0.7, b2: 2.0, eps1: 0.01, eps2: 0.05,
  gSignificant: 0.3, laxThreshold: 0.2, neutralEps: 0.1, passStep: 1.0,
);

const wdlParams = UnitParams(
  center: 0.5, b1: 0.10, b2: 0.30, eps1: 0.002, eps2: 0.01,
  gSignificant: 0.05, laxThreshold: 0.03, neutralEps: 0.02, passStep: 0.15,
  inaccuracyLoss: 0.02, laxityLoss: 0.06, mistakeLoss: 0.12,
);

/// Version of the analysis rules (kinds of moves, grades, ideas). Raise it
/// when an update changes how games are judged: analyses made with an older
/// version are marked "re-analyse" in the history, and a notice explains it
/// once after the update. The classification itself is recomputed from the
/// stored engine data on every opening; a re-analysis is needed only for
/// what the old engine data lacks.
/// 1 — up to the test builds of November 2026;
/// 2 — ChessAnalyst 1.0: retreat and defence, percent steps, new kinds,
///     brilliant ideas.
const analysisRules = 2;

class Settings {
  const Settings({this.unit = Unit.both, this.multipv = 5, this.percentSteps = false});

  final Unit unit;

  /// [авторское] Steps by the loss of the expected result in percent instead
  /// of the unit's thresholds (a switch in the quick settings): best ≤ 1%,
  /// excellent 1–2, good 2–5, inaccuracy 5–10, laxity 10–15, mistake 15–25,
  /// blunder over 25. Neutral: up to 1% lost by a move outside the best
  /// lines — it changes nothing.
  final bool percentSteps;

  /// Линий в корневом анализе (как в данных движка партии).
  final int multipv;
  final double cpClampPawns = 40.0;
  final double mateBasePawns = 100.0;
  final double mateFloorPawns = 50.0;

  final double excellentRatio = 0.7;
  final double goodRatio = 0.3;
  final double passRatio = 0.3;

  final int brilliantMaterial = 2;
  final int brilliantHoldReplies = 2;

  final int tacticalWindowPlies = 4;
  final int tacticalMinForcing = 2;
  final int attackThreshold = 1;
  final int defenseThreshold = 1;
  final int onlyWindowPlies = 8;
  final int onlyMinForcing = 3;
  final int threatsRemovedThreshold = 1;

  final int openingMaxMove = 12;
  final int openingMinUndeveloped = 3;
  final int endgameMaterial = 26;

  final double trivialShare = 0.8;
  final int theoryPlies = 0;

  final int ideaWindowPlies = 10;
  final int ideaScanPlies = 10;
  final int ideaMinGain = 2;

  final UnitParams pawns = pawnsParams;
  final UnitParams wdl = wdlParams;

  /// Единица категорий: при "both" — WDL.
  Unit get classUnit => unit == Unit.pawns ? Unit.pawns : Unit.wdl;

  UnitParams paramsFor(Unit u) => u == Unit.pawns ? pawns : wdl;

  List<Unit> get units => unit == Unit.both ? const [Unit.pawns, Unit.wdl] : [classUnit];
}
