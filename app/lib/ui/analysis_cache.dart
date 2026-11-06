/// Analyses of the showcase games, made once and away from the screen.
///
/// [авторское] Each home card used to analyse its game in the frame it was
/// built (a few hundred milliseconds on a phone): the home screen froze when
/// the decks appeared and stuttered when a card was swiped in. Now the
/// analysis runs in a background isolate (on the web, where isolates are not
/// available, between frames), one game at a time, and is kept for the
/// cards, the puzzles and the game screen.
library;

import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart' show kIsWeb;

import '../analysis/game.dart';
import '../analysis/openings.dart';
import '../analysis/settings.dart';

final _cache = <String, Future<GameAnalysis>>{};
Future<void> _queue = Future.value();

/// The analysis of [g] in pawns, from the cache or made in the background.
Future<GameAnalysis> analysisOf(GameData g, OpeningBook? book) {
  // одна и та же партия на той же глубине — тот же разбор
  final key = '${g.id}:${g.plies.length}:${g.engine['depth']}';
  return _cache.putIfAbsent(key, () {
    final done = Completer<GameAnalysis>();
    _queue = _queue.then((_) async {
      try {
        done.complete(await _analyse(g, book));
      } catch (e, st) {
        done.completeError(e, st);
      }
    });
    return done.future;
  });
}

Future<GameAnalysis> _analyse(GameData g, OpeningBook? book) async {
  if (kIsWeb) {
    // в браузере без изолятов: отдать кадр и считать
    await Future<void>.delayed(const Duration(milliseconds: 16));
    return analyzeGame(g, const Settings(unit: Unit.pawns), book: book);
  }
  return Isolate.run(() => analyzeGame(g, const Settings(unit: Unit.pawns), book: book));
}
