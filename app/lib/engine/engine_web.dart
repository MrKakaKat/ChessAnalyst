import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'engine.dart';

const _script = 'stockfish/stockfish-19-lite-single.js';

Future<UciEngine> startPlatformEngine() async => _WebEngine(web.Worker(_script.toJS));

class _WebEngine implements UciEngine {
  _WebEngine(this._worker) {
    _worker.onmessage = ((web.MessageEvent e) {
      final data = e.data;
      if (data != null && data.isA<JSString>()) {
        // Stockfish.js может прислать несколько строк одним сообщением
        for (final line in (data as JSString).toDart.split('\n')) {
          if (line.isNotEmpty) _lines.add(line);
        }
      }
    }).toJS;
  }

  final web.Worker _worker;
  final _lines = StreamController<String>.broadcast();

  @override
  Stream<String> get lines => _lines.stream;

  @override
  void send(String command) => _worker.postMessage(command.toJS);

  @override
  int get cores => 1; // однопоточная сборка Stockfish.js

  @override
  bool get alive => true;

  @override
  Future<void> dispose() async {
    _worker.terminate();
    await _lines.close();
  }
}
