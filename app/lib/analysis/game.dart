/// Партия с данными движка и её разбор (chessanalyst/pipeline.py без движка).
///
/// Сейчас данные Stockfish приходят готовыми (ассет, экспортированный
/// tools/export_flutter_fixture.py). Классификация и идейные цепочки
/// считаются здесь, в Dart, и пересчитываются при смене единицы.
library;

import 'dart:convert';

import 'package:dartchess/dartchess.dart' show Side, kInitialFEN;

import 'classify.dart';
import 'eval.dart';
import 'ideas.dart';
import 'openings.dart';
import 'pos.dart';
import 'settings.dart';

class GamePly {
  GamePly({
    required this.san,
    required this.uci,
    required this.fenBefore,
    required this.lines,
    required this.played,
    required this.allLines,
  });

  final String san, uci, fenBefore;
  final List<Line> lines;
  final Line played;
  final List<Line>? allLines;
}

class GameData {
  GameData({
    required this.id,
    required this.headers,
    required this.startFen,
    required this.engine,
    required this.plies,
  });

  factory GameData.fromJson(Map<String, dynamic> j) {
    List<Line> lines(dynamic xs) => [for (final x in xs as List) Line.fromJson(x as Map<String, dynamic>)];
    return GameData(
      id: j['id'] as String,
      headers: (j['headers'] as Map).map((k, v) => MapEntry(k as String, v?.toString() ?? '')),
      startFen: j['start_fen'] as String,
      engine: Map<String, dynamic>.from(j['engine'] as Map),
      plies: [
        for (final p in j['plies'] as List)
          GamePly(
            san: p['san'] as String,
            uci: p['uci'] as String,
            fenBefore: p['fen_before'] as String,
            lines: lines(p['lines']),
            played: Line.fromJson(p['played'] as Map<String, dynamic>),
            allLines: p['all_lines'] == null ? null : lines(p['all_lines']),
          ),
      ],
    );
  }

  factory GameData.parse(String source) => GameData.fromJson(jsonDecode(source) as Map<String, dynamic>);

  Map<String, dynamic> toJson() => {
        'id': id,
        'headers': headers,
        'start_fen': startFen,
        'engine': engine,
        'plies': [
          for (final p in plies)
            {
              'san': p.san,
              'uci': p.uci,
              'fen_before': p.fenBefore,
              'lines': [for (final l in p.lines) l.toJson()],
              'played': p.played.toJson(),
              'all_lines': p.allLines == null ? null : [for (final l in p.allLines!) l.toJson()],
            },
        ],
      };

  final String id;
  final Map<String, String> headers;
  final String startFen;
  final Map<String, dynamic> engine;
  final List<GamePly> plies;

  String get white => headers['white'] ?? '?';
  String get black => headers['black'] ?? '?';
  String get title => '$white — $black';

  /// The game as PGN: the seven-tag roster and the moves.
  String get pgn {
    String tag(String k, String key) => '[$k "${(headers[key] ?? '?').replaceAll('"', "'")}"]';
    final out = StringBuffer()
      ..writeln(tag('Event', 'event'))
      ..writeln(tag('Site', 'site'))
      ..writeln(tag('Date', 'date'))
      ..writeln(tag('Round', 'round'))
      ..writeln(tag('White', 'white'))
      ..writeln(tag('Black', 'black'))
      ..writeln(tag('Result', 'result'));
    if (startFen != kInitialFEN) {
      out
        ..writeln('[SetUp "1"]')
        ..writeln('[FEN "$startFen"]');
    }
    out.writeln();
    final words = <String>[];
    final black0 = Pos.fromFen(startFen).turn == Side.black;
    final move0 = int.tryParse(startFen.split(' ').last) ?? 1;
    for (var i = 0; i < plies.length; i++) {
      final k = i + (black0 ? 1 : 0);
      final n = move0 + k ~/ 2;
      if (k.isEven) words.add('$n.');
      if (i == 0 && black0) words.add('$n...');
      words.add(plies[i].san);
    }
    words.add(headers['result'] ?? '*');
    // строки до 80 знаков
    var line = '';
    for (final w in words) {
      if (line.isNotEmpty && line.length + 1 + w.length > 80) {
        out.writeln(line);
        line = w;
      } else {
        line = line.isEmpty ? w : '$line $w';
      }
    }
    out.writeln(line);
    return out.toString();
  }

  /// Позиция после последнего хода.
  String get finalFen {
    final last = plies.last;
    return Pos.fromFen(last.fenBefore).push(Pos.move(last.uci)).fen;
  }
}

class GameAnalysis {
  GameAnalysis(this.game, this.settings, this.records, this.ideas);

  final GameData game;
  final Settings settings;
  final List<MoveRecord> records;
  final List<Idea> ideas;

  Idea? ideaAt(int ply) {
    for (final i in ideas) {
      if (i.punishPly == ply) return i;
    }
    return null;
  }
}

GameAnalysis analyzeGame(GameData game, Settings s, {OpeningBook? book}) {
  // число линий — как в данных движка партии
  s = Settings(
      unit: s.unit, multipv: (game.engine['multipv'] as num?)?.toInt() ?? s.multipv, percentSteps: s.percentSteps);
  final analysed = [
    for (final p in game.plies)
      PlyAnalysis(board: Pos.fromFen(p.fenBefore), lines: p.lines, played: p.played, allLines: p.allLines),
  ];
  final openings = (book ?? OpeningBook.empty).names(game.startFen, [for (final p in game.plies) p.uci]);
  final records = <MoveRecord>[];
  for (var ply = 0; ply < analysed.length; ply++) {
    final a = analysed[ply];
    final prev = ply > 0 ? analysed[ply - 1].lines.first.eval : null;
    records.add(classify(a.board, a.lines, a.played, prev, s,
        ply: ply,
        allLines: a.allLines,
        opening: openings[ply],
        continuation: [for (final x in analysed.skip(ply + 1).take(6)) x.played.move]));
  }
  return GameAnalysis(game, s, records, findIdeas(analysed, records, s));
}
