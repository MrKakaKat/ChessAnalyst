/// UI labels (English, capitalized), step colors and step symbols.
///
/// Arrows and special glyphs are drawn as icons, never as text characters:
/// not every device font has them.
library;

import 'package:flutter/material.dart';

import '../analysis/settings.dart';
import 'step_icons.dart';

const stepLabels = {
  'best': 'Best',
  'excellent': 'Excellent',
  'good': 'Good',
  'neutral': 'Neutral',
  'inaccuracy': 'Inaccuracy',
  'pass': 'Pass',
  'laxity': 'Laxity',
  'mistake': 'Mistake',
  'blunder': 'Blunder',
  'forced': 'Forced',
  'book': 'Book',
};

/// Text marks (board annotations, move list). Steps without a mark use an icon.
const stepMarks = {
  'best': '!',
  'excellent': '!',
  'good': '',
  'neutral': '',
  'inaccuracy': '?!',
  'pass': '',
  'laxity': '!?',
  'mistake': '?',
  'blunder': '??',
  'forced': '',
  'book': '',
};

const flagLabels = {
  'pass': 'Pass',
  'neutral': 'Neutral',
  'near_best': 'Near best',
  'trivial': 'Trivial position',
  'sharp': 'Sharp position',
  'worst': 'Worst move of the game',
  'quiet': 'Quiet position',
  'theory': 'Theory',
  'book': 'Book',
  'hopeless': 'Hopeless position',
  'only_move': 'Only move',
  'only_light': 'Only move',
  'brilliant': 'Brilliant',
  'underpress': 'Underpress',
};

const stageLabels = {'opening': 'Opening', 'middlegame': 'Middlegame', 'endgame': 'Endgame'};

const categoryLabels = {'loss': 'Loss', 'worse': 'Worse', 'equal': 'Equal', 'better': 'Better', 'win': 'Win'};

const motifLabels = {
  'mate': 'Mate',
  'promotion': 'Promotion',
  'fork': 'Fork',
  'pin': 'Pin',
  'discovered': 'Discovered attack',
  'open_line': 'Open line',
  'hanging': 'Hanging piece',
  'material': 'Material gain',
  'plan': 'Plan',
};

const typeLabels = {
  'tactical': 'Tactical',
  'positional': 'Positional',
  'attacking': 'Attack',
  'counterattacking': 'Counterattack',
  'defensive': 'Defence',
};

const unitLabels = {Unit.pawns: 'Pawns', Unit.wdl: 'WDL', Unit.both: 'Diff'};

/// The third unit, Diff, is the practical evaluation of the difficulty
/// analysis (AAC stays in More graphs); without that analysis it shows
/// nothing but a button to run it.
String unitLabel(Unit u) => unitLabels[u]!;

/// Move type: the base (tactical / positional), then its directions
/// (attack, counterattack, defence), e.g. "Tactical · Attack + Defence".
String typeText(String type, List<String> extra) {
  final base = typeLabels[type] ?? type;
  if (extra.isEmpty) return base;
  return '$base · ${extra.map((t) => typeLabels[t] ?? t).join(' + ')}';
}

Color stepColor(String step, Brightness b) {
  final dark = b == Brightness.dark;
  return switch (step) {
    'best' || 'excellent' => dark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32),
    'good' => dark ? const Color(0xFF9CCC65) : const Color(0xFF558B2F),
    'neutral' || 'forced' => dark ? const Color(0xFF9E9E9E) : const Color(0xFF757575),
    'book' => dark ? const Color(0xFFD49A63) : const Color(0xFFA0612A),
    'inaccuracy' => dark ? const Color(0xFFFFCA28) : const Color(0xFFC08B00),
    'pass' => dark ? const Color(0xFFB39DDB) : const Color(0xFF6A4FB3),
    'laxity' => dark ? const Color(0xFFFFA726) : const Color(0xFFD07A00),
    'mistake' => dark ? const Color(0xFFFF7043) : const Color(0xFFD84315),
    'blunder' => dark ? const Color(0xFFEF5350) : const Color(0xFFB71C1C),
    _ => Colors.grey,
  };
}

const brilliantColor = Color(0xFF14A99C);
const onlyMoveColor = Color(0xFF3B7DD8);
const onlyLightColor = Color(0xFF00A572);

/// Colour of an icon kind in the card and text: the step colour, or the
/// brilliant / only move colour.
Color kindColor(String kind, Brightness b) => switch (kind) {
      'brilliant' => brilliantColor,
      'only_move' => onlyMoveColor,
      'only_light' => onlyLightColor,
      _ => stepColor(kind, b),
    };

/// Steps after which the card offers "Why?".
bool isBad(String step) => const {'inaccuracy', 'pass', 'laxity', 'mistake', 'blunder'}.contains(step);

bool isError(String step) => step == 'laxity' || step == 'mistake' || step == 'blunder';

/// The step's sign, drawn (see step_icons.dart): thick rounded !/?, star,
/// thumbs-up, check, bar, arrow, open book.
class StepSymbol extends StatelessWidget {
  const StepSymbol({super.key, required this.step, this.brilliant = false, required this.color, this.size = 14});

  final String step;
  final bool brilliant;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      StepGlyph(kind: brilliant ? 'brilliant' : step, color: color, size: size * 1.15);
}

/// Inline arrow drawn as an icon (text arrows are not supported on every font).
class ArrowGlyph extends StatelessWidget {
  const ArrowGlyph({super.key, this.size = 14, this.color});

  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Icon(Icons.arrow_forward_rounded, size: size, color: color ?? Theme.of(context).colorScheme.outline),
      );
}

/// Piece in English notation (R, N, B, Q, K; pawns by square only). Used instead
/// of the chess glyphs, which some device fonts lack.
String pieceText(String symbol, String square) {
  final letter = symbol.toUpperCase();
  return letter == 'P' ? square : '$letter$square';
}

const _glyphLetters = {
  '♖': 'R', '♘': 'N', '♗': 'B', '♕': 'Q', '♔': 'K', '♙': '',
  '♜': 'R', '♞': 'N', '♝': 'B', '♛': 'Q', '♚': 'K', '♟': '',
};

/// Replaces chess glyphs in analysis text by notation letters.
String deglyph(String text) => text.split('').map((ch) => _glyphLetters[ch] ?? ch).join();

String plyText(int ply) => '${ply ~/ 2 + 1}${ply.isOdd ? '...' : '.'}';

/// Kinds of move icons that can be hidden on the board (Settings).
const boardIconKinds = [
  'brilliant', 'only_move', 'only_light', 'best', 'excellent', 'good', 'book', 'forced', //
  'neutral', 'inaccuracy', 'laxity', 'pass', 'mistake', 'blunder',
];

String boardIconLabel(String k) => switch (k) {
      'only_light' => 'Obvious only move',
      _ => stepLabels[k] ?? flagLabels[k] ?? k,
    };
