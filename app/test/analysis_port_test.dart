// Port check: Dart must give the same labels and ideas as Python on the same
// engine data, for every test game and unit. Fixtures are written by
// tools/export_flutter_fixture.py.

import 'dart:convert';
import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/analysis/openings.dart';
import 'package:chessanalyst/analysis/settings.dart';
import 'package:flutter_test/flutter_test.dart';

const games = [
  'byrne_fischer_1956',
  'kasparov_topalov_1999',
  'morphy_opera_1858',
  'perfect_game',
  'immortal_zugzwang',
  'evergreen_game',
  'alphazero_01',
  'alphazero_02',
  'alphazero_03',
  'alphazero_04',
  'alphazero_05',
  'alphazero_06',
  'alphazero_07',
  'alphazero_08',
  'alphazero_09',
  'alphazero_10',
  'sf_kings_gambit',
  'sf_najdorf',
  'sf_grunfeld',
  'sf_english',
];

void main() {
  final book = OpeningBook.parse(File('assets/openings_book.json').readAsStringSync());
  for (final name in [...games, ...testGames]) {
    checkGame(name, book);
  }
}

/// Test games kept outside the app (data and reference side by side).
const testGames = ['mrkakakat_2026_11_04'];

void checkGame(String name, OpeningBook book) {
  final dir = testGames.contains(name) ? 'test/games' : 'assets/games';
  final game = GameData.parse(File('$dir/$name.json').readAsStringSync());
  final expected = jsonDecode(
          File(testGames.contains(name) ? 'test/games/$name.expected.json' : 'test/fixtures/$name.expected.json')
              .readAsStringSync())
      as Map<String, dynamic>;

  for (final unit in Unit.values) {
    group('$name, unit ${unit.name}', () {
      final exp = (expected['units'] as Map)[unit.name] as Map<String, dynamic>;
      final analysis = analyzeGame(game, Settings(unit: unit), book: book);

      test('labels of every move match Python', () {
        final records = exp['records'] as List;
        expect(analysis.records.length, records.length);
        for (var i = 0; i < records.length; i++) {
          final e = records[i] as Map<String, dynamic>;
          final r = analysis.records[i];
          final where = 'ply $i ${r.san}';
          expect(r.san, e['san'], reason: where);
          expect(r.step, e['step'], reason: where);
          expect(r.subtype, e['subtype'], reason: where);
          expect([...r.flags]..sort(), e['flags'], reason: where);
          expect(r.moveType, e['move_type'], reason: where);
          expect(r.typeSubtypes, e['type_subtypes'], reason: where);
          expect(r.stage, e['stage'], reason: where);
          expect(r.decidedBy.name, e['decided_by'], reason: where);
          expect({for (final x in r.unitSteps.entries) x.key.name: x.value}, e['unit_steps'], reason: where);
          expect(r.catE1, e['cat_e1'], reason: where);
          expect(r.opening, e['opening'], reason: where);
          expect(r.engineStep, e['engine_step'], reason: where);
          expect(r.catEp, e['cat_ep'], reason: where);
          expect(r.bestMoves.map((b) => b.uci).toList(), e['best'], reason: where);
          expect(r.nearBestMoves.map((b) => b.uci).toList(), e['near_best'], reason: where);
          final pw = (e['pawns'] as List).cast<num>();
          final wd = (e['wdl'] as List).cast<num>();
          expect(r.pawns.e0, closeTo(pw[0], 1e-6), reason: where);
          expect(r.pawns.e1, closeTo(pw[1], 1e-6), reason: where);
          expect(r.pawns.ep, closeTo(pw[2], 1e-6), reason: where);
          expect(r.wdl.e0, closeTo(wd[0], 1e-6), reason: where);
          expect(r.wdl.e1, closeTo(wd[1], 1e-6), reason: where);
          expect(r.wdl.ep, closeTo(wd[2], 1e-6), reason: where);
        }
      });

      test('idea chains match Python', () {
        final ideas = exp['ideas'] as List;
        expect(analysis.ideas.length, ideas.length);
        for (var i = 0; i < ideas.length; i++) {
          final e = ideas[i] as Map<String, dynamic>;
          final idea = analysis.ideas[i];
          final where = 'idea at ply ${idea.punishPly}';
          expect(idea.kind, e['kind'], reason: where);
          expect(idea.punishPly, e['punish_ply'], reason: where);
          expect(idea.owner.name, e['owner'], reason: where);
          expect(idea.startPly, e['start_ply'], reason: where);
          expect(idea.missPly, e['miss_ply'], reason: where);
          expect(idea.distance, e['distance'], reason: where);
          expect(idea.signature.motif, (e['signature'] as Map)['motif'], reason: where);
          expect(idea.signature.keySan, (e['signature'] as Map)['key'], reason: where);
          expect(idea.chunk, e['chunk'], reason: where);
          expect(idea.builderPlies, e['builder_plies'], reason: where);
          expect(
            idea.chain.map((c) => [c.ply, c.present, c.attacker.name, c.target.name]).toList(),
            [for (final c in e['chain'] as List) [c['ply'], c['present'], c['attacker'], c['target']]],
            reason: where,
          );
        }
      });
    });
  }
}
