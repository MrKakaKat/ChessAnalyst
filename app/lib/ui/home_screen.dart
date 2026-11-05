/// Home: the analysis library. For now it holds the built-in test games
/// (Byrne vs Fischer 1956, Kasparov vs Topalov 1999) that check the analysis.
/// Sections open from a drawer on the right.
///
/// Animations: cards grow in; counters count up; on "Analyze" the board flies
/// to the analysis screen (Hero), crossfading to the initial position, while
/// the background dims and clears again.
library;

import 'dart:math' as math;

import 'package:chessground/chessground.dart' hide GameData;
import 'package:dartchess/dartchess.dart' show Side;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../analysis/game.dart';
import '../analysis/openings.dart';
import 'controller.dart';
import 'game_screen.dart';
import 'labels.dart';
import 'board_screen.dart';
import 'history_screen.dart';
import 'import_screen.dart';
import 'legend_screen.dart';
import 'positions_screen.dart';
import 'reference_screen.dart';
import 'stats_screen.dart';
import 'li_icons.dart';
import 'play_screen.dart';
import '../analysis/settings.dart' show analysisRules;
import 'history_store.dart';
import 'puzzle_screen.dart';
import 'prefs.dart';
import 'settings_screen.dart';
import 'step_icons.dart';
import 'widgets/board_view.dart';

/// Once after an update that changed the analysis rules: what it means for
/// the games already analysed. Shown only when there are such games.
Future<void> showUpdateNotice(BuildContext context, OpeningBook book) async {
  if (prefs.seenRules >= analysisRules) return;
  await history.load();
  final old = history.entries.where((e) => e.outdated).length;
  prefs.update(rulesSeen: analysisRules);
  if (old == 0 || !context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.update_rounded),
      title: const Text('The analysis was updated'),
      content: SingleChildScrollView(
        child: Text(
          '$old of your games were analysed with older rules.\n\n'
          '• They open as before: grades, kinds of moves and ideas are recomputed from the stored engine data '
          'with the new rules.\n'
          '• Your statistics keep everything counted so far, kinds of moves that changed included.\n'
          '• Some new features need fresh engine data. These games are marked "Re-analyse" in the history: '
          'analyse them again when it suits you.',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
        FilledButton(
          onPressed: () {
            Navigator.pop(context);
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HistoryScreen(book: book)));
          },
          child: const Text('Open the history'),
        ),
      ],
    ),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key, required this.decks, required this.book});

  /// Showcase games by deck (name, games).
  final List<(String, List<GameData>)> decks;
  final OpeningBook book;

  List<GameData> get games => [for (final d in decks) ...d.$2];

  @override
  Widget build(BuildContext context) {
    // после обновления правил анализа — одно окно с пояснением
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_noticeChecked) {
        _noticeChecked = true;
        showUpdateNotice(context, book);
      }
    });
    return Scaffold(
      appBar: AppBar(title: const Text('ChessAnalyst')),
      endDrawer: _SectionsDrawer(book: book, games: games),
      // доски карточек следуют настройкам фигур и цвета доски
      body: ListenableBuilder(
        listenable: prefs,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Analyses', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              'Where the mistake began, not where the evaluation dropped.',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
            // колоды: мастера, AlphaZero против Stockfish, партии движков
            for (final (name, deck) in decks) ...[
              const SizedBox(height: 18),
              Text(name, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              // своя картинка: прокрутка не перерисовывает колоду
              RepaintBoundary(
                child: _GameDeck(games: deck, book: book),
              ),
            ],
            const SizedBox(height: 24),
            Text('All games', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            for (final (name, deck) in decks)
              for (final g in deck)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      name,
                      g.headers['event'] ?? '',
                      (g.headers['date'] ?? '').split('.').first,
                      g.headers['result'] ?? '',
                    ].where((x) => x.isNotEmpty && x != '?').join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton.filledTonal(
                    tooltip: 'Analyze',
                    onPressed: () => openShowcase(context, g, book),
                    icon: const PawnIcon(),
                  ),
                  onTap: () => openShowcase(context, g, book),
                ),
          ],
        ),
      ),
    );
  }
}

bool _noticeChecked = false;

/// Opens a showcase game from the list (no board flight).
void openShowcase(BuildContext context, GameData g, OpeningBook book) {
  final c = AnalysisController(g, book: book)..select(-1);
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => GameScreen(controller: c)));
}

/// Showcase games as a deck: the top card swipes away to either side and
/// goes back under the others; the cards behind peek out below.
class _GameDeck extends StatefulWidget {
  const _GameDeck({required this.games, required this.book});

  final List<GameData> games;
  final OpeningBook book;

  @override
  State<_GameDeck> createState() => _GameDeckState();
}

class _GameDeckState extends State<_GameDeck> with SingleTickerProviderStateMixin {
  /// How far each card under the top one shows at the top left.
  static const _step = 9.0;

  late final _order = [for (var i = 0; i < widget.games.length; i++) i];
  late final AnimationController _fly = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
  double _dx = 0;
  double _from = 0, _to = 0;

  @override
  void initState() {
    super.initState();
    _fly.addListener(() => setState(() => _dx = _from + (_to - _from) * Curves.easeOut.transform(_fly.value)));
  }

  @override
  void dispose() {
    _fly.dispose();
    super.dispose();
  }

  void _release(double velocity, double width) {
    final away = _dx.abs() > width * 0.3 || velocity.abs() > 700;
    _from = _dx;
    _to = away ? (_dx.sign == 0 ? velocity.sign : _dx.sign) * width * 1.2 : 0;
    _fly.forward(from: 0).then((_) {
      if (!away) return;
      // верхняя карта уходит вниз колоды
      setState(() {
        _order.add(_order.removeAt(0));
        _dx = 0;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final width = box.maxWidth.clamp(0.0, 400.0);
        final behind = math.min(2, _order.length - 1);
        final topHeight = _heights[widget.games[_order.first].id];
        final shown = _order.take(behind + 1).toList();
        return Center(
          child: SizedBox(
            width: width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // одна и та же обёртка на любой глубине: карточки не пересоздаются
                // и не дёргаются, когда верхняя уходит вниз колоды
                // пока верхнюю карту тянут или она улетает, вторая растёт и
                // поднимается прямо за пальцем (без запаздывающей анимации):
                // к смене карт она уже на месте и не «проседает»
                // карты под верхней видны силуэтом сверху слева: это колода
                for (final (depth, i) in shown.indexed.toList().reversed)
                  AnimatedPadding(
                    key: ValueKey(widget.games[i].id),
                    duration: _dx == 0 ? const Duration(milliseconds: 260) : Duration.zero,
                    curve: Curves.easeOut,
                    padding: () {
                      final d = depth - (depth == 1 ? (_dx.abs() / width).clamp(0.0, 1.0) : 0.0);
                      final shift = _step * (behind - d);
                      return EdgeInsets.only(top: shift, left: shift, right: _step * d);
                    }(),
                    child: AnimatedScale(
                      duration: _dx == 0 ? const Duration(milliseconds: 260) : Duration.zero,
                      curve: Curves.easeOut,
                      scale: 1,
                      alignment: Alignment.topCenter,
                      child: IgnorePointer(
                        ignoring: depth != 0,
                        child: GestureDetector(
                          onHorizontalDragUpdate: depth == 0 ? (d) => setState(() => _dx += d.delta.dx) : null,
                          onHorizontalDragEnd: depth == 0 ? (d) => _release(d.primaryVelocity ?? 0, width) : null,
                          child: Transform.translate(
                            offset: Offset(depth == 0 ? _dx : 0, 0),
                            child: Transform.rotate(
                              angle: depth == 0 ? _dx / width * 0.25 : 0,
                              // карты под верхней обрезаны по её высоте: снизу не видны
                              child: ClipRect(
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  heightFactor: depth == 0 || topHeight == null
                                      ? 1
                                      : (topHeight / (_heights[widget.games[i].id] ?? topHeight)).clamp(0.0, 1.0),
                                  child: _SizeReporter(
                                    onSize: (size) {
                                      final id = widget.games[i].id;
                                      if (mounted && _heights[id] != size.height) {
                                        setState(() => _heights[id] = size.height);
                                      }
                                    },
                                    child: _card(i, depth),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Every card of a deck has the same height: the cards under the top one
  /// show only at the top left, not below it.
  /// Measured height of each card: the cards under the top one are cut to
  /// its height, so they show only at the top left.
  final _heights = <String, double>{};

  Widget _card(int i, int depth) => _GameCard(game: widget.games[i], book: widget.book, delay: i * 150);
}

class _GameCard extends StatefulWidget {
  const _GameCard({required this.game, required this.book, required this.delay});

  final GameData game;
  final OpeningBook book;
  final int delay;

  @override
  State<_GameCard> createState() => _GameCardState();
}

class _GameCardState extends State<_GameCard> {
  late final AnalysisController _controller = AnalysisController(widget.game, book: widget.book);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Ход, позиция после которого показана на карточке: последний ход по книге
  /// (подпись — название дебюта), иначе первый ход.
  int get _showcase {
    final i = _controller.analysis.records.lastIndexWhere((r) => r.opening != null);
    return i >= 0 ? i : 0;
  }

  String? get _opening => _controller.analysis.records[_showcase].opening;

  String get _showcaseKind {
    final r = _controller.analysis.records[_showcase];
    return iconKindOf(r.step, r.subtype);
  }

  /// The board in flight: crossfades between the card's position and the
  /// analysis screen's (both ways, the animation runs back on return).
  Widget _shuttle(BuildContext _, Animation<double> anim, HeroFlightDirection _, BuildContext _, BuildContext _) =>
      flightBoard(
        _controller,
        from: (fen: _controller.after[_showcase].fen, lastMove: _controller.moves[_showcase], kind: _showcaseKind),
        animation: anim,
      );

  void _open() {
    // разбор начинается с начальной позиции; при перелёте доска плавно сменяется
    _controller.select(-1);
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 650),
        reverseTransitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (context, a, _) =>
            GameScreen(controller: _controller, heroTag: widget.game.id, heroShuttle: _shuttle),
        transitionsBuilder: (context, a, _, child) {
          // фон темнеет, пока доска летит, и светлеет к её приземлению
          final dim = Tween(begin: 0.0, end: 1.0).animate(a);
          return AnimatedBuilder(
            animation: dim,
            builder: (context, _) => Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.55 * math.sin(math.pi * dim.value))),
                ),
                Opacity(opacity: Curves.easeIn.transform(dim.value), child: child),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.game;
    final scheme = Theme.of(context).colorScheme;
    final records = _controller.analysis.records;
    int count(Side side, bool Function(String) f) => records.where((r) => r.side == side && f(r.step)).length;
    final brilliant = records.where((r) => r.subtype == 'brilliant').length;
    final fen = _controller.after[_showcase].fen;

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 600 + widget.delay),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.9 + 0.1 * t, child: child),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: SizedBox(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            g.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${g.headers['event']}, ${g.headers['date']?.substring(0, 4)} · ${g.headers['result']}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: scheme.outline, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    // Доска по фактической ширине карточки: при фиксированном размере
                    // фон и фигуры расходились на узком экране.
                    LayoutBuilder(
                      builder: (context, box) {
                        final size = math.min(320.0, box.maxWidth);
                        return Center(
                          child: Hero(
                            tag: g.id,
                            flightShuttleBuilder: _shuttle,
                            child: StaticChessboard(
                              size: size,
                              orientation: Side.white,
                              fen: fen,
                              lastMove: _controller.moves[_showcase],
                              settings: StaticChessboardSettings(
                                pieceAssets: prefs.pieceSet.assets,
                                colorScheme: boardScheme(_showcaseKind),
                                borderRadius: const BorderRadius.all(Radius.circular(6)),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (_opening != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _opening!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: scheme.outline),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        _Counter(label: 'Moves', value: g.plies.length),
                        _Counter(label: 'White errors', value: count(Side.white, isError), step: 'mistake'),
                        _Counter(label: 'Black errors', value: count(Side.black, isError), step: 'mistake'),
                        _Counter(label: 'Brilliant', value: brilliant, color: brilliantColor),
                        _Counter(label: 'Ideas', value: _controller.analysis.ideas.length, color: scheme.tertiary),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Stockfish 16, depth ${g.engine['depth']}, MultiPV ${g.engine['multipv']}. '
                      'Labels are computed in the app.',
                      style: TextStyle(color: scheme.outline, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(onPressed: _open, icon: const PawnIcon(), label: const Text('Analyze')),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({required this.label, required this.value, this.step, this.color});

  final String label;
  final int value;
  final String? step;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? (step != null ? stepColor(step!, Theme.of(context).brightness) : null);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: value.toDouble()),
      duration: const Duration(milliseconds: 1100),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${v.round()}',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: c),
          ),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

/// Pawn icon in the current icon colour (the button's text colour).
class PawnIcon extends StatelessWidget {
  const PawnIcon({super.key, this.size});

  final double? size;

  @override
  Widget build(BuildContext context) => LiIcon(LiPiece.pawn, size: size);
}

/// Sections of the app, in a drawer on the right: analyses, play the engine,
/// analyse your own game, history, settings, icons.
class _SectionsDrawer extends StatelessWidget {
  const _SectionsDrawer({required this.book, required this.games});

  final OpeningBook book;
  final List<GameData> games;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text('ChessAnalyst', style: Theme.of(context).textTheme.titleLarge),
            ),
            ListTile(
              leading: const PawnIcon(),
              title: const Text('Analyses'),
              selected: true,
              onTap: () => Navigator.of(context).pop(),
            ),
            ListTile(
              leading: const Icon(Icons.desktop_windows_outlined),
              title: const Text('Play the engine'),
              subtitle: const Text('Stockfish, eight levels'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => const PlayScreen()));
              },
            ),
            ListTile(
              leading: const DartboardIcon(),
              title: const Text('Puzzles'),
              subtitle: const Text('From the analysed games'),
              onTap: () {
                _go(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PuzzleHomeScreen(games: games, book: book),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.biotech_outlined),
              title: const Text('Analysis board'),
              subtitle: const Text('Free board with the engine, saved sessions'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => const AnalysisBoardScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded),
              title: const Text('Analyze my game'),
              subtitle: const Text('Paste a PGN, choose depth and power'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => ImportScreen(book: book)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: const Text('Analysis history'),
              subtitle: const Text('Your analyses, also unfinished ones'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => HistoryScreen(book: book)));
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text('Settings'),
              subtitle: const Text('Arrows, legal moves, board, pieces'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.insights_rounded),
              title: const Text('Statistics'),
              subtitle: const Text('Your games: colours, stages, missed moves'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => StatsScreen(book: book)));
              },
            ),
            ListTile(
              leading: const Icon(Icons.extension_rounded),
              title: const Text('Positions'),
              subtitle: const Text('Solved and underlined positions, by trait'),
              onTap: () {
                _go(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => PositionsScreen(games: games, book: book),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.menu_book_rounded),
              title: const Text('Analysis guide'),
              subtitle: const Text('What the marks, types and characters mean'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => const ReferenceScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('Icons'),
              onTap: () {
                _go(context, MaterialPageRoute<void>(builder: (_) => const LegendScreen()));
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Closes the drawer, then opens [route] once the drawer is gone: both
/// animations together made some screens stutter.
void _go(BuildContext context, Route<void> route) {
  final nav = Navigator.of(context);
  nav.pop();
  Future<void>.delayed(const Duration(milliseconds: 220), () => nav.push(route));
}

/// Reports the size of its child after layout.
class _SizeReporter extends SingleChildRenderObjectWidget {
  const _SizeReporter({required this.onSize, super.child});

  final ValueChanged<Size> onSize;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSizeReporter(onSize);

  @override
  void updateRenderObject(BuildContext context, _RenderSizeReporter renderObject) => renderObject.onSize = onSize;
}

class _RenderSizeReporter extends RenderProxyBox {
  _RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    if (size != _last) {
      _last = size;
      final s = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => onSize(s));
    }
  }
}
