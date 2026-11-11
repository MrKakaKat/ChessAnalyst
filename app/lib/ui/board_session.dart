/// Analysis board: a free board with the engine on, for checking an opening
/// or a position. Moves form a tree (a move off the line starts a branch);
/// sessions are saved on the device and can be reopened.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../analysis/eval.dart';
import '../analysis/openings.dart';
import '../analysis/pgn_import.dart' show normalizeCastling;
import '../analysis/pos.dart';
import '../engine/bot.dart';
import '../engine/game_job.dart' show EnginePower;
import 'prefs.dart';
import 'widgets/arrows.dart';

class MoveNode {
  MoveNode({this.move, this.san = '', required this.pos, this.parent});

  final NormalMove? move;
  final String san;
  final Pos pos;
  final MoveNode? parent;
  final children = <MoveNode>[];
  final arrows = <BoardArrow>[];
  final marks = <BoardMark>[];

  int get ply => parent == null ? 0 : parent!.ply + 1;

  Map<String, dynamic> toJson() => {
        if (move != null) 'uci': move!.uci,
        'children': [for (final c in children) c.toJson()],
      };
}

class BoardSession {
  BoardSession(
      {required this.id,
      required this.name,
      required this.startFen,
      DateTime? created,
      String? kind,
      this.pinned = false,
      this.favourite = false})
      : created = created ?? DateTime.now(),
        kind = kind ?? (startFen == Chess.initial.fen ? 'opening' : 'position'),
        root = MoveNode(pos: Pos.fromFen(startFen));

  final String id;
  String name;
  final String startFen;
  final DateTime created;
  final MoveNode root;

  /// 'opening': a clean board from the start (named by the user, shown with
  /// the opening's name); 'position': opened from a puzzle or another place
  /// with the analysis icon.
  final String kind;
  bool pinned, favourite;

  /// Where the analysis stopped: the child index at each step from the root,
  /// and the side the board was seen from.
  List<int> lastPath = const [];
  bool flipped = false;

  bool get isOpening => kind == 'opening';

  /// The node at [lastPath] (the root if it no longer exists).
  MoveNode get lastNode {
    var n = root;
    for (final i in lastPath) {
      if (i < 0 || i >= n.children.length) break;
      n = n.children[i];
    }
    return n;
  }

  static List<int> pathOf(MoveNode n) {
    final out = <int>[];
    for (MoveNode? x = n; x != null && x.parent != null; x = x.parent) {
      out.insert(0, x.parent!.children.indexOf(x));
    }
    return out;
  }

  /// The opening of the main line (the first branch at each move), from
  /// [book]; null outside the book or from another position.
  String? openingName(OpeningBook? book) {
    if (book == null || !isOpening) return null;
    final ucis = <String>[];
    for (var n = root; n.children.isNotEmpty; n = n.children.first) {
      ucis.add(n.children.first.move!.uci);
      if (ucis.length >= 30) break;
    }
    String? name;
    for (final x in book.names(startFen, ucis)) {
      if (x != null && x.isNotEmpty) name = x;
    }
    return name;
  }

  /// The whole tree as PGN: the main line with every branch in brackets.
  String pgn() {
    final b = StringBuffer();
    if (startFen != Chess.initial.fen) b.write('[SetUp "1"]\n[FEN "$startFen"]\n\n');
    String no(MoveNode n, bool force) {
      final pos = n.parent!.pos;
      if (pos.turn == Side.white) return '${pos.fullmoves}. ';
      return force ? '${pos.fullmoves}... ' : '';
    }

    void line(MoveNode from, bool forceFirst) {
      var n = from;
      var force = forceFirst;
      while (n.children.isNotEmpty) {
        final main = n.children.first;
        b.write('${no(main, force)}${main.san} ');
        // ветки — в скобках сразу после главного хода
        for (final v in n.children.skip(1)) {
          b.write('(${no(v, true)}${v.san} ');
          line(v, false);
          b.write(') ');
        }
        force = n.children.length > 1;
        n = main;
      }
    }

    line(root, true);
    b.write('*');
    return b.toString().replaceAll(' )', ')').trim();
  }

  int get moveCount {
    var n = 0;
    void walk(MoveNode m) {
      n += m.children.length;
      m.children.forEach(walk);
    }

    walk(root);
    return n;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start': startFen,
        'created': created.toIso8601String(),
        'kind': kind,
        if (pinned) 'pinned': true,
        if (favourite) 'favourite': true,
        if (lastPath.isNotEmpty) 'path': lastPath,
        if (flipped) 'flipped': true,
        'tree': root.toJson(),
      };

  factory BoardSession.fromJson(Map<String, dynamic> j) {
    final s = BoardSession(
      id: j['id'] as String,
      name: j['name'] as String,
      startFen: j['start'] as String,
      created: DateTime.tryParse(j['created'] as String? ?? ''),
      // старые сессии: с начальной позиции — дебютные
      kind: j['kind'] as String?,
      pinned: j['pinned'] as bool? ?? false,
      favourite: j['favourite'] as bool? ?? false,
    )
      ..lastPath = (j['path'] as List?)?.cast<int>() ?? const []
      ..flipped = j['flipped'] as bool? ?? false;
    void grow(MoveNode node, Map<String, dynamic> data) {
      for (final c in (data['children'] as List).cast<Map<String, dynamic>>()) {
        final m = NormalMove.fromUci(c['uci'] as String);
        if (!node.pos.isLegal(m)) continue;
        final child = MoveNode(move: m, san: node.pos.san(m), pos: node.pos.push(m), parent: node);
        node.children.add(child);
        grow(child, c);
      }
    }

    grow(s.root, j['tree'] as Map<String, dynamic>);
    return s;
  }
}

/// Saved sessions (shared_preferences: an index and one entry per session).
class BoardSessions {
  static const _index = 'boards.index';

  static Future<List<BoardSession>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      return [
        for (final id in p.getStringList(_index) ?? <String>[])
          if (p.getString('boards.$id') case final raw?) BoardSession.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      ];
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(BoardSession s) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ids = p.getStringList(_index) ?? [];
      await p.setString('boards.${s.id}', jsonEncode(s.toJson()));
      await p.setStringList(_index, [s.id, ...ids.where((x) => x != s.id)]);
    } catch (_) {}
  }

  static Future<void> remove(String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.remove('boards.$id');
      await p.setStringList(_index, [...?p.getStringList(_index)?.where((x) => x != id)]);
    } catch (_) {}
  }
}

class SessionController extends ChangeNotifier {
  SessionController(this.session)
      : current = session.lastNode,
        flipped = session.flipped {
    _analyse();
  }

  BoardSession session;
  MoveNode current;

  /// A temporary session (opened from a puzzle) is not saved until [keep].
  bool temporary = false;
  bool flipped;
  bool engineOn = true;

  /// [простое решение] Low by default: one thread, depth 14 — a quick check
  /// that keeps the phone cool.
  EnginePower power = EnginePower.low;

  /// Engine lines of [current] (side to move's view); null while computing.
  List<Line>? lines;
  int depth = 0;
  bool _disposed = false;
  Timer? _saveTimer;

  /// Engine results by position and power: going back to a position shows
  /// them at once; only new positions are computed.
  final _cache = <String, (List<Line>, int)>{};

  Pos get position => current.pos;

  /// Makes a temporary session a regular saved one.
  void keep() {
    temporary = false;
    BoardSessions.save(session);
    notifyListeners();
  }

  void open(BoardSession s) {
    temporary = false;
    session = s;
    // там, где остановились, и тем же цветом
    current = s.lastNode;
    flipped = s.flipped;
    lines = null;
    notifyListeners();
    _analyse();
  }

  /// A move on the board: follows an existing branch or starts a new one.
  void play(NormalMove m) {
    m = normalizeCastling(position, m);
    if (!position.isLegal(m)) return;
    MoveNode? next;
    for (final c in current.children) {
      if (c.move == m) next = c;
    }
    if (next == null) {
      next = MoveNode(move: m, san: position.san(m), pos: position.push(m), parent: current);
      current.children.add(next);
      _scheduleSave();
    }
    go(next);
  }

  void go(MoveNode node) {
    current = node;
    session.lastPath = BoardSession.pathOf(node);
    _scheduleSave();
    lines = null;
    notifyListeners();
    _analyse();
  }

  void back() {
    if (current.parent != null) go(current.parent!);
  }

  void forward() {
    if (current.children.isNotEmpty) go(current.children.first);
  }

  void toStart() => go(session.root);

  void toEnd() {
    var n = current;
    while (n.children.isNotEmpty) {
      n = n.children.first;
    }
    go(n);
  }

  /// Removes [node] and its branch.
  void delete(MoveNode node) {
    final parent = node.parent;
    if (parent == null) return;
    parent.children.remove(node);
    var n = current;
    while (n.parent != null) {
      if (identical(n, node)) {
        go(parent);
        break;
      }
      n = n.parent!;
    }
    _scheduleSave();
    notifyListeners();
  }

  void flip() {
    flipped = !flipped;
    session.flipped = flipped;
    _scheduleSave();
    notifyListeners();
  }

  /// Makes the branch of [node] the main line at its move, or (when it is
  /// already the main one) a side branch.
  void toggleMain(MoveNode node) {
    final parent = node.parent;
    if (parent == null || parent.children.length < 2) return;
    final i = parent.children.indexOf(node);
    parent.children.removeAt(i);
    if (i == 0) {
      parent.children.add(node);
    } else {
      parent.children.insert(0, node);
    }
    session.lastPath = BoardSession.pathOf(current);
    _scheduleSave();
    notifyListeners();
  }

  void save() => _scheduleSave();

  void setEngine(bool on) {
    engineOn = on;
    lines = null;
    notifyListeners();
    _analyse();
  }

  void setPower(EnginePower p) {
    power = p;
    lines = null;
    notifyListeners();
    _analyse();
  }

  void toggleMark(Square s) {
    final m = BoardMark(s, prefs.userMarkColor);
    if (!current.marks.remove(m)) current.marks.add(m);
    notifyListeners();
  }

  void toggleArrow(Square from, Square to) {
    final a = BoardArrow(from, to, prefs.userArrowColor, sketched: true);
    if (!current.arrows.remove(a)) current.arrows.add(a);
    notifyListeners();
  }

  int get _depth => switch (power) { EnginePower.low => 14, EnginePower.medium => 18, EnginePower.high => 22 };

  Future<void> _analyse() async {
    if (!engineOn) return;
    final node = current;
    if (node.pos.p.isGameOver) return;
    final key = '${node.pos.fen}|${power.name}';
    if (_cache[key] case final hit?) {
      lines = hit.$1;
      depth = hit.$2;
      notifyListeners();
      return;
    }
    try {
      final bot = await EngineBot.shared();
      final threads = switch (power) {
        EnginePower.low => 1,
        EnginePower.medium => math.min(2, bot.cores),
        EnginePower.high => math.max(1, math.min(bot.cores - 1, 4)),
      };
      // позиция могла смениться, пока движок был занят — считаем только текущую
      if (_disposed || !identical(node, current)) return;
      final result = await bot.analyse(node.pos.fen, depth: _depth, multipv: 3, threads: threads);
      if (_disposed || !identical(node, current)) return;
      lines = result;
      depth = _depth;
      _cache[key] = (result, _depth);
      notifyListeners();
    } catch (_) {}
  }

  void _scheduleSave() {
    if (temporary) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 600), () => BoardSessions.save(session));
  }

  @override
  void dispose() {
    _disposed = true;
    _saveTimer?.cancel();
    // временная сессия (из задачи) исчезает при выходе
    if (!temporary) BoardSessions.save(session);
    super.dispose();
  }
}
