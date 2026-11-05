import 'dart:io';

import 'package:chessanalyst/analysis/character.dart';
import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/pos.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('position character: trivial, sharp and quiet are all met in the showcase games', () {
    final seen = <String, int>{};
    final watch = Stopwatch()..start();
    for (final name in ['byrne_fischer_1956', 'kasparov_topalov_1999', 'morphy_opera_1858']) {
      final g = GameData.parse(File('assets/games/$name.json').readAsStringSync());
      for (var i = 0; i < g.plies.length; i++) {
        final p = g.plies[i];
        final ch = characterOf(Pos.fromFen(p.fenBefore), p.lines, p.allLines, const Settings());
        final key = '${ch.sharpness?.name ?? 'unknown'}${ch.quiet ? '+quiet' : ''}';
        seen[key] = (seen[key] ?? 0) + 1;
      }
    }
    // ignore: avoid_print
    print('$seen in ${watch.elapsedMilliseconds} ms');
    expect(seen.keys.any((k) => k.startsWith('trivial')), isTrue);
    expect(seen.keys.any((k) => k.startsWith('sharp')), isTrue);
    expect(seen.keys.any((k) => k.contains('quiet')), isTrue);
  });
}
