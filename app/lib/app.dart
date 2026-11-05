/// The whole app. Imported by main.dart everywhere except the JS build for
/// browsers without WebAssembly GC (see app_unsupported.dart).
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'analysis/game.dart';
import 'analysis/openings.dart';
import 'ui/analysis_queue.dart';
import 'ui/home_screen.dart';
import 'ui/prefs.dart';
import 'ui/theme.dart';

/// Built-in showcase games by deck (they also check the analysis): the
/// masters, AlphaZero against Stockfish 8, and engine games made for the
/// app. Remove a line to drop a game.
final embeddedDecks = <(String, List<String>)>[
  ('Masters', [
    'assets/games/kasparov_topalov_1999.json',
    'assets/games/byrne_fischer_1956.json',
    'assets/games/morphy_opera_1858.json',
    'assets/games/immortal_zugzwang.json',
    'assets/games/evergreen_game.json',
  ]),
  ('AlphaZero vs Stockfish 8', [
    for (var i = 1; i <= 10; i++) 'assets/games/alphazero_${i.toString().padLeft(2, '0')}.json',
  ]),
  ('Engine games', [
    // системная партия приложения: Stockfish против себя, ничья с наивысшей точностью
    'assets/games/perfect_game.json',
    'assets/games/sf_kings_gambit.json',
    'assets/games/sf_najdorf.json',
    'assets/games/sf_grunfeld.json',
    'assets/games/sf_english.json',
  ]),
];

const openingBookAsset = 'assets/openings_book.json';
const openingWeightsAsset = 'assets/openings_weights.json';

class ChessIdeasApp extends StatelessWidget {
  const ChessIdeasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChessAnalyst',
      navigatorKey: analysisQueue.navigatorKey,
      // кружки очереди анализов — поверх любого экрана
      builder: (context, child) => Stack(children: [child!, const QueueBadges()]),
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: const _Loader(),
    );
  }
}

class _Loader extends StatelessWidget {
  const _Loader();

  Future<(List<(String, List<GameData>)>, OpeningBook)> _load() async {
    await prefs.load();
    // правая кнопка мыши рисует стрелки — без меню браузера
    if (kIsWeb) await BrowserContextMenu.disableContextMenu();
    final book = OpeningBook.parse(await rootBundle.loadString(openingBookAsset),
        weights: await rootBundle.loadString(openingWeightsAsset));
    final decks = <(String, List<GameData>)>[];
    for (final (name, paths) in embeddedDecks) {
      final games = <GameData>[];
      for (final path in paths) {
        // партии, которых нет в сборке, пропускаются
        try {
          games.add(GameData.parse(await rootBundle.loadString(path)));
        } catch (_) {}
      }
      if (games.isNotEmpty) decks.add((name, games));
    }
    // очередь анализов, прерванная прошлым запуском, продолжается
    analysisQueue.book = book;
    analysisQueue.restore();
    return (decks, book);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<(String, List<GameData>)>, OpeningBook)>(
      future: _load(),
      builder: (context, snap) {
        if (snap.hasError) return Scaffold(body: Center(child: Text('Loading failed: ${snap.error}')));
        if (!snap.hasData) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        return HomeScreen(decks: snap.data!.$1, book: snap.data!.$2);
      },
    );
  }
}
