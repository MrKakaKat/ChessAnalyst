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
  static const _prefix = 'history.';
  final _jobs = <String, AnalysisJob>{};
  List<HistoryEntry> entries = [];

  /// Games marked as favourites, by analysis id. Kept apart from the
  /// analyses (key outside "history."), so analysing again keeps the mark.
  static const _favKey = 'favorites.history';
  final favorites = <String>{};

  bool isFavorite(String id) => favorites.contains(id);

  Future<void> toggleFavorite(String id) async {
    favorites.contains(id) ? favorites.remove(id) : favorites.add(id);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_favKey, favorites.toList());
    } catch (_) {}
  }

  /// Writes go one after another: a save never overtakes a load.
  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() f) {
    final out = _queue.then((_) => f());
    _queue = out.then((_) {}, onError: (_) {});
    return out;
  }

  bool _loaded = false;

  /// Reads the history. [авторское] The list is rebuilt from every stored
  /// analysis, not only from the index: an index written before the history
  /// was loaded (a queued analysis saving itself at start) once held only
  /// that game, and the other analyses seemed lost; they come back here.
  Future<void> load() => _serial(() async {
        try {
          final p = await SharedPreferences.getInstance();
          favorites
            ..clear()
            ..addAll(p.getStringList(_favKey) ?? const []);
          final indexed = p.getStringList(_index) ?? [];
          final stored = [
            for (final k in p.getKeys())
              if (k.startsWith(_prefix) && k != _index) k.substring(_prefix.length),
          ];
          final ids = [...indexed, for (final id in stored) if (!indexed.contains(id)) id];
          final out = <HistoryEntry>[];
          for (final id in ids) {
            final live = _jobs[id];
            if (live != null) {
              out.add(_entry(live));
              continue;
            }
            final raw = p.getString('$_prefix$id');
            if (raw == null) continue;
            try {
              out.add(_entry(AnalysisJob.fromJson(jsonDecode(raw) as Map<String, dynamic>)));
            } catch (_) {
              // повреждённая запись — пропускается, остальные читаются
            }
          }
          // разборы в памяти, ещё не записанные на устройство
          for (final j in _jobs.values) {
            if (!out.any((e) => e.id == j.id)) out.add(_entry(j));
          }
          out.sort((a, b) => b.created.compareTo(a.created));
          entries = out;
          _loaded = true;
          await p.setStringList(_index, [for (final e in entries) e.id]);
          notifyListeners();
        } catch (_) {}
      });

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
    if (!_loaded) await load();
    await _serial(() async {
      entries = [_entry(job), ...entries.where((e) => e.id != job.id)];
      notifyListeners();
      try {
        final p = await SharedPreferences.getInstance();
        await p.setString('$_prefix${job.id}', jsonEncode(job.toJson()));
        // индекс — объединение записанного и известного: ничего не теряется
        final known = p.getStringList(_index) ?? [];
        final ids = [for (final e in entries) e.id];
        await p.setStringList(_index, [...ids, for (final id in known) if (!ids.contains(id)) id]);
      } catch (_) {
        // хранилище переполнено или недоступно — разбор остаётся в памяти
      }
    });
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

  Future<void> remove(String id) => _serial(() async {
        _jobs.remove(id)?.pause();
        entries = entries.where((e) => e.id != id).toList();
        notifyListeners();
        try {
          final p = await SharedPreferences.getInstance();
          await p.remove('$_prefix$id');
          if (favorites.remove(id)) await p.setStringList(_favKey, favorites.toList());
          await p.setStringList(_index, [
            for (final x in p.getStringList(_index) ?? <String>[])
              if (x != id) x,
          ]);
        } catch (_) {}
      });
}

final history = HistoryStore();
