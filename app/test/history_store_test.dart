import 'dart:convert';
import 'dart:io';

import 'package:chessanalyst/analysis/pgn_import.dart';
import 'package:chessanalyst/engine/game_job.dart';
import 'package:chessanalyst/ui/history_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AnalysisJob _job(String id, DateTime created) => AnalysisJob(
    id: id,
    source: importPgn(File('../examples/opera_game.pgn').readAsStringSync()),
    targetDepth: 14,
    created: created);

void main() {
  test('saving before the history is loaded keeps the other analyses', () async {
    // на устройстве три разбора, но индекс — только с одним (как после бага)
    SharedPreferences.setMockInitialValues({
      'history.index': ['b'],
      for (final (i, id) in ['a', 'b', 'c'].indexed)
        'history.$id': jsonEncode(_job(id, DateTime(2026, 11, 1 + i)).toJson()),
    });
    final store = HistoryStore();
    // разбор из очереди сохраняется раньше, чем история прочитана
    await store.save(_job('d', DateTime(2026, 11, 5)));
    expect({for (final e in store.entries) e.id}, {'a', 'b', 'c', 'd'});
    final p = await SharedPreferences.getInstance();
    expect(p.getStringList('history.index')!.toSet(), {'a', 'b', 'c', 'd'});
    // повторное чтение — тот же список, свежие сверху
    await store.load();
    expect([for (final e in store.entries) e.id], ['d', 'c', 'b', 'a']);
  });
}
