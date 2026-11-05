/// Analyze my game: paste a PGN, choose depth and power, start. The quick
/// pass runs first (the analysis opens as soon as it ends), then the chosen
/// depth; the game screen refreshes as the engine goes.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../analysis/openings.dart';
import '../analysis/pgn_import.dart';
import '../engine/game_job.dart';
import 'history_store.dart';
import 'home_screen.dart' show PawnIcon;
import 'analysis_queue.dart';
import 'job_screen.dart';
import 'prefs.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.book});

  final OpeningBook book;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _text = TextEditingController();
  int _depth = depthPresets['Standard']!;
  EnginePower _power = EnginePower.medium;

  /// Stop after the quick pass (depth 8), or go on to the chosen depth.
  bool _quickOnly = false;
  String? _error;
  ImportedGame? _preview;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  static String _depthName(int d) => d <= 8 ? 'quick look' : d <= 12 ? 'quick' : d <= 16 ? 'standard' : d <= 20 ? 'deep' : 'maximum';

  void _parse() {
    try {
      final g = importPgn(_text.text);
      setState(() {
        _preview = g;
        _error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        _preview = null;
        _error = _text.text.trim().isEmpty ? null : e.message;
      });
    } catch (e) {
      setState(() {
        _preview = null;
        _error = 'Not a PGN: $e';
      });
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text == null) return;
    _text.text = data!.text!;
    _parse();
  }

  /// The analysis in the history with the same moves, if any.
  Future<String?> _duplicateOf(ImportedGame g) async {
    await history.load();
    for (final e in history.entries) {
      final job = await history.open(e.id);
      if (job == null) continue;
      final s = job.source;
      if (s.startFen == g.startFen && s.ucis.length == g.ucis.length && s.ucis.join(' ') == g.ucis.join(' ')) {
        return e.id;
      }
    }
    return null;
  }

  /// Once: how to let the analysis run with the screen off (Android).
  Future<void> _batteryHint() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android || prefs.batteryHintShown) return;
    prefs.update(batteryHint: true);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Analysis in the background'),
        content: const Text(
            'The analysis goes on while you use other screens. To keep it running with the screen off or the app '
            'in the background, allow it in Android settings: Apps → ChessAnalyst → Battery → Unrestricted (also '
            'turn off "Pause app activity if unused"). If Android stops it anyway, it continues from the same '
            'position when you open the app again.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Got it'))],
      ),
    );
  }

  Future<void> _start() async {
    final g = _preview;
    if (g == null) return;
    // та же партия уже разобрана — предупредить
    final dup = await _duplicateOf(g);
    if (!mounted) return;
    if (dup != null) {
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Already analysed'),
          content: const Text('This game (the same moves) is already in your history.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, 'again'), child: const Text('Analyze again')),
            FilledButton(onPressed: () => Navigator.pop(context, 'open'), child: const Text('Open it')),
          ],
        ),
      );
      if (!mounted || choice == null) return;
      if (choice == 'open') {
        final job = await history.open(dup);
        if (!mounted || job == null) return;
        if (job.stalled) analysisQueue.add(job);
        Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (_) => JobScreen(job: job, book: widget.book)));
        return;
      }
    }
    final job = AnalysisJob(
      id: 'game_${DateTime.now().millisecondsSinceEpoch}',
      source: g,
      targetDepth: _depth,
      quickFirst: _quickOnly,
      multipv: prefs.engineLines,
      power: _power,
    );
    // в очередь: если движок занят другой партией, эта ждёт своей очереди
    analysisQueue.add(job);
    await _batteryHint();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => JobScreen(job: job, book: widget.book)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = Theme.of(context).textTheme.titleMedium;
    final g = _preview;
    return Scaffold(
      appBar: AppBar(title: const Text('Analyze my game')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Row(children: [
          Expanded(child: Text('PGN', style: title)),
          TextButton.icon(onPressed: _paste, icon: const Icon(Icons.content_paste_rounded), label: const Text('Paste')),
        ]),
        TextField(
          controller: _text,
          minLines: 5,
          maxLines: 10,
          onChanged: (_) => _parse(),
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: '[White "..."]\n1. e4 e5 2. Nf3 ...',
            errorText: _error,
          ),
        ),
        if (g != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('${g.title} · ${g.headers['result']} · ${(g.sans.length + 1) ~/ 2} moves',
                style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)),
          ),
        const SizedBox(height: 20),
        Text('Analysis', style: title),
        const SizedBox(height: 6),
        // quick: быстрый проход (партия сразу открывается), дальше анализ сам
        // идёт до глубины, пока ты смотришь; full: сразу на всю глубину,
        // партия открывается, когда готово всё
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Quick pass first'), icon: Icon(Icons.speed_rounded)),
            ButtonSegment(value: false, label: Text('Full depth'), icon: Icon(Icons.layers_rounded)),
          ],
          selected: {_quickOnly},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _quickOnly = s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
              _quickOnly
                  ? 'The game opens after a quick pass at depth $quickDepth (about 30%), then the analysis goes on to '
                      'depth $_depth while you read it.'
                  : 'One pass at depth $_depth: the game opens when the whole analysis is done.',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
        const SizedBox(height: 12),
        Text('Depth $_depth (${_depthName(_depth)})', style: title),
        // ползунок с фиксацией на каждой глубине
        Slider(
          value: _depth.toDouble(),
          min: 1,
          max: maxDepth.toDouble(),
          divisions: maxDepth - 1,
          label: '$_depth',
          onChanged: (v) => setState(() => _depth = v.round()),
        ),
        Text('Lines per move: ${prefs.engineLines}', style: title),
        Slider(
          value: prefs.engineLines.toDouble(),
          min: 5,
          max: 25,
          divisions: 20,
          label: '${prefs.engineLines}',
          onChanged: (v) => setState(() => prefs.update(lines: v.round())),
        ),
        // примерное время: по числу ходов партии, глубине, линиям и мощности
        if (g != null)
          Text(
              'About ${durationText(estimateDuration(g.sans.length, _depth, prefs.engineLines, _power, quickFirst: _quickOnly))} '
              'for ${g.sans.length} positions (a rough guess; the analysis screen refines it as it goes).',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        const SizedBox(height: 20),
        Text('Power', style: title),
        const SizedBox(height: 6),
        SegmentedButton<EnginePower>(
          segments: const [
            ButtonSegment(value: EnginePower.low, label: Text('Low'), icon: Icon(Icons.eco_outlined)),
            ButtonSegment(value: EnginePower.medium, label: Text('Medium')),
            ButtonSegment(value: EnginePower.high, label: Text('High'), icon: Icon(Icons.bolt_rounded)),
          ],
          selected: {_power},
          showSelectedIcon: false,
          onSelectionChanged: (s) => setState(() => _power = s.first),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              switch (_power) {
                EnginePower.low => 'One thread and long pauses: slow, keeps the phone cool.',
                EnginePower.medium => 'Two threads with short pauses.',
                EnginePower.high => 'All but one core, no pauses: fastest, the phone gets warm.',
              },
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
              onPressed: g == null ? null : _start, icon: const PawnIcon(), label: const Text('Analyze')),
        ),
      ]),
    );
  }
}
