/// Идейная цепочка назад от наказания (раздел 8.3; chessanalyst/ideas.py).
///
/// Подпись: атакующая фигура владельца идеи (отслеживается по ходам), цель
/// (фигура, король или поле) и мотив. «Достигает цели» — взятие этой фигурой,
/// шах от неё или приход на поле.
library;

import 'package:dartchess/dartchess.dart';

import 'classify.dart';
import 'eval.dart';
import 'features.dart';
import 'pos.dart';
import 'settings.dart';

const punishingSteps = ['mistake', 'blunder'];

class Signature {
  const Signature({
    required this.attackerPiece,
    required this.attackerSquare,
    required this.targetKind,
    required this.targetSquare,
    required this.targetPiece,
    required this.motif,
    required this.keySan,
  });

  final String attackerPiece;
  final Square attackerSquare;
  final String targetKind; // piece | king | square
  final Square targetSquare;
  final String? targetPiece;
  final String motif;
  final String keySan;

  String text() {
    final tgt = targetPiece != null ? unicodeSymbol(targetPiece!) : '';
    return '${unicodeSymbol(attackerPiece)}${attackerSquare.name} → $tgt${targetSquare.name} ($motif)';
  }
}

class ChainEntry {
  const ChainEntry({required this.ply, required this.present, required this.attacker, required this.target});

  final int ply;
  final bool present;
  final Square attacker, target;
}

class Idea {
  Idea({
    required this.kind,
    required this.punishPly,
    required this.owner,
    required this.signature,
    required this.startPly,
    required this.missPly,
    required this.distance,
    required this.chain,
    required this.builderPlies,
    this.chunk = '',
  });

  final String kind; // punishment | pass
  final int punishPly;
  final Side owner;
  Side get victim => owner.opposite;
  final Signature signature;
  final int startPly;
  final int? missPly;
  final int? distance;
  final List<ChainEntry> chain;
  final List<int> builderPlies;
  String chunk;
}

/// Данные движка по полуходу партии.
class PlyAnalysis {
  PlyAnalysis({required this.board, required this.lines, required this.played, this.allLines});

  final Pos board;
  final List<Line> lines;
  final Line played;
  final List<Line>? allLines;
}

typedef Step = (Pos, NormalMove);

(Square, Square)? _castlingRook(Pos board, NormalMove move) {
  if (!board.isCastling(move)) return null;
  final rank = move.from.rank;
  if (board.isKingsideCastling(move)) return (Square.fromCoords(File.h, rank), Square.fromCoords(File.f, rank));
  return (Square.fromCoords(File.a, rank), Square.fromCoords(File.d, rank));
}

/// Где была фигура, стоящая на sq после всех steps, до первого из них.
Square trackBack(List<Step> steps, Square sq) {
  for (final (board, move) in steps.reversed) {
    final rook = _castlingRook(board, move);
    if (move.to == sq) {
      sq = move.from;
    } else if (rook != null && rook.$2 == sq) {
      sq = rook.$1;
    }
  }
  return sq;
}

Square? _advance(Pos board, NormalMove move, Square? sq) {
  if (sq == null) return null;
  final rook = _castlingRook(board, move);
  if (move.from == sq) return move.to;
  if (rook != null && rook.$1 == sq) return rook.$2;
  if (move.to == sq) return null;
  if (board.isEnPassant(move)) {
    final epVictim = Square.fromCoords(move.to.file, move.from.rank);
    if (epVictim == sq) return null;
  }
  return sq;
}

bool reaches(Pos board, List<String> pv, Square attacker, Square target, String kind, int window) {
  var b = board;
  Square? att = attacker, tgt = target;
  for (final uci in pv.take(window)) {
    final m = Pos.move(uci);
    if (!b.isLegal(m)) return false;
    final moverIsAttacker = m.from == att;
    if (kind == 'piece' && moverIsAttacker && m.to == tgt) return true;
    final givesCheck = b.givesCheck(m);
    final newAtt = _advance(b, m, att);
    final newTgt = kind == 'square' ? tgt : _advance(b, m, tgt);
    b = b.push(m);
    att = newAtt;
    tgt = newTgt;
    if (att == null || tgt == null) return false;
    if (kind == 'square' && moverIsAttacker && att == target) return true;
    if (kind == 'king' && givesCheck && b.checkers.has(att)) return true;
  }
  return false;
}

// --- подпись ---

String _motif(Pos beforeKey, NormalMove key, List<Step> steps, Square targetSq, bool mate) {
  final owner = beforeKey.turn;
  if (mate) return 'mate';
  if (key.promotion != null) return 'promotion';
  final attackerSq = key.from;
  final piece = beforeKey.pieceAt(attackerSq);
  var arrival = beforeKey;
  for (var i = 0; i < steps.length; i++) {
    final (b, m) = steps[i];
    if (b.turn == owner && m.to == attackerSq) arrival = i + 1 < steps.length ? steps[i + 1].$1 : beforeKey;
  }
  final valuable = arrival.attacks(attackerSq).squares.where((sq) {
    final p = arrival.pieceAt(sq);
    return p != null && p.color != owner && (p.role == Role.king || pieceValues[p.role]! >= 3);
  }).length;
  if (valuable >= 2) return 'fork';
  if (beforeKey.isPinned(owner.opposite, targetSq)) return 'pin';
  final ownPrev = steps.where((st) => st.$1.turn == owner).toList();
  const sliders = [Role.bishop, Role.rook, Role.queen];
  if (ownPrev.isNotEmpty && piece != null && sliders.contains(piece.role)) {
    final (b, m) = ownPrev.last;
    if (m.to != attackerSq && !b.attacks(attackerSq).has(targetSq)) return 'discovered';
  }
  if (piece != null && (piece.role == Role.rook || piece.role == Role.queen)) {
    final file = attackerSq.file;
    final hasPawn = List.generate(8, (r) => Square.fromCoords(file, Rank(r)))
        .any((sq) => beforeKey.roleAt(sq) == Role.pawn);
    if (!hasPawn) return 'open_line';
  }
  if (!beforeKey.isAttackedBy(owner.opposite, targetSq)) return 'hanging';
  return 'material';
}

Signature _make(Pos before, NormalMove key, List<Step> steps, String kind, Square targetSq, String? targetPiece,
    {bool mate = false, String? motif}) {
  final piece = before.pieceAt(key.from)!;
  final m = motif ?? _motif(before, key, steps, targetSq, mate);
  final attacker0 = trackBack(steps, key.from);
  final target0 = kind == 'square' ? targetSq : trackBack(steps, targetSq);
  return Signature(
    attackerPiece: pieceSymbol(piece),
    attackerSquare: attacker0,
    targetKind: kind,
    targetSquare: target0,
    targetPiece: targetPiece,
    motif: m,
    keySan: before.san(key),
  );
}

typedef _Capture = (int, Pos, NormalMove);

Signature _captureSig(_Capture capture, List<Step> steps) {
  final (idx, board, move) = capture;
  final target = board.pieceAt(move.to)!;
  return _make(board, move, steps.sublist(0, idx), 'piece', move.to, pieceSymbol(target));
}

Signature? extractSignature(Pos board, List<String> pv, Settings s) {
  final owner = board.turn;
  var b = board;
  final startBalance = balance(b, owner);
  final steps = <Step>[];
  _Capture? lastCapture;
  _Capture? biggest;
  for (final uci in pv.take(s.ideaScanPlies)) {
    final m = Pos.move(uci);
    if (!b.isLegal(m)) break;
    final before = b;
    final isOwner = b.turn == owner;
    final captured = b.pieceAt(m.to);
    b = b.push(m);
    if (isOwner && b.isCheckmate) {
      return _make(before, m, steps, 'king', before.king(owner.opposite)!, null, mate: true);
    }
    if (isOwner && m.promotion != null) return _make(before, m, steps, 'square', m.to, null);
    if (isOwner && captured != null) {
      lastCapture = (steps.length, before, m);
      if (biggest == null ||
          pieceValues[captured.role]! > pieceValues[biggest.$2.roleAt(biggest.$3.to)]!) {
        biggest = lastCapture;
      }
    }
    steps.add((before, m));
    if (lastCapture != null && balance(b, owner) - startBalance >= s.ideaMinGain) {
      return _captureSig(lastCapture, steps);
    }
  }
  if (biggest != null && pieceValues[biggest.$2.roleAt(biggest.$3.to)]! >= s.ideaMinGain) {
    return _captureSig(biggest, steps);
  }
  for (final (before, m) in steps) {
    if (before.turn == owner && before.roleAt(m.from) != Role.king) {
      return _make(before, m, const [], 'square', m.to, null, motif: 'plan');
    }
  }
  return null;
}

// --- цепочка ---

List<Line> _linesAt(List<PlyAnalysis> analysed, int j) {
  final a = analysed[j];
  final lines = List<Line>.of(a.lines);
  if (lines.every((ln) => ln.move != a.played.move)) lines.add(a.played);
  return lines;
}

Idea? buildChain(List<PlyAnalysis> analysed, List<MoveRecord> records, int k, Settings s,
    {String kind = 'punishment'}) {
  final window = s.ideaWindowPlies;
  final gameSteps = [for (final a in analysed) (a.board, Pos.move(a.played.move))];

  final int p;
  final Pos ownerBoard;
  final List<String> ownerPv;
  if (kind == 'punishment') {
    final mistake = analysed[k];
    ownerBoard = mistake.board.push(Pos.move(mistake.played.move));
    ownerPv = k + 1 < analysed.length ? analysed[k + 1].lines.first.pv : mistake.played.pv.sublist(1);
    p = k + 1;
  } else {
    // pass — лучшая несыгранная линия; brilliant — сыгранная линия блестящего хода
    p = k;
    ownerBoard = analysed[k].board;
    ownerPv = kind == 'brilliant' ? analysed[k].played.pv : analysed[k].lines.first.pv;
  }
  if (ownerPv.isEmpty) return null;
  final sig = extractSignature(ownerBoard, ownerPv, s);
  if (sig == null) return null;
  final owner = ownerBoard.turn;

  (Square, Square) squaresAt(int j) {
    final slice = gameSteps.sublist(j, p.clamp(0, gameSteps.length));
    final att = trackBack(slice, sig.attackerSquare);
    final tgt = sig.targetKind == 'square' ? sig.targetSquare : trackBack(slice, sig.targetSquare);
    return (att, tgt);
  }

  final chain = [ChainEntry(ply: p, present: true, attacker: sig.attackerSquare, target: sig.targetSquare)];
  var start = p;
  final builders = <int>[];
  var j = sig.motif != 'plan' ? p - 2 : -1;
  while (j >= 0) {
    final board = analysed[j].board;
    final (att, tgt) = squaresAt(j);
    final piece = board.pieceAt(att);
    if (piece == null || piece.color != owner) break;
    final present = _linesAt(analysed, j).any((ln) => reaches(board, ln.pv, att, tgt, sig.targetKind, window));
    chain.add(ChainEntry(ply: j, present: present, attacker: att, target: tgt));
    if (!present) break;
    start = j;
    if (reaches(board, analysed[j].played.pv, att, tgt, sig.targetKind, window)) builders.add(j);
    j -= 2;
  }

  int? miss;
  int? distance;
  if (kind == 'punishment') {
    for (var m = start + 1; m < k + 1; m += 2) {
      final board = analysed[m].board;
      final (att, tgt) = squaresAt(m);
      final best = analysed[m].lines.first;
      final stops = !reaches(board, best.pv, att, tgt, sig.targetKind, window + 1);
      if (stops && records[m].step != 'best' && records[m].step != forcedStep) {
        miss = m;
        break;
      }
    }
    miss ??= k;
    distance = k - miss;
  }

  chain.sort((a, b) => a.ply.compareTo(b.ply));
  builders.sort();
  return Idea(
    kind: kind,
    punishPly: k,
    owner: owner,
    signature: sig,
    startPly: start,
    missPly: miss,
    distance: distance,
    chain: chain,
    builderPlies: builders,
  )..chunk = makeChunk(ownerBoard, ownerPv, sig, s);
}

String makeChunk(Pos board, List<String> pv, Signature sig, Settings s) {
  final owner = board.turn;
  final support = <Square>{
    for (final sq in board.attackers(owner, sig.targetSquare).squares)
      if (sq != sig.attackerSquare) sq,
  };
  var b = board;
  final steps = <Step>[];
  for (final uci in pv.take(s.ideaScanPlies)) {
    final m = Pos.move(uci);
    if (!b.isLegal(m) || b.san(m) == sig.keySan) break;
    if (b.turn == owner) {
      final origin = trackBack(steps, m.from);
      if (origin != sig.attackerSquare) support.add(origin);
    }
    steps.add((b, m));
    b = b.push(m);
  }
  final names = <String>[];
  for (final sq in support.toList()..sort()) {
    final p = board.pieceAt(sq);
    if (p != null && p.color == owner && p.role != Role.king) {
      names.add('${unicodeSymbol(pieceSymbol(p))}${sq.name}');
    }
  }
  return sig.text() + (names.isNotEmpty ? ' | ${names.join(', ')}' : '');
}

List<Idea> findIdeas(List<PlyAnalysis> analysed, List<MoveRecord> records, Settings s) {
  final ideas = <Idea>[];
  for (final r in records) {
    if (r.flags.contains('theory') || r.flags.contains('book')) continue;
    Idea? idea;
    if (punishingSteps.contains(r.step)) {
      idea = buildChain(analysed, records, r.ply, s);
    } else if (r.flags.contains('pass')) {
      idea = buildChain(analysed, records, r.ply, s, kind: 'pass');
    } else if (r.subtype == 'brilliant') {
      idea = buildChain(analysed, records, r.ply, s, kind: 'brilliant');
    } else {
      continue;
    }
    if (idea != null) ideas.add(idea);
  }
  return ideas;
}
