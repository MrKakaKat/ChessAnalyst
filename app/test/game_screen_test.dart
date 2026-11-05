import 'dart:io';

import 'package:chessanalyst/analysis/game.dart';
import 'package:chessanalyst/ui/controller.dart';
import 'package:chessanalyst/ui/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final game = GameData.parse(File('assets/games/kasparov_topalov_1999.json').readAsStringSync());

  testWidgets('game screen renders at the start, a move, the end and in a variation', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final c = AnalysisController(game);
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    await tester.pump(const Duration(seconds: 2));
    for (final step in [() => c.select(10), () => c.last(), () => c.first()]) {
      step();
      await tester.pump(const Duration(seconds: 2));
    }
    c.select(20);
    c.playMove(c.position.legalMoves.first);
    await tester.pump(const Duration(seconds: 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkmate gets its own card and sign', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final fischer = GameData.parse(File('assets/games/byrne_fischer_1956.json').readAsStringSync());
    final c = AnalysisController(fischer);
    expect(c.isMate(c.length - 1), isTrue);
    expect(c.kindAt(c.length - 1), 'mate');
    expect(c.end, isNull); // мат, а не сдача
    await tester.pumpWidget(MaterialApp(home: GameScreen(controller: c)));
    c.last();
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Black checkmates White.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
