import 'dart:io' show Platform;

import 'package:multistockfish/multistockfish.dart';

import 'engine.dart';

Future<UciEngine> startPlatformEngine() async => _NativeEngine(await Stockfish.create());

class _NativeEngine implements UciEngine {
  _NativeEngine(this._sf);

  final Stockfish _sf;

  @override
  Stream<String> get lines => _sf.stdout;

  @override
  void send(String command) => _sf.stdin = command;

  @override
  int get cores => Platform.numberOfProcessors;

  @override
  bool get alive => _sf.state.value == StockfishState.ready;

  @override
  Future<void> dispose() => _sf.dispose();
}
