/// Set up a position on the analysis board: clear the board, put pieces on
/// it, choose who moves. The castling rights follow the kings and rooks on
/// their first squares. Returns the position's FEN.
library;

import 'dart:math' as math;

import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart' hide Board;
import 'package:flutter/material.dart';

import 'prefs.dart';

/// Opens the editor with [fen]; the edited position's FEN, or null.
Future<String?> editPosition(BuildContext context, String fen) => Navigator.of(context)
    .push<String>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => _EditorScreen(fen: fen)));

class _EditorScreen extends StatefulWidget {
  const _EditorScreen({required this.fen});

  final String fen;

  @override
  State<_EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<_EditorScreen> {
  late Pieces _pieces = readFen(widget.fen.split(' ').first);
  late Side _turn = widget.fen.split(' ').length > 1 && widget.fen.split(' ')[1] == 'b' ? Side.black : Side.white;
  Side _orientation = Side.white;

  /// The piece put on a tapped square (null: tapping removes a piece).
  Piece? _brush;
  bool _erase = false;

  static const _roles = [Role.king, Role.queen, Role.rook, Role.bishop, Role.knight, Role.pawn];

  String get _castling {
    bool at(String sq, Side side, Role role) => _pieces[Square.fromName(sq)] == Piece(color: side, role: role);
    final out = StringBuffer();
    if (at('e1', Side.white, Role.king)) {
      if (at('h1', Side.white, Role.rook)) out.write('K');
      if (at('a1', Side.white, Role.rook)) out.write('Q');
    }
    if (at('e8', Side.black, Role.king)) {
      if (at('h8', Side.black, Role.rook)) out.write('k');
      if (at('a8', Side.black, Role.rook)) out.write('q');
    }
    return out.isEmpty ? '-' : out.toString();
  }

  String get _fen => '${writeFen(_pieces)} ${_turn == Side.white ? 'w' : 'b'} $_castling - 0 1';

  /// Why the position cannot be played, or null.
  String? get _problem {
    final kings = _pieces.values.where((p) => p.role == Role.king);
    if (kings.where((p) => p.color == Side.white).length != 1 || kings.where((p) => p.color == Side.black).length != 1) {
      return 'Each side needs one king.';
    }
    if (_pieces.entries.any((e) => e.value.role == Role.pawn && (e.key.rank == Rank.first || e.key.rank == Rank.eighth))) {
      return 'Pawns cannot stand on the first or the last rank.';
    }
    try {
      Chess.fromSetup(Setup.parseFen(_fen));
      return null;
    } on PositionSetupException catch (e) {
      return switch (e.cause) {
        IllegalSetupCause.oppositeCheck => 'The side not to move is in check.',
        IllegalSetupCause.impossibleCheck => 'This check is impossible.',
        _ => 'This position cannot be played.',
      };
    } catch (_) {
      return 'This position cannot be played.';
    }
  }

  void _put(Square sq) => setState(() {
        if (_erase) {
          _pieces = {..._pieces}..remove(sq);
        } else if (_brush != null) {
          _pieces = {..._pieces, sq: _brush!};
        }
      });

  Widget _palette(Side side, double sq) {
    final scheme = Theme.of(context).colorScheme;
    // серая подложка: чёрные фигуры не сливаются с тёмной темой
    return Container(
      decoration: BoxDecoration(color: const Color(0xFFB9BCC0), borderRadius: BorderRadius.circular(6)),
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      for (final role in _roles)
        () {
          final piece = Piece(color: side, role: role);
          final selected = !_erase && _brush == piece;
          final icon = PieceWidget(piece: piece, size: sq, pieceAssets: prefs.pieceSet.assets);
          return Draggable<Piece>(
            data: piece,
            feedback: PieceDragFeedback(piece: piece, squareSize: sq, pieceAssets: prefs.pieceSet.assets),
            child: GestureDetector(
              onTap: () => setState(() {
                _erase = false;
                _brush = selected ? null : piece;
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: selected ? scheme.primaryContainer : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: icon,
              ),
            ),
          );
        }(),
    ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final problem = _problem;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up a position'),
      ),
      body: LayoutBuilder(builder: (context, box) {
        final size = math.min(box.maxWidth - 24, math.min(520.0, box.maxHeight * 0.55));
        final sq = math.min(size / 8, (box.maxWidth - 24) / 6.6);
        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
          _palette(_orientation.opposite, sq),
          const SizedBox(height: 6),
          Center(
            child: ChessboardEditor(
              size: size,
              orientation: _orientation,
              pieces: _pieces,
              pointerMode: _brush != null || _erase ? EditorPointerMode.edit : EditorPointerMode.drag,
              settings: ChessboardSettings(
                colorScheme: prefs.scheme,
                pieceAssets: prefs.pieceSet.assets,
                borderRadius: const BorderRadius.all(Radius.circular(6)),
              ),
              onEditedSquare: _put,
              onDroppedPiece: (origin, dest, piece) => setState(() {
                _pieces = {..._pieces};
                if (origin != null) _pieces.remove(origin);
                _pieces[dest] = piece;
              }),
              onDiscardedPiece: (sq) => setState(() => _pieces = {..._pieces}..remove(sq)),
            ),
          ),
          const SizedBox(height: 6),
          _palette(_orientation, sq),
          const SizedBox(height: 12),
          // инструменты — в одну строку, листаются вбок
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
            FilterChip(
              avatar: const Icon(Icons.auto_fix_normal_rounded, size: 18),
              label: const Text('Eraser'),
              selected: _erase,
              showCheckmark: false,
              onSelected: (v) => setState(() {
                _erase = v;
                if (v) _brush = null;
              }),
            ),
            ActionChip(
              avatar: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear the board'),
              onPressed: () => setState(() => _pieces = {}),
            ),
            ActionChip(
              avatar: const Icon(Icons.restart_alt_rounded, size: 18),
              label: const Text('Start position'),
              onPressed: () => setState(() {
                _pieces = readFen(kInitialBoardFEN);
                _turn = Side.white;
              }),
            ),
            ].expand((w) => [w, const SizedBox(width: 8)]).toList()),
          ),
          const SizedBox(height: 12),
          SegmentedButton<Side>(
            segments: const [
              ButtonSegment(value: Side.white, label: Text('White to move')),
              ButtonSegment(value: Side.black, label: Text('Black to move')),
            ],
            selected: {_turn},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() => _turn = s.first),
          ),
          const SizedBox(height: 12),
          // Done — во всю ширину, справа разворот доски
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: problem == null ? () => Navigator.pop(context, _fen) : null,
                icon: const Icon(Icons.check_rounded),
                label: const Text('Done'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Flip the board',
              onPressed: () => setState(() => _orientation = _orientation.opposite),
              icon: const Icon(Icons.swap_vert_rounded),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            problem ??
                'Drag pieces on, off and around the board, or pick a piece (or the eraser) and tap the squares. '
                    'Castling: ${_castling == '-' ? 'none' : _castling} (from the kings and rooks on their squares).',
            style: TextStyle(fontSize: 12, color: problem != null ? scheme.error : scheme.outline),
          ),
        ]);
      }),
    );
  }
}
