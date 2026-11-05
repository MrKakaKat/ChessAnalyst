/// A user's game from PGN text: headers, start position and the moves in UCI
/// (castling as e1g1, as in the engine data).
library;

import 'package:dartchess/dartchess.dart';

import 'pos.dart';

class ImportedGame {
  const ImportedGame({
    required this.headers,
    required this.startFen,
    required this.sans,
    required this.ucis,
    required this.fensBefore,
  });

  final Map<String, String> headers;
  final String startFen;
  final List<String> sans;
  final List<String> ucis;
  final List<String> fensBefore;

  String get title => '${headers['white'] ?? '?'} — ${headers['black'] ?? '?'}';
}

/// Parses the first game of [text]; throws [FormatException] when there are
/// no legal moves.
ImportedGame importPgn(String text) {
  final game = PgnGame.parsePgn(text);
  final Position start;
  try {
    start = PgnGame.startingPosition(game.headers);
  } catch (_) {
    throw const FormatException('Unsupported start position');
  }
  var pos = Pos(start as Chess);
  final sans = <String>[], ucis = <String>[], fens = <String>[];
  for (final node in game.moves.mainline()) {
    final m = pos.p.parseSan(node.san);
    if (m is! NormalMove) throw FormatException('Illegal move ${node.san} after ${sans.length} plies');
    final move = normalizeCastling(pos, m);
    fens.add(pos.fen);
    sans.add(pos.san(move));
    ucis.add(move.uci);
    pos = pos.push(move);
  }
  if (sans.isEmpty) throw const FormatException('No moves found');

  final h = game.headers;
  String tag(String k) => h[k] ?? '';
  final result = tag('Result');
  final how = tag('Termination').toLowerCase();
  final termination = how.contains('time')
      ? 'time'
      : pos.isCheckmate
          ? 'mate'
          : (result == '1-0' || result == '0-1')
              ? 'resign'
              : (result == '1/2-1/2' ? 'draw' : 'unknown');
  return ImportedGame(
    headers: {
      'event': tag('Event'),
      'site': tag('Site'),
      'date': tag('Date').isEmpty ? '????.??.??' : tag('Date'),
      'round': tag('Round'),
      'white': tag('White').isEmpty ? 'White' : tag('White'),
      'black': tag('Black').isEmpty ? 'Black' : tag('Black'),
      'result': result.isEmpty ? '*' : result,
      'termination': termination,
    },
    startFen: start.fen,
    sans: sans,
    ucis: ucis,
    fensBefore: fens,
  );
}

/// King moves onto its rook (dartchess) → e1g1 / e1c1.
NormalMove normalizeCastling(Pos pos, NormalMove m) {
  final piece = pos.pieceAt(m.from);
  if (piece?.role != Role.king) return m;
  final target = pos.pieceAt(m.to);
  final ontoRook = target != null && target.color == piece!.color && target.role == Role.rook;
  if (!ontoRook) return m;
  final file = m.to.file > m.from.file ? File.g : File.c;
  return NormalMove(from: m.from, to: Square.fromCoords(file, m.from.rank));
}
