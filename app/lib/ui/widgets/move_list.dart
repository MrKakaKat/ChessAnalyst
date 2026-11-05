/// Move list with step marks and own variations.
///
/// A branch is listed under the game move it starts after, behind its own
/// fold button (the button shows how many branches start there).
///
/// A long press selects a move (a button to copy it appears at the top);
/// dragging on extends the selection over a range of moves, like selecting
/// text; on release the copy button shows at the top or the bottom, away
/// from the finger. Under a move with an idea, the lines of the idea
/// (the missed line and the punishment, from the analysis) open as branches.
///
/// Animations: rows cascade in when the game opens; the current move's
/// background changes smoothly; the list scrolls to it; mark colours blend on
/// a unit switch; branches unfold.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller.dart';
import '../labels.dart';
import '../step_icons.dart';
import 'eval_widgets.dart';

class MoveList extends StatefulWidget {
  const MoveList({super.key, required this.controller, this.bottomPadding = 0, this.header});

  final AnalysisController controller;
  final double bottomPadding;

  /// Shown above the moves and scrolled with them (the game's header and
  /// evaluation in the Game tab).
  final Widget? header;

  @override
  State<MoveList> createState() => _MoveListState();
}

class _MoveListState extends State<MoveList> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  int _lastPly = -1;
  final _folded = <int>{};

  /// Selected range of game plies (long press and drag); the bar with the
  /// copy button stays at the top.
  int? _selA, _selB;

  bool _selected(int ply) {
    final a = _selA, b = _selB;
    if (a == null || b == null) return false;
    return ply >= (a < b ? a : b) && ply <= (a < b ? b : a);
  }

  int? _plyAt(Offset global) {
    for (final e in _keys.entries) {
      final box = e.value.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final local = box.globalToLocal(global);
      if ((Offset.zero & box.size).contains(local) && e.key < c.length) return e.key;
    }
    return null;
  }

  void _startSelect(int ply) => setState(() {
    _selA = _selB = ply;
    _varSel = null;
  });

  void _dragSelect(Offset global) {
    final p = _plyAt(global);
    if (p != null && p != _selB) setState(() => _selB = p);
  }

  void _endSelect(Offset global) {}

  /// A move of a branch held down: it can be copied (the branch up to it)
  /// or deleted with everything after it.
  (Variation, int)? _varSel;

  void _clearSel() => setState(() {
    _selA = _selB = null;
    _varSel = null;
  });

  /// The bar over the list, always at the top: round icon buttons only —
  /// copy, delete (branch moves), close.
  Widget _copyBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget round(IconData icon, String tip, VoidCallback onTap, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: IconButton.filled(
        tooltip: tip,
        style: IconButton.styleFrom(
          backgroundColor: color ?? scheme.inverseSurface,
          foregroundColor: scheme.onInverseSurface,
          elevation: 4,
        ),
        onPressed: onTap,
        icon: Icon(icon, size: 20),
      ),
    );
    final vs = _varSel;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        round(Icons.content_copy_rounded, 'Copy', () {
          final text = vs != null ? c.branchText(vs.$1, vs.$2) : c.movesText(_selA!, _selB!);
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Moves copied')));
          _clearSel();
        }),
        if (vs != null)
          round(Icons.delete_outline_rounded, 'Delete this move and all after it', () {
            c.removeFrom(vs.$1, vs.$2);
            _clearSel();
          }, color: scheme.error),
        round(Icons.close_rounded, 'Cancel', _clearSel),
      ],
    );
  }

  AnalysisController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    _scroll.dispose();
    _intro.dispose();
    super.dispose();
  }

  void _onChange() {
    setState(() {});
    if (c.ply != _lastPly) {
      _lastPly = c.ply;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _keys[c.ply]?.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.4,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final plies = c.game.plies;
    final rows = (plies.length + 1) ~/ 2;
    final list = ListView.builder(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(0, 4, 0, 4 + widget.bottomPadding),
      itemCount: rows + (c.end != null ? 1 : 0) + (widget.header != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.header != null && index == 0) return widget.header!;
        final row = widget.header != null ? index - 1 : index;
        if (row == rows) return _endCell(context);
        // каскад: каждая строка появляется чуть позже предыдущей
        final start = (row / rows * 0.6).clamp(0.0, 0.6);
        final anim = CurvedAnimation(
          parent: _intro,
          curve: Interval(start, start + 0.4, curve: Curves.easeOut),
        );
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween(begin: const Offset(0.15, 0), end: Offset.zero).animate(anim),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 34,
                      child: Text(
                        '${row + 1}.',
                        style: TextStyle(color: Theme.of(context).colorScheme.outline, fontSize: 13),
                      ),
                    ),
                    Expanded(child: _cell(context, row * 2)),
                    Expanded(child: row * 2 + 1 < plies.length ? _cell(context, row * 2 + 1) : const SizedBox()),
                  ],
                ),
                if (row == 0) _branches(context, -1),
                _ideaLines(context, row * 2),
                _branches(context, row * 2),
                if (row * 2 + 1 < plies.length) _ideaLines(context, row * 2 + 1),
                if (row * 2 + 1 < plies.length) _branches(context, row * 2 + 1),
              ],
            ),
          ),
        );
      },
    );
    // одна и та же структура с выделением и без: прокрутка не сбрасывается
    return LayoutBuilder(
      builder: (context, box) {
        _listWidth = box.maxWidth;
        return Stack(
          children: [
            list,
            if (_selA != null || _varSel != null)
              Positioned(left: 0, right: 0, top: 6, child: Center(child: _copyBar(context))),
          ],
        );
      },
    );
  }

  /// Under a move with an idea: its lines from the analysis — what the
  /// erring side missed and how the move was punished; a tap opens the line
  /// as a branch.
  Widget _ideaLines(BuildContext context, int ply) {
    final idea = c.analysis.ideaAt(ply);
    if (idea == null || idea.kind == 'brilliant') return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final p = c.game.plies[ply];
    final missed = p.lines.first.pv.isNotEmpty && p.lines.first.move != p.uci ? p.lines.first.pv : const <String>[];
    final punish = ply + 1 < c.length ? c.game.plies[ply + 1].lines.first.pv : const <String>[];
    Widget line(String label, IconData icon, int anchor, int from, List<String> pv) => InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => c.showLine(anchor, pv),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 14, color: scheme.tertiary),
            const SizedBox(width: 4),
            Text(
              '$label ',
              style: TextStyle(fontSize: 12, color: scheme.tertiary, fontWeight: FontWeight.w600),
            ),
            Expanded(
              child: Text(
                c.lineSans(from, pv).join(' '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: scheme.primary),
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(left: 30, right: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (missed.isNotEmpty) line('Better', Icons.lightbulb_outline, ply - 1, ply, missed),
          if (punish.isNotEmpty && idea.kind == 'punishment')
            line('Punished', Icons.bolt_rounded, ply, ply + 1, punish),
        ],
      ),
    );
  }

  Widget _cell(BuildContext context, int ply) {
    final r = c.analysis.records[ply];
    final scheme = Theme.of(context).colorScheme;
    final current = ply == c.ply && !c.inVariation;
    final brilliant = r.subtype == 'brilliant';
    final kind = c.kindAt(ply);
    final color = kind == 'mate' ? c.kindColorAt(ply, kind) : kindColor(kind, Theme.of(context).brightness);
    final quiet = r.step == 'neutral' || r.step == 'forced';
    return Padding(
      key: _keys.putIfAbsent(ply, GlobalKey.new),
      padding: const EdgeInsets.all(1.5),
      child: GestureDetector(
        // зажатие — выделить ход; протяжка — диапазон, как выделение текста
        onLongPressStart: (_) => _startSelect(ply),
        onLongPressMoveUpdate: (d) => _dragSelect(d.globalPosition),
        onLongPressEnd: (d) => _endSelect(d.globalPosition),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () {
            if (_selA != null || _varSel != null) return _clearSel();
            c.select(ply);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            height: 28,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: current ? scheme.primary : (_selected(ply) ? scheme.primaryContainer : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 300),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isError(r.step) || brilliant ? FontWeight.w700 : FontWeight.w500,
                    color: current ? scheme.onPrimary : (quiet ? scheme.onSurface : color),
                  ),
                  child: Text(c.game.plies[ply].san),
                ),
                if (r.step != 'neutral')
                  Padding(
                    padding: const EdgeInsets.only(left: 2),
                    // вердикт сменился при пересчёте — знак меняется с масштабом
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 350),
                      transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                      child: StepGlyph(
                        key: ValueKey(kind),
                        kind: kind,
                        size: 14,
                        color: current ? scheme.onPrimary : color,
                      ),
                    ),
                  ),
                if (c.analysis.ideaAt(ply) != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.lightbulb_outline, size: 14, color: current ? scheme.onPrimary : scheme.tertiary),
                  ),
                // ветки — числом на краю клетки, без отдельной строки
                const Spacer(),
                // нажимается треть клетки справа, не только сам значок
                _branchCount(context, ply, current, hitWidth: (_listWidth - 34) / 2 / 3),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The game's end as a last pseudo-move: Resign / Time out.
  Widget _endCell(BuildContext context) {
    final e = c.end!;
    final scheme = Theme.of(context).colorScheme;
    final current = c.atEnd;
    final color = markColor(e.step ?? 'forced');
    return Padding(
      key: _keys.putIfAbsent(c.length, GlobalKey.new),
      padding: const EdgeInsets.fromLTRB(34, 1.5, 1.5, 1.5),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => c.select(c.length),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: current ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              StepGlyph(kind: e.kind, size: 15, color: current ? scheme.onPrimary : color),
              const SizedBox(width: 6),
              Text(
                '${e.label} · ${c.game.headers['result']}',
                style: TextStyle(fontWeight: FontWeight.w700, color: current ? scheme.onPrimary : color),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Branches starting after [anchor]: a fold button and the branch lines.
  /// The branch count at the edge of the move's cell: a small chip with the
  /// number only; a tap folds or unfolds the branches under the row.
  Widget _branchCount(BuildContext context, int anchor, bool current, {double hitWidth = 0}) {
    final n = c.variationsAt(anchor).length;
    if (n == 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final open = !_folded.contains(anchor);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => open ? _folded.add(anchor) : _folded.remove(anchor)),
      child: Container(
        constraints: BoxConstraints(minWidth: hitWidth.clamp(0.0, 120.0), minHeight: 26),
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: current
                ? scheme.onPrimary.withValues(alpha: 0.2)
                : scheme.tertiary.withValues(alpha: open ? 0.18 : 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.call_split_rounded, size: 11, color: current ? scheme.onPrimary : scheme.tertiary),
              Text(
                '$n',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: current ? scheme.onPrimary : scheme.tertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Width of the list, for the tap area of the branch counts.
  double _listWidth = 360;

  /// Branches starting after [anchor], under the row (folded with the count
  /// chip of the move).
  Widget _branches(BuildContext context, int anchor) {
    final list = c.variationsAt(anchor);
    if (list.isEmpty) return const SizedBox.shrink();
    final open = !_folded.contains(anchor);
    return Padding(
      padding: const EdgeInsets.only(left: 30, right: 6, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ветки от начальной позиции — у них нет клетки хода, счётчик здесь
          if (anchor == -1) _branchCount(context, -1, false),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topLeft,
            child: open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final v in list) _variationLine(context, v)],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _variationLine(BuildContext context, Variation v) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      padding: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: scheme.tertiary, width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Wrap(
              spacing: 2,
              runSpacing: 2,
              children: [
                if (v.forkAt > 0)
                  Text('… ', style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.outline)),
                for (final (i, m) in v.moves.indexed)
                  if (i >= v.forkAt)
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => c.selectVar(v, i),
                      // зажатие хода ветки — скопировать или удалить
                      onLongPress: () => setState(() {
                        _selA = _selB = null;
                        _varSel = (v, i);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                        decoration: BoxDecoration(
                          color: identical(c.variation, v) && c.varIndex == i ? scheme.tertiary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_moveNo(v, i)}${m.san}${m.eval != null ? ' ${whiteEvalText(m.eval!, m.root, c.unit)}' : ''}',
                          style: TextStyle(
                            fontSize: 13,
                            // синие — линии анализа партии, серые — посчитанные на устройстве
                            color: identical(c.variation, v) && c.varIndex == i ? scheme.onTertiary : branchColor(m),
                          ),
                        ),
                      ),
                    ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 16,
            tooltip: 'Delete variation',
            onPressed: () => c.removeVariation(v),
            icon: Icon(Icons.close_rounded, color: scheme.outline),
          ),
        ],
      ),
    );
  }

  String _moveNo(Variation v, int i) {
    final ply = v.anchor + 1 + i;
    if (ply.isEven) return '${ply ~/ 2 + 1}. ';
    return i == 0 ? '${ply ~/ 2 + 1}... ' : '';
  }
}
