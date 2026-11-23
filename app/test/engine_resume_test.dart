import 'dart:async';

import 'package:chessanalyst/engine/bot.dart';
import 'package:chessanalyst/engine/engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// An engine that answers the handshake, starts a search and then freezes
/// (as a native engine can while the app is in the background).
class FrozenEngine implements UciEngine {
  final _out = StreamController<String>.broadcast();
  bool frozen = false;

  @override
  Stream<String> get lines => _out.stream;

  @override
  void send(String command) {
    if (frozen) return;
    scheduleMicrotask(() {
      if (command == 'uci') _out.add('uciok');
      if (command == 'isready') _out.add('readyok');
      if (command.startsWith('go')) {
        _out.add('info depth 1 multipv 1 score cp 20 pv e2e4');
        frozen = true;
      }
    });
  }

  @override
  int get cores => 1;

  @override
  bool get alive => true;

  @override
  Future<void> dispose() async {}
}

void main() {
  test('a search frozen in the background fails at once on resume, and a new engine is taken', () async {
    var started = 0;
    EngineBot.engineFactory = () async {
      started++;
      return FrozenEngine();
    };
    await EngineBot.reset();
    final bot = await EngineBot.shared();
    final search = bot.analyse('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', depth: 20);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await EngineBot.checkAfterResume(quiet: Duration.zero, grace: const Duration(milliseconds: 100));
    await expectLater(search, throwsA(isA<TimeoutException>()));
    expect(bot.alive, isFalse);
    final next = await EngineBot.shared();
    expect(identical(next, bot), isFalse);
    expect(started, 2);
    EngineBot.engineFactory = null;
    await EngineBot.reset();
  });
}
