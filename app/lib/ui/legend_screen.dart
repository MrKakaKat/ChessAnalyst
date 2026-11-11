/// Icon legend: every step icon in display order, as a badge (board) and as a
/// sign (move list). The play button (or a tap on a badge) replays the
/// badge's board animation: flash, jump, outline flying out, waving flag.
library;

import 'package:flutter/material.dart';

import 'labels.dart';
import 'puzzle_screen.dart' show DartHit, DartboardPainter;
import 'step_icons.dart';
import 'widgets/board_view.dart' show BoardBadge;

const _names = {
  'brilliant': 'Brilliant',
  'only_move': 'Only move',
  'only_light': 'Only move low',
  'mate': 'Checkmate',
  'resign': 'Resign',
  'timeout': 'Time out',
  'draw': 'Draw',
  ...stepLabels,
};

const _kinds = [...iconKinds, 'resign', 'timeout', 'draw'];

class LegendScreen extends StatefulWidget {
  const LegendScreen({super.key});

  @override
  State<LegendScreen> createState() => _LegendScreenState();
}

class _LegendScreenState extends State<LegendScreen> {
  int _all = 0;
  final _one = <String, int>{};

  /// The icon shown large in the middle (null: none).
  String? _zoom;

  void _tap(String k) => setState(() {
    _one[k] = (_one[k] ?? 0) + 1;
    _zoom = k;
  });

  Color _color(String k) => k == 'resign' || k == 'draw' ? markColor('neutral') : markColor(k);

  /// The tapped icon, large, over the dimmed screen; a tap closes it. The
  /// play button above stays active and replays it.
  Widget _zoomed(String k) {
    const d = 168.0;
    return GestureDetector(
      key: ValueKey('zoom-$k'),
      onTap: () => setState(() => _zoom = null),
      child: Container(
        color: Colors.black.withValues(alpha: 0.62),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox.square(
              dimension: d,
              child: k == 'dart'
                  ? OverflowBox(
                      maxWidth: d * 1.6,
                      maxHeight: d * 1.6,
                      child: DartHit(key: ValueKey('zdart-$_all-${_one['dart']}'), size: d),
                    )
                  : BoardBadge(key: ValueKey('z$k-$_all-${_one[k]}'), kind: k, size: d, color: _color(k)),
            ),
            const SizedBox(height: 20),
            if (k != 'dart') StepGlyph(kind: k, size: 40, color: _color(k)),
            const SizedBox(height: 10),
            Text(
              k == 'dart' ? 'Puzzle solved' : _names[k]!,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Icons'),
        actions: [
          IconButton(
            tooltip: 'Play the animations',
            onPressed: () => setState(() => _all++),
            icon: const Icon(Icons.play_circle_outline_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Tap a badge to see it large and replay its animation.',
                style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  for (final k in _kinds)
                    SizedBox(
                      width: 96,
                      child: Column(
                        children: [
                          GestureDetector(
                            onTap: () => _tap(k),
                            child: SizedBox.square(
                              dimension: 48,
                              child: _all == 0 && (_one[k] ?? 0) == 0
                                  ? StepIcon(kind: k, size: 48, color: k == 'resign' ? markColor('neutral') : null)
                                  : BoardBadge(
                                      key: ValueKey('$k-$_all-${_one[k]}'),
                                      kind: k,
                                      size: 48,
                                      color: k == 'resign' ? markColor('neutral') : markColor(k),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          StepGlyph(kind: k, size: 18, color: markColor(k == 'resign' ? 'neutral' : k)),
                          const SizedBox(height: 4),
                          Text(_names[k]!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  // задача решена: мишень с дротиком
                  SizedBox(
                    width: 96,
                    child: Column(
                      children: [
                        GestureDetector(
                          onTap: () => _tap('dart'),
                          child: SizedBox.square(
                            dimension: 48,
                            child: _all == 0 && (_one['dart'] ?? 0) == 0
                                ? const CustomPaint(painter: DartboardPainter())
                                : OverflowBox(
                                    maxWidth: 48 * 1.6,
                                    maxHeight: 48 * 1.6,
                                    child: DartHit(key: ValueKey('dart-$_all-${_one['dart']}'), size: 48),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 28),
                        const Text('Puzzle solved', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          // нажатая иконка — крупно в середине, фон затемнён
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: _zoom == null ? const SizedBox.shrink() : _zoomed(_zoom!),
            ),
          ),
        ],
      ),
    );
  }
}
