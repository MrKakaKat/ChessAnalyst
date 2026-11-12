/// UCI chess engine: Stockfish 19 with a small embedded net.
///
/// On Android and iOS it is the native multistockfish plugin (light flavor);
/// on the web it is Stockfish.js lite, single-threaded, in a Web Worker
/// (web/stockfish/). Both speak UCI line by line.
library;

import 'dart:async';

import 'engine_stub.dart'
    if (dart.library.js_interop) 'engine_web.dart'
    if (dart.library.ffi) 'engine_native.dart' as platform;

abstract class UciEngine {
  /// Engine output, one UCI line per event.
  Stream<String> get lines;

  void send(String command);

  /// Processor cores available to the engine (1 on the web build).
  int get cores;

  /// The engine still runs (the native one can die on its own, for example
  /// while the app was in the background).
  bool get alive;

  Future<void> dispose();
}

/// Starts the platform's engine.
Future<UciEngine> startEngine() => platform.startPlatformEngine();
