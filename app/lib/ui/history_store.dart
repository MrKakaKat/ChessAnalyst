/// History of the user's analyses, kept on the device.
///
/// [простое решение] Stored with shared_preferences (localStorage on the web):
/// an index of ids and one JSON entry per analysis. Running jobs stay in
/// memory, so the history can reattach to one that is still being computed.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/settings.dart';
import '../engine/game_job.dart';

class HistoryEntry {
  const HistoryEntry(this.id, this.title, this.date, this.created, this.depth, this.target, this.progress,
      {this.finished, this.rules = analysisRules});

  final String id, title, date;
  final DateTime created;

  /// When the analysis was finished.
  final DateTime? finished;

  /// Version of the analysis rules it was made with.
  final int rules;

  /// Made with older rules: marked to be analysed again.
  bool get outdated => rules < analysisRules;
  final int depth, target;
  final double progress;
}

class HistoryStore extends ChangeNotifier {
  static const _index = 'history.index';
  final _jobs = <String, AnalysisJob>{};
  List<HistoryEntry> entries = [];

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final ids = p.getStringList(_index) ?? [];
      final out = <HistoryEntry>[];
      for (final id in ids) {
        final raw = p.getString('history.$id');
        if (raw == null) continue;
        final m = jsonDecode(raw) as Map<String, dynamic>;
        out.add(_entry(AnalysisJob.fromJson(m)));
      }
      entries = out;
      notifyListeners();
    } catch (_) {}
  }

  HistoryEntry _entry(AnalysisJob j) => HistoryEntry(
      j.id, j.title, j.source.headers['date'] ?? '', j.created, j.depth, j.targetDepth, j.progress,
      finished: j.finished, rules: j.rules);

  /// Registers a job: it is saved as it goes.
  void track(AnalysisJob job) {
    _jobs[job.id] = job;
    job.onSave = save;
    save(job);
  }

  Future<void> save(AnalysisJob job) async {
    entries = [_entry(job), ...entries.where((e) => e.id != job.id)];
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('history.${job.id}', jsonEncode(job.toJson()));
      await p.setStringList(_index, [for (final e in entries) e.id]);
    } catch (_) {
      // хранилище переполнено или недоступно — разбор остаётся в памяти
    }
  }

  /// The job of [id]: the running one, or restored from the device.
  Future<AnalysisJob?> open(String id) async {
    final live = _jobs[id];
    if (live != null) return live;
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('history.$id');
      if (raw == null) return null;
      final job = AnalysisJob.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      _jobs[id] = job;
      job.onSave = save;
      return job;
    } catch (_) {
      return null;
    }
  }

  Future<void> remove(String id) async {
    _jobs.remove(id)?.pause();
    entries = entries.where((e) => e.id != id).toList();
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('history.$id');
      await p.setStringList(_index, [for (final e in entries) e.id]);
    } catch (_) {}
  }
}

final history = HistoryStore();
