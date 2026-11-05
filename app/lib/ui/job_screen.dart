/// The analysis of a game on the device: progress, the time left, pause and
/// resume. The analysis runs in the background: this screen can be left
/// (the ring at the bottom right brings it back). With "quick pass first" the
/// game opens as soon as the quick pass is done.
library;

import 'package:flutter/material.dart';

import '../analysis/openings.dart';
import '../engine/game_job.dart';
import 'analysis_queue.dart';
import 'controller.dart';
import 'game_screen.dart';

class JobScreen extends StatefulWidget {
  const JobScreen({super.key, required this.job, required this.book, this.autoOpen = true});

  final AnalysisJob job;

  /// Opens the game when it is ready (after the import). From the progress
  /// ring it stays on this screen: the game opens with its button.
  final bool autoOpen;
  final OpeningBook book;

  @override
  State<JobScreen> createState() => _JobScreenState();
}

class _JobScreenState extends State<JobScreen> {
  bool _opened = false;

  AnalysisJob get job => widget.job;

  @override
  void initState() {
    super.initState();
    job.addListener(_onJob);
    analysisQueue.addListener(_onJob);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onJob());
  }

  @override
  void dispose() {
    job.removeListener(_onJob);
    analysisQueue.removeListener(_onJob);
    super.dispose();
  }

  void _onJob() {
    if (!mounted) return;
    if (widget.autoOpen && job.ready && !_opened) {
      _opened = true;
      _openGame();
      return;
    }
    setState(() {});
  }

  void _openGame() => Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => GameScreen(controller: AnalysisController(job.snapshot(), book: widget.book), job: job),
      ));

  /// Stops the analysis and takes it out of the queue; what is done stays in
  /// the history and can be resumed there.
  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel the analysis?'),
        content: const Text('It leaves the queue. What is analysed stays in the history, where it can be resumed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cancel analysis')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    job.pause();
    analysisQueue.remove(job);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final waiting = job.state != JobState.running &&
        !job.pausedByUser &&
        job.state != JobState.failed &&
        analysisQueue.jobs.any((j) => j.state == JobState.running && j != job);
    final title = switch (job.state) {
      JobState.failed => 'The engine stopped',
      JobState.paused when waiting => 'Waiting in the queue',
      JobState.paused => 'Paused',
      _ => job.quickFirst && job.depth < quickDepth
          ? 'Quick pass (depth $quickDepth)'
          : 'Analysis at depth ${job.targetDepth}',
    };
    final mode = job.quickFirst
        ? 'Quick pass first: the game opens at about 30%, then the analysis goes on to depth ${job.targetDepth}.'
        : 'Full depth ${job.targetDepth}: the game opens when the analysis is done.';
    return Scaffold(
      appBar: AppBar(title: Text(job.title, overflow: TextOverflow.ellipsis)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // кружок с внутренним огоньком: горит, пока движок считает
            SizedBox.square(dimension: 64, child: JobRing(job: job, stroke: 5)),
            const SizedBox(height: 8),
            Text(
              switch (job.state) {
                JobState.running => job.thinking ? 'The engine is computing' : 'Resting between positions (power saving)',
                JobState.failed => 'Stopped',
                _ => 'Not running',
              },
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            TweenAnimationBuilder<double>(
              tween: Tween(end: job.progress),
              duration: const Duration(milliseconds: 300),
              builder: (context, v, _) => LinearProgressIndicator(value: v, minHeight: 6),
            ),
            const SizedBox(height: 10),
            Text('${(job.progress * 100).round()}% · ${job.length} positions · ${job.multipv} lines',
                style: TextStyle(color: scheme.outline)),
            const SizedBox(height: 4),
            Text(job.done ? 'Done' : 'About ${durationText(job.eta)} left',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            Text(mode, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.outline)),
            if (job.error != null) ...[
              const SizedBox(height: 10),
              Text(job.error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 20),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              if (job.state == JobState.running)
                OutlinedButton.icon(onPressed: job.pause, icon: const Icon(Icons.pause_rounded), label: const Text('Pause'))
              else
                FilledButton.icon(
                    onPressed: () => analysisQueue.resume(job),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Resume')),
              if (job.ready)
                FilledButton.tonalIcon(
                    onPressed: _openGame, icon: const Icon(Icons.visibility_rounded), label: const Text('Open the game')),
              OutlinedButton.icon(
                onPressed: _cancel,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel'),
                style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
              ),
              // анализ идёт в фоне: можно решать задачи или смотреть другие партии
              TextButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Continue in the background'),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
