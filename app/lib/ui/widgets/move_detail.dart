/// Selected move card and engine lines.
///
/// Animations: the card slides in from the side you are stepping towards; the
/// step badge first pops in as a round sign, then rolls aside and reveals the
/// step name; Brilliant and Blunder send an outline flying out, Brilliant gets
/// a glare. Best and book chips play their move on the board.
library;

import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../../analysis/aac.dart' show Trick;
import '../../analysis/character.dart' show Sharpness;
import '../../analysis/classify.dart';
import '../../analysis/difficulty.dart' show lineHasOnly;
import '../../analysis/human.dart' show humanAim, significance;
import '../../analysis/ideas.dart';
import '../../analysis/kinds.dart' show kindLabels;
import '../../analysis/weakness.dart';
import '../../analysis/pos.dart';
import '../../analysis/settings.dart';
import '../controller.dart';
import '../theme.dart' show onlyBlue;
import '../improve_screen.dart';
import '../underlines.dart';
import '../labels.dart';
import '../prefs.dart';
import '../step_icons.dart';
import 'board_view.dart';
import 'eval_widgets.dart';
import 'faded_line.dart';
import 'summary_sheet.dart';

class MoveDetail extends StatelessWidget {
  const MoveDetail({super.key, required this.controller, this.onOpenIdea});

  final AnalysisController controller;
  final VoidCallback? onOpenIdea;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    // новые данные анализа — карточка проступает на месте, без сдвига
    final dir = c.updatingData ? 0.0 : c.direction.toDouble();
    final kind = c.inVariation ? (c.varMove!.kind ?? '') : (c.record != null ? c.kindAt(c.ply) : '');
    final key = ValueKey('${c.positionKey}-${c.unit.name}-$kind');
    final vm = c.varMove;
    final Widget card;
    if (vm != null) {
      final ply = c.variation!.anchor + 1 + c.varIndex;
      card = vm.record != null
          ? _Card(key: key, c: c, r: vm.record!, title: '${plyText(ply)} ${vm.san}', variation: true)
          : _VariationCard(key: key, c: c, vm: vm, title: '${plyText(ply)} ${vm.san}');
    } else if (c.atStart) {
      card = _StartCard(key: key, c: c);
    } else if (c.atEnd) {
      card = _EndCard(key: key, c: c);
    } else if (c.isMate(c.ply)) {
      card = _MateCard(key: key, c: c);
    } else {
      final r = c.analysis.records[c.ply];
      card = _Card(key: key, c: c, r: r, title: '${plyText(r.ply)} ${r.san}', onOpenIdea: onOpenIdea);
    }
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final incoming = child.key == key;
        final offset = Tween(begin: Offset((incoming ? 0.12 : -0.12) * dir, 0), end: Offset.zero).animate(anim);
        return FadeTransition(opacity: anim, child: SlideTransition(position: offset, child: child));
      },
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.topLeft, children: [...previous, ?current]),
      child: card,
    );
  }
}

/// Initial position, before the first move.
class _StartCard extends StatelessWidget {
  const _StartCard({super.key, required this.c});

  final AnalysisController c;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // заголовок открывает разбор ошибок: Fix и Survival, Foresight
      InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ImproveScreen(controller: c))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(
            child: Text('Start to improve!', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 6),
          Icon(Icons.arrow_forward_rounded, color: theme.colorScheme.primary),
        ]),
      ),
      const SizedBox(height: 6),
      Text('Tap the title to work through the mistakes: find the better move, hold it against the engine, or '
          'foresee the plan. Or step through the game and play your own moves on the board.',
          style: TextStyle(color: theme.colorScheme.outline)),
    ]);
  }
}

/// Checkmate: its own sign and nothing else to judge.
class _MateCard extends StatelessWidget {
  const _MateCard({super.key, required this.c});

  final AnalysisController c;

  @override
  Widget build(BuildContext context) {
    final r = c.analysis.records[c.ply];
    final theme = Theme.of(context);
    final winner = r.side.name == 'white' ? 'White' : 'Black';
    final loser = r.side.name == 'white' ? 'Black' : 'White';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${plyText(r.ply)} ${r.san}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        StepBadge(kind: 'mate', color: c.kindColorAt(c.ply, 'mate')),
        AccuracyButton(controller: c),
      ]),
      const SizedBox(height: 10),
      Text('$winner checkmates $loser.'),
    ]);
  }
}

/// The game's end: resignation (graded) or loss on time.
class _EndCard extends StatelessWidget {
  const _EndCard({super.key, required this.c});

  final AnalysisController c;

  @override
  Widget build(BuildContext context) {
    final e = c.end!;
    final theme = Theme.of(context);
    final who = e.loser?.name == 'white' ? 'White' : 'Black';
    final text = switch (e.kind) {
      'resign' => '$who resigned in ${_article(categoryLabels[e.category]!)} position.',
      'draw' => 'Draw: ${e.reason!.toLowerCase()}.',
      _ => '$who lost on time.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.label, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 10),
      Wrap(spacing: 10, runSpacing: 8, children: [
        StepBadge(kind: e.kind, color: markColor(e.step ?? (e.kind == 'draw' ? 'neutral' : 'forced'))),
        AccuracyButton(controller: c),
      ]),
      const SizedBox(height: 10),
      Text(text),
      if (e.step != null) ...[
        const SizedBox(height: 6),
        Row(children: [
          Text('Verdict: ', style: TextStyle(color: theme.colorScheme.outline)),
          Text(stepLabels[e.step]!, style: TextStyle(fontWeight: FontWeight.w700, color: markColor(e.step!))),
          const SizedBox(width: 6),
          StepGlyph(kind: e.step!, color: markColor(e.step!), size: 16),
        ]),
      ],
    ]);
  }

  static String _article(String category) {
    final word = category.toLowerCase();
    return word == 'equal' ? 'an equal' : (word == 'win' ? 'a winning' : (word == 'loss' ? 'a lost' : 'a $word'));
  }
}

/// A variation move without its own verdict: along the engine line (best,
/// with the line's evaluation) or an own move outside the lines (grey branch
/// sign, no evaluation, no animation).
class _VariationCard extends StatelessWidget {
  const _VariationCard({super.key, required this.c, required this.vm, required this.title});

  final AnalysisController c;
  final VarMove vm;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 10, children: [
        Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (vm.moveType != null)
          Text(typeText(vm.moveType!, const []),
              style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline, fontWeight: FontWeight.w600)),
      ]),
      const SizedBox(height: 10),
      if (vm.eval != null) ...[
        const StepBadge(kind: 'best'),
        const SizedBox(height: 10),
        // синие — линии анализа партии, серые — посчитанные на устройстве сейчас
        Text(
            '${vm.inLines ? 'Engine line of the analysis' : 'Engine on the device'}: '
            '${whiteEvalText(vm.eval!, vm.root, c.unit)}',
            style: TextStyle(fontSize: 13, color: vm.inLines ? scheme.primary : scheme.outline)),
      ] else ...[
        StepBadge(kind: 'branch', color: markColor('neutral'), animate: false),
        const SizedBox(height: 10),
        Text('Your move is outside the engine lines, so it has no evaluation yet.',
            style: TextStyle(fontSize: 13, color: scheme.outline)),
      ],
    ]);
  }
}

/// Heights of the card's header grid (title row, gap before the badge row).
const _titleRow = 34.0;
const _rowGap = 10.0;

class _Card extends StatelessWidget {
  const _Card({super.key, required this.c, required this.r, required this.title, this.variation = false, this.onOpenIdea});

  final AnalysisController c;
  final MoveRecord r;
  final String title;

  /// The first move of an own branch, judged in the game's position.
  final bool variation;
  final VoidCallback? onOpenIdea;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final idea = variation ? null : c.analysis.ideaAt(c.ply);
    // brilliant уже на бейдже
    // brilliant и only уже на плашке хода
    // характер позиции до хода: тривиальная / острая, тихая; старая метка
    // trivial (перевес держат почти все ходы) уступает ему место
    final ch = variation ? null : c.characterAt(c.ply);
    final tags = [
      if (r.subtype != null && !const {'brilliant', 'only_move', 'only_light'}.contains(r.subtype)) r.subtype!,
      if (ch?.sharpness == Sharpness.trivial) 'trivial',
      if (!variation && c.worstPly(r.side) == r.ply) 'worst',
      if (ch?.sharpness == Sharpness.sharp) 'sharp',
      if (ch?.quiet ?? false) 'quiet',
      ...r.flags.where((f) => f != 'book' && (ch == null || f != 'trivial')),
    ];
    final unitDiff = r.unitSteps.length > 1 && r.unitSteps.values.toSet().length > 1;
    final suggest = !variation && r.step != 'forced' && c.alternatives(c.ply).length > 1;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // справа — лучший (или второй) ход: центр хода на одной линии с заголовком
      // Сетка заголовка: слева ход и тип, под ними плашка; справа заголовок
      // «Best/Other move» на линии типа хода, сам ход — на линии плашки,
      // оценка — под ним на том же расстоянии, что заголовок над ним.
      // правый блок не растягивает сетку: оценка под ходом свисает вниз,
      // поэтому следующие строки оставляют справа место
      // строка хода — на всю ширину; справа место только у строки плашки:
      // там стоит other move (или Back to game в своей ветке)
      Stack(clipBehavior: Clip.none, children: [
        Padding(
          padding: EdgeInsets.zero,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: _titleRow,
              child: Row(children: [
                // ход — сколько ему нужно; тип — всё остальное место строки
                Text(title,
                    maxLines: 1, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(typeText(r.moveType, r.typeSubtypes),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(color: scheme.outline, fontWeight: FontWeight.w600)),
                ),
              ]),
            ),
            const SizedBox(height: _rowGap),
            Padding(
              padding: EdgeInsets.only(right: suggest ? 150 : (variation ? 150 : 0)),
              child: Wrap(spacing: 10, runSpacing: 8, children: [
              StepBadge(kind: iconKindOf(r.step, r.subtype)),
              // трюк: круглая карточка без названия справа от основной
              if (!variation && prefs.showTrick)
                if (c.trickAt(r.ply) case final t?) TrickBadge(trick: t),
              // партия кончилась иначе (ничья и т. п.) — итог на последнем ходу
              if (!variation && c.ply == c.length - 1 && c.end == null) AccuracyButton(controller: c),
              ]),
            ),
          ]),
        ),
        if (suggest)
          Positioned(top: _titleRow + _rowGap, right: 0, child: _Suggestion(c: c, ply: c.ply, played: r.uci)),
        // в своей ветке на месте other move — возврат к партии
        if (variation)
          Positioned(
            top: _titleRow + _rowGap,
            right: 0,
            child: SizedBox(
              height: 30,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  minimumSize: const Size(0, 30),
                ),
                onPressed: c.exitVariation,
                icon: const Icon(Icons.undo_rounded, size: 18),
                label: const Text('Back to game'),
              ),
            ),
          ),
      ]),
      // оценка other move свисает под строкой плашки
      if (r.opening != null) ...[
        const SizedBox(height: 10),
        Text(r.opening!, style: const TextStyle(fontWeight: FontWeight.w600)),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('Engine verdict: ${stepLabels[r.engineStep]}', style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
      ],
      if (tags.isNotEmpty || unitDiff)
        Padding(
          // справа место под оценку other move, свисающую из строки плашки
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in tags) _Tag(flagLabels[t] ?? t),
            if (unitDiff)
              _Tag('Pawns: ${stepLabels[r.unitSteps[Unit.pawns]]}, WDL: ${stepLabels[r.unitSteps[Unit.wdl]]}',
                  muted: true),
          ]),
        ),
      // после плохого хода — «Why?»: идея (если она есть) или линия
      // соперника, в которой он получает перевес
      if (!variation && (negativeSteps.contains(r.step) || idea != null)) ...[
        const SizedBox(height: 10),
        // Why и Underline — в одной строке; причина идеи — под Why, не сдвигая его
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (idea != null || (isBad(r.step) && c.canShowPunishment(c.ply)))
            Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact),
                onPressed: () {
                  if (idea != null) {
                    c.selectIdea(idea);
                    onOpenIdea?.call();
                  } else {
                    c.showPunishment(c.ply);
                  }
                },
                icon: const Icon(Icons.help_outline_rounded, size: 18),
                label: const Text('Why?'),
              ),
              if (idea != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(motifLabels[idea.signature.motif] ?? idea.signature.motif,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: scheme.onSurfaceVariant)),
                ),
            ]),
          // правее Why: отметить ошибку как непонятную (вес ×2 в профиле)
          if (negativeSteps.contains(r.step))
            Flexible(
              child: ListenableBuilder(
                listenable: underlines,
                builder: (context, _) {
                  final on = underlines.has(c.game.id, c.ply);
                  return TextButton.icon(
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 6), visualDensity: VisualDensity.compact),
                    onPressed: () => underlines.toggle(c.game.id, c.ply),
                    icon: Icon(on ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, size: 18),
                    label: Text(on ? 'Underlined: not clear to me' : 'Underline: not clear to me why',
                        overflow: TextOverflow.ellipsis),
                  );
                },
              ),
            ),
        ]),
      ],
      const SizedBox(height: 12),
      if (!variation) ...[
        // что делает ход, и чего не увидел игрок (вид пропущенного лучшего)
        _kv(context, 'Kind', Text(c.kindsAt(c.ply).$1.map((k) => kindLabels[k] ?? k).join(' · '), style: _valueStyle)),
        if (c.kindsAt(c.ply).$2.isNotEmpty)
          _kv(
            context,
            'Missed',
            Text(
              '${c.kindsAt(c.ply).$2.map((k) => kindLabels[k] ?? k).join(' · ')} '
              '${r.bestMoves.isNotEmpty ? '(${r.bestMoves.first.san}) ' : ''}'
              'in the ${stageLabels[r.stage]!.toLowerCase()}',
              style: _valueStyle.copyWith(color: stepColor(r.step, theme.brightness), fontWeight: FontWeight.w600),
            ),
          ),
      ],
      if (!variation && negativeSteps.contains(r.step))
        if (c.weightAt(c.ply) case final w?)
          // вес ошибки: насколько трудно было увидеть наказание
          _kv(context, 'Weight', Text('${w.value} · ${w.why}', style: _valueStyle)),
      if (!variation && r.step != 'book' && r.step != 'forced' && r.bestMoves.isNotEmpty)
        _kv(
            context,
            'Intuitive',
            Text(
                '${c.intuitivenessAt(c.ply)} · ${switch (c.intuitivenessAt(c.ply)) { < 30 => 'hard to see', < 60 => 'takes a look', _ => 'natural' }} '
                '(${r.bestMoves.first.san})',
                style: _valueStyle)),
      // значимость ошибки: падение, интуитивность, сложность позиции
      if (!variation && negativeSteps.contains(r.step))
        if (significance(c.analysis, c.ply) case final sg)
          _kv(
              context,
              'Significance',
              Text('${sg.value} · D ${sg.drop} · I ${sg.intuitive} · C ${sg.complexity}', style: _valueStyle)),
      // куда рациональнее идти по WDL: к победе, к ничьей или держать баланс
      if (!variation && r.step != 'book' && r.step != 'forced')
        if (humanAim(c.game, c.ply) case final h?)
          _kv(
              context,
              'Aim',
              Text(
                  '${switch (h.aim) { 'win' => 'Play for the win', 'draw' => 'Aim for a draw', _ => 'Keep the balance' }}'
                  ' · ${c.before[c.ply].san(Pos.move(h.uci))}${h.engineBest ? '' : ' (human)'}'
                  ' · W ${(h.wdl.$1 / 10).round()} D ${(h.wdl.$2 / 10).round()} L ${(h.wdl.$3 / 10).round()}',
                  style: _valueStyle)),
      // анализ сложности: трудность позиции до хода для каждой стороны и
      // практическая оценка (оценка движка с поправкой на сложность стороны,
      // которая впереди)
      if (!variation && c.ply >= 0 && c.ply < c.difficulty.length && c.difficulty[c.ply] != null)
        () {
          final d = c.difficulty[c.ply]!;
          String side(bool mover) => (r.side == Side.white) == mover ? 'White' : 'Black';
          // оценки — за белых, как везде
          String pawns(double v) {
            final w = r.side == Side.white ? v : -v;
            return '${w >= 0 ? '+' : ''}${w.toStringAsFixed(1)}';
          }
          return _kv(
              context,
              'Difficulty',
              Text(
                  '${side(true)} ${(d.mover * 100).round()}% · ${side(false)} ${(d.other * 100).round()}%'
                  ' · practical ${pawns(d.practical)} (engine ${pawns(d.engine)})',
                  style: _valueStyle));
        }(),
      if (!variation && negativeSteps.contains(r.step)) ...[
        if (lossKind(r.pawns.e1, r.pawns.ep) case final l?) _kv(context, 'Loss', Text(lossLabels[l]!, style: _valueStyle)),
        _kv(context, 'Irreversibility', Text(irreversibilityLabels[irreversibilityOf(r.pawns.e1)]!, style: _valueStyle)),
      ],
      _kv(context, 'Stage', Text(stageLabels[r.stage]!, style: _valueStyle)),
      // активность фигур после хода (поля, связки, минус защитные обязанности)
      if (!variation && c.ply < c.aac.length)
        _kv(
            context,
            'Activity',
            Text(
                'White ${c.aac[c.ply].activity[Side.white]!.round()} · Black ${c.aac[c.ply].activity[Side.black]!.round()}',
                style: _valueStyle)),
      _kv(context, 'Position', Text(categoryLabels[r.catEp]!, style: _valueStyle)),
      const SizedBox(height: 8),
      if (r.step == 'book' && c.book != null) ...[
        Text('Popular continuations', style: theme.textTheme.labelLarge?.copyWith(color: scheme.outline)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final b in c.book!.continuations(c.before[c.ply]))
            ActionChip(
              visualDensity: VisualDensity.compact,
              avatar: const StepIcon(kind: 'book', size: 18),
              label: Text([
                b.san,
                if (_alt(b.uci) case final a?) whiteEvalText(a.eval, a.side, c.unit),
                if (b.uci == r.uci) 'Played',
              ].join('  ')),
              tooltip: b.name.isEmpty ? null : b.name,
              onPressed: () => c.playAlternative(c.ply, b.uci),
            ),
        ]),
      ],
    ]);
  }

  AltMove? _alt(String uci) {
    if (variation) return null;
    for (final a in c.alternatives(c.ply)) {
      if (a.uci == uci) return a;
    }
    return null;
  }

  static const _valueStyle = TextStyle(fontSize: 13, fontFeatures: [FontFeature.tabularFigures()]);

  Widget _kv(BuildContext context, String k, Widget v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
              width: 86,
              child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13))),
          Expanded(child: v),
        ]),
      );
}

/// Idea chunk: attacker, arrow icon, target and motif.
/// Drawn from the signature, so no text arrows are needed.
class ChunkView extends StatelessWidget {
  const ChunkView({super.key, required this.idea, this.color, this.style});

  final Idea idea;
  final Color? color;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final sig = idea.signature;
    final s = (style ?? const TextStyle(fontSize: 14)).copyWith(color: color);
    return Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text(pieceText(sig.attackerPiece, sig.attackerSquare.name), style: s),
      ArrowGlyph(size: 15, color: color),
      Text(sig.targetPiece != null ? pieceText(sig.targetPiece!, sig.targetSquare.name) : sig.targetSquare.name,
          style: s),
      Text('  ${motifLabels[sig.motif] ?? sig.motif}', style: s.copyWith(fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Step badge: a round sign pops in, then rolls to the side and reveals the
/// name. Brilliant and Blunder send an outline flying out of the frame;
/// Brilliant has a light gradient and a glare sweeping across.
class StepBadge extends StatefulWidget {
  const StepBadge({super.key, required this.kind, this.color, this.animate = true});

  /// Icon kind: a step, brilliant / only_move, resign / timeout, branch.
  final String kind;
  final Color? color;
  final bool animate;

  bool get brilliant => kind == 'brilliant';

  @override
  State<StepBadge> createState() => _StepBadgeState();
}

class _StepBadgeState extends State<StepBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: Duration(milliseconds: widget.brilliant ? 1700 : 1150))
    ..forward(from: widget.animate ? 0 : 1);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = widget.kind;
    // блок и знак в кружке — тот же цвет, что у значка на доске
    final color = widget.color ?? markColor(kind);
    final label = switch (kind) {
      'brilliant' => 'Brilliant',
      'only_move' || 'only_light' => 'Only move',
      'resign' => 'Resign',
      'timeout' => 'Time out',
      'branch' => 'Own move',
      'mate' => 'Checkmate',
      _ => stepLabels[kind]!,
    };
    final loud = isLoudKind(kind);
    const d = 30.0;
    // доли общей длительности: у brilliant добавлен блик в конце
    final k = widget.brilliant ? 1150 / 1700 : 1.0;
    final pop = CurvedAnimation(parent: _a, curve: Interval(0, 0.3 * k, curve: Curves.elasticOut));
    final roll = CurvedAnimation(parent: _a, curve: Interval(0.3 * k, 0.85 * k, curve: Curves.easeOutCubic));
    final fly = CurvedAnimation(parent: _a, curve: Interval(0.8 * k, math.min(1, 1.3 * k)));
    final glare = CurvedAnimation(parent: _a, curve: Interval(0.78, 1, curve: Curves.easeInOutSine));
    return AnimatedBuilder(
      animation: _a,
      builder: (context, _) {
        final body = Container(
          height: d,
          decoration: BoxDecoration(
            color: widget.brilliant ? null : color,
            gradient: widget.brilliant ? LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.25)!]) : null,
            borderRadius: BorderRadius.circular(d / 2),
          ),
          foregroundDecoration: null,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: roll.value,
                child: Padding(
                  padding: const EdgeInsets.only(left: 14, right: 8),
                  child: Text(label,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14,
                          shadows: [Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 2)])),
                ),
              ),
            ),
            // кружок со знаком катится вправо, пока раскрывается название
            Transform.rotate(
              angle: roll.value * 2 * math.pi,
              child: Container(
                width: d,
                height: d,
                padding: const EdgeInsets.all(3),
                child: Container(
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: StepGlyph(kind: kind, color: color, size: 17, shadow: false),
                ),
              ),
            ),
          ]),
        );
        return Transform.scale(
          scale: pop.value.clamp(0.0, 1.2),
          alignment: Alignment.centerLeft,
          child: Stack(clipBehavior: Clip.none, children: [
            if (loud && fly.value > 0 && fly.value < 1)
              Positioned.fill(child: CustomPaint(painter: FlyOutPainter(fly.value, color))),
            if (widget.brilliant)
              ClipRRect(
                borderRadius: BorderRadius.circular(d / 2),
                child: CustomPaint(foregroundPainter: _GlarePainter(glare.value), child: body),
              )
            else
              body,
          ]),
        );
      },
    );
  }
}

/// A thick straight shine at an angle, passing once across the frame.
class _GlarePainter extends CustomPainter {
  _GlarePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0 || t >= 1) return;
    const band = 18.0;
    final x = -band * 2 + (size.width + band * 4) * t;
    final path = Path()
      ..moveTo(x, size.height)
      ..lineTo(x + band, size.height)
      ..lineTo(x + band + size.height * 0.6, 0)
      ..lineTo(x + size.height * 0.6, 0)
      ..close();
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.75),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(x, 0, band + size.height * 0.6, size.height)),
    );
  }

  @override
  bool shouldRepaint(_GlarePainter old) => old.t != t;
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.muted = false});

  final String text;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
        color: muted ? null : scheme.secondaryContainer,
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: muted ? scheme.outline : scheme.onSecondaryContainer)),
    );
  }
}

/// Right side of the card: the best move, or — when the best was played —
/// the second line ("Other"), with the icon it would earn, even a poor one.
class _Suggestion extends StatelessWidget {
  const _Suggestion({required this.c, required this.ply, required this.played});

  final AnalysisController c;
  final int ply;
  final String played;

  @override
  Widget build(BuildContext context) {
    final alts = c.alternatives(ply);
    if (alts.isEmpty) return const SizedBox.shrink();
    final playedBest = alts.first.uci == played;
    final a = playedBest ? (alts.length > 1 ? alts[1] : null) : alts.first;
    if (a == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = markColor(a.kind);
    final small = theme.textTheme.bodyMedium?.copyWith(color: scheme.outline, fontWeight: FontWeight.w600, height: 1.2);
    // без заголовка: ход — на линии плашки хода, оценка — справа от него
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => c.playAlternative(ply, a.uci),
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: SizedBox(
          height: 30,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(a.san, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: color, height: 1.2)),
            const SizedBox(width: 4),
            StepGlyph(kind: a.kind, color: color, size: 18),
            const SizedBox(width: 6),
            Text(whiteEvalText(a.eval, a.side, c.unit), style: small),
          ]),
        ),
      ),
    );
  }
}

class LinesTable extends StatelessWidget {
  const LinesTable({super.key, required this.controller});

  final AnalysisController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    // позиция на доске — до хода ply + 1
    final next = c.atStart ? 0 : c.ply + 1;
    final Widget body;
    if (c.inVariation) {
      body = Text('Engine lines are stored for the game positions only.', style: TextStyle(color: scheme.outline));
    } else if (next >= c.length) {
      body = Text('The game is over: no lines after the last move.', style: TextStyle(color: scheme.outline));
    } else {
      final p = c.game.plies[next];
      final pos = Pos.fromFen(p.fenBefore);
      final where = next == 0 ? 'Start position' : 'After ${plyText(next - 1)} ${c.game.plies[next - 1].san}';
      body = Column(
        key: ValueKey(next),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              '$where: Stockfish, depth ${c.game.engine['depth']}, ${p.lines.length} lines'
              ' · blue: the line needs an only move',
              style: TextStyle(color: scheme.outline, fontSize: 12)),
          const SizedBox(height: 6),
          for (final (i, ln) in p.lines.indexed)
            InkWell(
              onTap: () => c.playAlternative(next, ln.move),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 58,
                    child: Text(whiteEvalText(ln.eval, pos.turn, c.unit == Unit.wdl ? Unit.wdl : Unit.pawns),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            // синяя оценка: линия требует only move
                            color: lineHasOnly(p.fenBefore, p.lines, i, c.game.scans?[next])
                                ? onlyBlue
                                : (i == 0 ? scheme.primary : scheme.onSurface),
                            fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                  Expanded(
                    // одна строка: длинная линия листается вбок и гаснет справа
                    child: FadedLine(_sanLine(pos, ln.pv),
                        style: TextStyle(fontSize: 13, color: ln.move == p.uci ? scheme.tertiary : null)),
                  ),
                ]),
              ),
            ),
          if (p.lines.every((l) => l.move != p.uci))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Played ${p.san}: ${whiteEvalText(p.played.eval, pos.turn, c.unit == Unit.wdl ? Unit.wdl : Unit.pawns)}',
                  style: TextStyle(color: scheme.tertiary, fontSize: 13)),
            ),
        ],
      );
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: body);
  }

  static String _sanLine(Pos start, List<String> pv) {
    var b = start;
    final out = <String>[];
    for (final (i, uci) in pv.take(20).indexed) {
      final m = Pos.move(uci);
      if (!b.isLegal(m)) break;
      final no = b.turn == Side.white ? '${b.fullmoves}. ' : (i == 0 ? '${b.fullmoves}... ' : '');
      out.add('$no${b.san(m)}');
      b = b.push(m);
    }
    return out.join(' ');
  }
}

/// Trick of a move in a lost position: a round sign with a white icon, no
/// name; a tap tells what the trick is.
class TrickBadge extends StatefulWidget {
  const TrickBadge({super.key, required this.trick});

  final Trick trick;

  @override
  State<TrickBadge> createState() => _TrickBadgeState();
}

class _TrickBadgeState extends State<TrickBadge> {
  bool _shown = false;

  @override
  void initState() {
    super.initState();
    // появляется плавно, когда карточка уже встала на место
    Future<void>.delayed(const Duration(milliseconds: 420), () {
      if (mounted) setState(() => _shown = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.trick;
    final how = [
      if (t.stalemates > 0) '${t.stalemates} stalemate${t.stalemates == 1 ? '' : 's'}',
      if (t.perpetuals > 0) '${t.perpetuals} with perpetual check',
    ];
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOut,
      child: Semantics(
        label: 'Trick',
        child: InkResponse(
          radius: 18,
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              icon: const Icon(Icons.auto_fix_high_rounded),
              title: const Text('Trick'),
              content: Text('The position is lost, but ${t.traps} of the opponent\'s ${t.legal} moves let it slip to a '
                  'draw${how.isEmpty ? '' : ' (${how.join(', ')})'}. The more there are, the better the chance.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
            ),
          ),
          child: SizedBox.square(
            dimension: 30,
            child: Icon(Icons.auto_fix_high_rounded,
                size: 20,
                color: Colors.white,
                shadows: const [Shadow(color: Color(0x99000000), blurRadius: 3)]),
          ),
        ),
      ),
    );
  }
}
