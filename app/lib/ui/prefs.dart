/// Personal settings: arrow style, how legal moves are shown, piece set and
/// board colours. Kept on the device (shared_preferences).
library;

import 'package:chessground/chessground.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Arrow styles: classic, blunt (classic with a wider, flatter head), slim
/// (dots at both ends), bold.
enum ArrowStyle { classic, blunt, slim, bold }

enum LegalMoves { outline, dots, none }

/// Board colour themes with plain square colours (the board layer paints the
/// squares itself, so image themes are left out).
const boardThemes = {
  'Green': ChessboardColorScheme.green,
  'Brown': ChessboardColorScheme.brown,
  'Blue': ChessboardColorScheme.blue,
  'Grey': ChessboardColorScheme.ic,
  'Purple': ChessboardColorScheme.purple,
};

/// Colours of the user's own arrows (the idea's red and the best move's green
/// stay as they are); chosen not to merge with the board colours.
const arrowColors = {
  'Orange': Color(0xFFE08A00),
  'Blue': Color(0xFF1E88E5),
  'Violet': Color(0xFF8E44AD),
  'Pink': Color(0xFFD81B60),
  'Teal': Color(0xFF00897B),
  'Red': Color(0xFFC62828), // как стрелка идеи
};

/// Colours of marked squares: the arrow colours, the blunder red and the
/// colours of the move verdicts (as under an evaluated move).
const markColors = {
  'Orange': Color(0xFFE08A00),
  'Blue': Color(0xFF1E88E5),
  'Violet': Color(0xFF8E44AD),
  'Pink': Color(0xFFD81B60),
  'Red': Color(0xFFD7322F),
  'Brilliant': Color(0xFF14A99C),
  'Only move': Color(0xFF3B7DD8),
  'Best': Color(0xFF4CAF50),
  'Excellent': Color(0xFF5C9E68),
  'Good': Color(0xFF7FA486),
  'Book': Color(0xFFB0702F),
  'Inaccuracy': Color(0xFFF0B414),
  'Laxity': Color(0xFFF59B1E),
  'Mistake': Color(0xFFE5622E),
};

class AppPrefs extends ChangeNotifier {
  ArrowStyle arrowStyle = ArrowStyle.classic;
  bool animateArrows = true;
  String arrowColor = 'Orange';
  String markColor = 'Red';

  /// Estimate each puzzle's rating with the engine while it is being solved.
  bool estimatePuzzleRating = true;

  /// Puzzle rating chosen on the puzzles screen.
  int puzzleTarget = 1200;

  /// The puzzle rating follows the results (puzzles.dart, autoRating).
  bool puzzleAutoRating = false;

  /// Quick settings of the analysis board.
  bool showBestArrow = true;
  bool showBoardIcons = true;
  bool showSquareTint = true;
  bool showIdeaArrows = true;

  /// Move steps by the percent of the expected result lost.
  bool percentSteps = false;

  /// The trick sign next to a move's sign (off by default).
  bool showTrick = false;

  /// The analysis rules version the update notice was last shown for.
  int seenRules = 0;

  /// Pause between the moves of an idea's playback, milliseconds.
  int ideaStepMs = 1200;

  /// Ideas tab: only serious tactics; which side's ideas are shown.
  bool seriousIdeas = true;

  /// Engine lines per move for new analyses (MultiPV), 5…25.
  int engineLines = 10;

  /// How long a piece takes to move on the boards (ms).
  int moveAnimationMs = 320;

  /// Judge own moves in branches with the engine on the device.
  bool analyzeOwnMoves = true;
  bool whiteIdeas = true;
  bool blackIdeas = true;

  Color get userMarkColor => markColors[markColor] ?? const Color(0xFFD7322F);

  Color get userArrowColor => arrowColors[arrowColor] ?? const Color(0xFFE08A00);
  LegalMoves legalMoves = LegalMoves.outline;
  PieceSet pieceSet = PieceSet.cburnett;

  /// The player's name in the games (to find their side); empty: the name
  /// met most often in the analysed games.
  String playerName = '';

  /// Puzzles: prefer ones like the player's mistakes.
  bool weaknessPuzzles = true;

  /// The hint about background work was shown.
  bool batteryHintShown = false;

  /// Accuracy window: icons in their own colours (else one colour).
  bool colourSummaryIcons = false;
  String boardTheme = 'Green';

  ChessboardColorScheme get scheme => boardThemes[boardTheme] ?? ChessboardColorScheme.green;

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      arrowStyle = ArrowStyle.values.asNameMap()[p.getString('arrowStyle')] ?? arrowStyle;
      legalMoves = LegalMoves.values.asNameMap()[p.getString('legalMoves')] ?? legalMoves;
      pieceSet = PieceSet.values.asNameMap()[p.getString('pieceSet')] ?? pieceSet;
      animateArrows = p.getBool('animateArrows') ?? animateArrows;
      estimatePuzzleRating = p.getBool('estimatePuzzleRating') ?? estimatePuzzleRating;
      showBestArrow = p.getBool('showBestArrow') ?? showBestArrow;
      puzzleTarget = p.getInt('puzzleTarget') ?? puzzleTarget;
      puzzleAutoRating = p.getBool('puzzleAutoRating') ?? puzzleAutoRating;
      showBoardIcons = p.getBool('showBoardIcons') ?? showBoardIcons;
      showSquareTint = p.getBool('showSquareTint') ?? showSquareTint;
      showIdeaArrows = p.getBool('showIdeaArrows') ?? showIdeaArrows;
      percentSteps = p.getBool('percentSteps') ?? percentSteps;
      showTrick = p.getBool('showTrick') ?? showTrick;
      seenRules = p.getInt('seenRules') ?? seenRules;
      ideaStepMs = p.getInt('ideaStepMs') ?? ideaStepMs;
      seriousIdeas = p.getBool('seriousIdeas') ?? seriousIdeas;
      playerName = p.getString('playerName') ?? playerName;
      weaknessPuzzles = p.getBool('weaknessPuzzles') ?? weaknessPuzzles;
      batteryHintShown = p.getBool('batteryHintShown') ?? batteryHintShown;
      colourSummaryIcons = p.getBool('colourSummaryIcons') ?? colourSummaryIcons;
      engineLines = p.getInt('engineLines') ?? engineLines;
      moveAnimationMs = p.getInt('moveAnimationMs') ?? moveAnimationMs;
      analyzeOwnMoves = p.getBool('analyzeOwnMoves') ?? analyzeOwnMoves;
      whiteIdeas = p.getBool('whiteIdeas') ?? whiteIdeas;
      blackIdeas = p.getBool('blackIdeas') ?? blackIdeas;
      final mc = p.getString('markColor');
      if (mc != null && markColors.containsKey(mc)) markColor = mc;
      final ac = p.getString('arrowColor');
      if (ac != null && arrowColors.containsKey(ac)) arrowColor = ac;
      final theme = p.getString('boardTheme');
      if (theme != null && boardThemes.containsKey(theme)) boardTheme = theme;
      notifyListeners();
    } catch (_) {
      // без хранилища — настройки по умолчанию
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('arrowStyle', arrowStyle.name);
      await p.setString('legalMoves', legalMoves.name);
      await p.setString('pieceSet', pieceSet.name);
      await p.setString('boardTheme', boardTheme);
      await p.setBool('animateArrows', animateArrows);
      await p.setString('arrowColor', arrowColor);
      await p.setString('markColor', markColor);
      await p.setBool('estimatePuzzleRating', estimatePuzzleRating);
      await p.setBool('showBestArrow', showBestArrow);
      await p.setInt('puzzleTarget', puzzleTarget);
      await p.setBool('puzzleAutoRating', puzzleAutoRating);
      await p.setBool('showBoardIcons', showBoardIcons);
      await p.setBool('showSquareTint', showSquareTint);
      await p.setBool('showIdeaArrows', showIdeaArrows);
      await p.setBool('percentSteps', percentSteps);
      await p.setBool('showTrick', showTrick);
      await p.setInt('seenRules', seenRules);
      await p.setInt('ideaStepMs', ideaStepMs);
      await p.setBool('seriousIdeas', seriousIdeas);
      await p.setString('playerName', playerName);
      await p.setBool('weaknessPuzzles', weaknessPuzzles);
      await p.setBool('batteryHintShown', batteryHintShown);
      await p.setBool('colourSummaryIcons', colourSummaryIcons);
      await p.setInt('engineLines', engineLines);
      await p.setInt('moveAnimationMs', moveAnimationMs);
      await p.setBool('analyzeOwnMoves', analyzeOwnMoves);
      await p.setBool('whiteIdeas', whiteIdeas);
      await p.setBool('blackIdeas', blackIdeas);
    } catch (_) {}
  }

  void update({
    ArrowStyle? arrow,
    LegalMoves? legal,
    PieceSet? pieces,
    String? theme,
    bool? animate,
    String? color,
    String? mark,
    bool? puzzleRating,
    bool? bestArrow,
    int? target,
    bool? autoRating,
    bool? boardIcons,
    bool? squareTint,
    bool? ideaArrows,
    bool? percent,
    bool? trick,
    int? rulesSeen,
    int? ideaStep,
    bool? serious,
    String? name,
    bool? weakness,
    bool? batteryHint,
    bool? colourIcons,
    int? lines,
    int? moveMs,
    bool? ownMoves,
    bool? white,
    bool? black,
  }) {
    showBestArrow = bestArrow ?? showBestArrow;
    puzzleTarget = target ?? puzzleTarget;
    puzzleAutoRating = autoRating ?? puzzleAutoRating;
    showBoardIcons = boardIcons ?? showBoardIcons;
    showSquareTint = squareTint ?? showSquareTint;
    showIdeaArrows = ideaArrows ?? showIdeaArrows;
    percentSteps = percent ?? percentSteps;
    showTrick = trick ?? showTrick;
    seenRules = rulesSeen ?? seenRules;
    ideaStepMs = ideaStep ?? ideaStepMs;
    seriousIdeas = serious ?? seriousIdeas;
    playerName = name ?? playerName;
    weaknessPuzzles = weakness ?? weaknessPuzzles;
    batteryHintShown = batteryHint ?? batteryHintShown;
    colourSummaryIcons = colourIcons ?? colourSummaryIcons;
    engineLines = lines ?? engineLines;
    moveAnimationMs = moveMs ?? moveAnimationMs;
    analyzeOwnMoves = ownMoves ?? analyzeOwnMoves;
    whiteIdeas = white ?? whiteIdeas;
    blackIdeas = black ?? blackIdeas;
    estimatePuzzleRating = puzzleRating ?? estimatePuzzleRating;
    markColor = mark ?? markColor;
    arrowStyle = arrow ?? arrowStyle;
    animateArrows = animate ?? animateArrows;
    arrowColor = color ?? arrowColor;
    legalMoves = legal ?? legalMoves;
    pieceSet = pieces ?? pieceSet;
    boardTheme = theme ?? boardTheme;
    notifyListeners();
    _save();
  }
}

final prefs = AppPrefs();
