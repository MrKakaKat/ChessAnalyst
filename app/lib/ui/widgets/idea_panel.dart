/// Idea chains of the game and their playback.
///
/// "Play chain" walks the board through the chain: from the idea's start
/// through the owner's moves to the miss, the error and the punishing reply;
/// pieces move and a red arrow shows the attacker and its target. The timeline
/// below fills node by node.
library;

import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';

import '../../analysis/ideas.dart';
import '../controller.dart';
import '../labels.dart';
import '../prefs.dart';
import 'move_detail.dart';

final _keys = <int, GlobalKey>{};

/// The idea the list was last scrolled to (or chosen in the list itself).
Idea? _scrolledTo;

void _scrollTo(int i) {
  // после того как шкала прошлой идеи свернётся, иначе список сдвигается и
  // прокрутка проскакивает блок
  Future<void>.delayed(const Duration(milliseconds: 300), () {
    final ctx = _keys[i]?.currentContext;
    if (ctx != null && ctx.mounted) {
      Scrollable.ensureVisible(ctx, alignment: 0.02, duration: const Duration(milliseconds: 350), curve: Curves.easeInOutCubic);
    }
  });
}

class IdeaPanel extends StatelessWidget {
  const IdeaPanel({super.key, required this.controller, this.bottomPadding = 0});

  final AnalysisController controller;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: prefs, builder: (context, _) => _build(context));

  Widget _build(BuildContext context) {
    final c = controller;
    final all = c.analysis.ideas;
    final scheme = Theme.of(context).colorScheme;
    if (all.isEmpty) {
      return const Center(child: Text('No errors with an idea chain in this game.'));
    }
    // фильтр: только серьёзные тактики, идеи выбранных сторон (выбранная
    // снаружи идея видна всегда)
    bool shown(Idea x) =>
        identical(x, c.selectedIdea) ||
        ((!prefs.seriousIdeas || isSeriousIdea(x)) &&
            (x.owner == Side.white ? prefs.whiteIdeas : prefs.blackIdeas));
    final visible = [for (final (i, x) in all.indexed) if (shown(x)) (i, x)];
    final hidden = all.length - visible.length;
    // идея выбрана снаружи (блок идеи в окне хода) — листаем к ней
    final chosen = c.selectedIdea;
    if (chosen != null && !identical(chosen, _scrolledTo)) {
      _scrolledTo = chosen;
      final i = all.indexWhere((x) => identical(x, chosen));
      if (i >= 0) _scrollTo(i);
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 16 + bottomPadding),
      children: [
        _IdeaFilter(hidden: hidden),
        const SizedBox(height: 4),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No ideas match the filter.', style: TextStyle(color: scheme.outline))),
          ),
        for (final (k, (i, idea)) in visible.indexed) ...[
          _IdeaTile(
            key: _keys.putIfAbsent(i, GlobalKey.new),
            idea: idea,
            controller: c,
            selected: identical(idea, c.selectedIdea),
            // ▼ — к следующей идее: выбирает её и прокручивает список
            onNext: () {
              final (next, nextIdea) = visible[(k + 1) % visible.length];
              _scrolledTo = nextIdea;
              c.selectIdea(nextIdea);
              _scrollTo(next);
            },
          ),
          // шкала цепочки — сразу под выбранной идеей, чтобы не листать
          AnimatedSize(
            duration: const Duration(milliseconds: 280),
            curve: Curves.easeInOutCubic,
            child: identical(idea, c.selectedIdea)
                ? Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _ChainTimeline(controller: c, idea: idea),
                      // под станциями — что показывается сейчас
                      _PhaseLine(controller: c),
                      Text('Red arrow: the attacking piece and its target in each position of the idea.',
                          style: TextStyle(fontSize: 12, color: scheme.outline)),
                    ]),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ],
    );
  }
}

/// A serious tactic: mate, fork, pin, discovered attack, promotion, or a
/// chain of more than one move. A piece left hanging for one move is not.
bool isSeriousIdea(Idea i) =>
    const {'mate', 'fork', 'pin', 'discovered', 'promotion'}.contains(i.signature.motif) || (i.distance ?? 0) >= 2;

/// Filter row: "Serious tactics", and two circles for White's and Black's
/// ideas (a second outline marks the chosen ones).
class _IdeaFilter extends StatelessWidget {
  const _IdeaFilter({required this.hidden});

  final int hidden;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget side(bool white) {
      final on = white ? prefs.whiteIdeas : prefs.blackIdeas;
      final other = white ? prefs.blackIdeas : prefs.whiteIdeas;
      return Tooltip(
        message: white ? "White's ideas" : "Black's ideas",
        // без подсветки нажатия: выбор показывает второй контур
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // хотя бы одна сторона остаётся выбранной
          onTap: () {
            if (on && !other) return;
            prefs.update(white: white ? !on : null, black: white ? null : !on);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 34,
            height: 34,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: on ? scheme.tertiary : Colors.transparent, width: 2),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: white ? const Color(0xFFF2F2F2) : const Color(0xFF202020),
                border: Border.all(color: scheme.outline, width: 1),
              ),
            ),
          ),
        ),
      );
    }

    return Row(children: [
      FilterChip(
        label: const Text('Serious tactics'),
        selected: prefs.seriousIdeas,
        onSelected: (v) => prefs.update(serious: v),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(hidden > 0 ? '$hidden hidden' : '',
            style: TextStyle(fontSize: 12, color: scheme.outline), overflow: TextOverflow.ellipsis),
      ),
      side(true),
      const SizedBox(width: 4),
      side(false),
    ]);
  }
}

class _IdeaTile extends StatelessWidget {
  const _IdeaTile({super.key, required this.idea, required this.controller, required this.selected, required this.onNext});

  final Idea idea;
  final AnalysisController controller;
  final bool selected;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final scheme = Theme.of(context).colorScheme;
    final san = c.game.plies[idea.punishPly].san;
    final title = switch (idea.kind) {
      'pass' => 'Pass: ${plyText(idea.punishPly)} $san',
      'brilliant' => 'Brilliant: ${plyText(idea.punishPly)} $san',
      _ => '${plyText(idea.punishPly)} $san: ${idea.victim.name == 'white' ? 'White' : 'Black'} error',
    };
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: selected ? scheme.tertiaryContainer : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: selected ? scheme.tertiary : scheme.outlineVariant, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          // выбор в самом списке — без прокрутки
          _scrolledTo = selected ? null : idea;
          c.selectIdea(selected ? null : idea);
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (selected)
                IconButton(
                  tooltip: 'Next idea',
                  onPressed: onNext,
                  icon: Transform.rotate(
                    angle: 1.5708, // тот же треугольник, вершиной вниз
                    child: CustomPaint(size: const Size.square(22), painter: PlayStopPainter(0, scheme.onSurfaceVariant)),
                  ),
                ),
              // в начало идеи — без сброса паузы на старт
              if (selected)
                IconButton(
                  tooltip: 'Back to the start of the idea',
                  onPressed: c.ideaFrames.isEmpty ? null : c.restartIdea,
                  icon: const Icon(Icons.replay_rounded),
                ),
              if (selected)
                IconButton.filled(
                  tooltip: c.playing ? 'Pause' : 'Play the idea',
                  onPressed: c.playing ? c.stopChain : c.playChain,
                  icon: TweenAnimationBuilder<double>(
                    tween: Tween(end: c.playing ? 1 : 0),
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeInOutCubic,
                    builder: (context, v, _) => CustomPaint(
                      size: const Size.square(24),
                      painter: PlayStopPainter(v, Theme.of(context).colorScheme.onPrimary),
                    ),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            ChunkView(idea: idea),
            const SizedBox(height: 4),
            Text(
              'Key move ${idea.signature.keySan}${idea.distance != null ? ' · Distance ${idea.distance}' : ''}',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ]),
        ),
      ),
    );
  }
}

class _ChainTimeline extends StatelessWidget {
  const _ChainTimeline({required this.controller, required this.idea});

  final AnalysisController controller;
  final Idea idea;

  static const _inset = 40.0;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final plies = c.chainPlies(idea);
    final scheme = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    final reached = plies.lastIndexWhere((p) => p <= c.ply);
    final punishing = c.punishes(idea) ? idea.punishPly + 1 : -1;

    // Узел — выбранный полуход (позиция после него).
    String role(int p) {
      if (p == punishing) return 'Punishment';
      if (idea.kind == 'pass' && p == idea.punishPly) return 'Pass';
      if (idea.kind == 'brilliant' && p == idea.punishPly) return 'Brilliant';
      if (idea.kind == 'brilliant' && p > idea.punishPly) return p == idea.punishPly + 1 ? 'Consequences' : '';
      if (p == idea.missPly) return idea.missPly == idea.punishPly ? 'Error' : 'Miss';
      if (p == idea.punishPly) return 'Error';
      if (p == idea.startPly - 1) return 'Start';
      if (c.onlySince(idea) case final s? when p == s - 1) return 'Only move since';
      if (c.beganWith(idea) case final s? when p == s - 1) return 'Began with ${plyText(s)} ${c.game.plies[s].san}';
      return '';
    }

    Color nodeColor(int p) {
      if (idea.kind == 'brilliant' && p == idea.punishPly) return brilliantColor;
      if (p == punishing) return stepColor('blunder', b);
      if (p == idea.missPly || p == idea.punishPly) return stepColor('mistake', b);
      if (p == idea.startPly - 1) return scheme.tertiary;
      return scheme.primary;
    }

    return SizedBox(
      height: 74,
      child: LayoutBuilder(builder: (context, box) {
        final n = plies.length;
        final gap = n > 1 ? (box.maxWidth - 2 * _inset) / (n - 1) : 0.0;
        return Stack(children: [
          Positioned(
            left: _inset, right: _inset, top: 19,
            child: Container(height: 3, color: scheme.outlineVariant),
          ),
          AnimatedPositioned(
            duration: const Duration(milliseconds: 600),
            curve: Curves.easeInOutCubic,
            left: _inset,
            top: 19,
            width: reached <= 0 ? 0 : gap * reached,
            child: Container(height: 3, color: scheme.tertiary),
          ),
          for (final (i, p) in plies.indexed)
            Positioned(
              left: (n > 1 ? _inset + gap * i : box.maxWidth / 2) - 36,
              top: 0,
              width: 72,
              height: 74,
              child: GestureDetector(
                // вся область станции, а не только кружок и подпись
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  c.stopChain();
                  c.select(p);
                },
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutBack,
                    width: p == c.ply ? 22 : 14,
                    height: p == c.ply ? 22 : 14,
                    margin: EdgeInsets.all(p == c.ply ? 9 : 13),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i <= reached ? nodeColor(p) : scheme.surface,
                      border: Border.all(color: nodeColor(p), width: 2.5),
                    ),
                  ),
                  Text('${plyText(p)} ${c.game.plies[p].san}', style: const TextStyle(fontSize: 11), maxLines: 1),
                  Text(role(p), style: TextStyle(fontSize: 10, color: nodeColor(p))),
                ]),
              ),
            ),
        ]);
      }),
    );
  }
}

/// Play/stop morph ([t] 0: play, 1: stop): the triangle's sides spread out and
/// its point opens into the square's right edge.
class PlayStopPainter extends CustomPainter {
  PlayStopPainter(this.t, this.color);

  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    Offset lerp(Offset a, Offset b) => Offset.lerp(a, b, t)! * s;
    const play = [Offset(0.3, 0.2), Offset(0.82, 0.5), Offset(0.82, 0.5), Offset(0.3, 0.8)];
    const stop = [Offset(0.24, 0.24), Offset(0.76, 0.24), Offset(0.76, 0.76), Offset(0.24, 0.76)];
    final pts = [for (var i = 0; i < 4; i++) lerp(play[i], stop[i])];
    final path = Path()..addPolygon(pts, true);
    final paint = Paint()
      ..color = color
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = s * 0.1;
    canvas.drawPath(path, paint..style = PaintingStyle.fill);
    canvas.drawPath(path, paint..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(PlayStopPainter old) => old.t != t || old.color != color;
}

/// What the idea's playback shows now: the game, the punishment or the
/// better line (one line under the stations).
class _PhaseLine extends StatelessWidget {
  const _PhaseLine({required this.controller});

  final AnalysisController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final phase = controller.ideaPhase;
    final text = switch (phase) {
      'game' => 'Now: the game',
      'punishment' => 'Now: the punishment — the opponent\'s best line after the error',
      'better' => 'Now: the better line — what was missed before the error',
      'brilliant' => 'Now: the line of the brilliant move',
      _ => controller.ideaFramesDone ? '' : 'Preparing the lines of the idea…',
    };
    return SizedBox(
      height: 20,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        child: Text(text,
            key: ValueKey(text),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: phase == 'punishment' ? scheme.error : (phase == null ? scheme.outline : scheme.tertiary))),
      ),
    );
  }
}
