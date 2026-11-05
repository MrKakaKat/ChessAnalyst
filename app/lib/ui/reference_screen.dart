/// Analysis guide: docs/analysis_guide.md (copied into the app's assets,
/// a test keeps the copy equal) shown as a page. A small reader for the
/// Markdown the file uses: headings, paragraphs, lists, tables, bold and
/// code.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key});

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

class _ReferenceScreenState extends State<ReferenceScreen> {
  String? _text;

  @override
  void initState() {
    super.initState();
    rootBundle.loadString('assets/docs/analysis_guide.md').then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = _text;
    return Scaffold(
      appBar: AppBar(title: const Text('Analysis guide')),
      body: t == null
          ? const Center(child: CircularProgressIndicator())
          : SelectionArea(
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: markdownBlocks(context, t)),
            ),
    );
  }
}

/// Inline text: **bold** and `code`.
InlineSpan inlineSpan(String s, TextStyle base) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');
  var at = 0;
  for (final m in re.allMatches(s)) {
    if (m.start > at) spans.add(TextSpan(text: s.substring(at, m.start)));
    if (m.group(1) != null) {
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
    } else {
      spans.add(TextSpan(text: m.group(2), style: const TextStyle(fontFamily: 'monospace')));
    }
    at = m.end;
  }
  if (at < s.length) spans.add(TextSpan(text: s.substring(at)));
  return TextSpan(style: base, children: spans);
}

List<Widget> markdownBlocks(BuildContext context, String md) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final body = theme.textTheme.bodyMedium!.copyWith(height: 1.4);
  final out = <Widget>[];
  final lines = md.split('\n');
  var i = 0;
  final para = <String>[];
  void flush() {
    if (para.isEmpty) return;
    out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4), child: Text.rich(inlineSpan(para.join(' '), body))));
    para.clear();
  }

  while (i < lines.length) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed == '---') {
      flush();
      if (trimmed == '---') out.add(const Divider(height: 24));
      i++;
      continue;
    }
    if (trimmed.startsWith('#')) {
      flush();
      final level = trimmed.indexOf(' ');
      final text = trimmed.substring(level + 1);
      final style = switch (level) {
        1 => theme.textTheme.headlineSmall,
        2 => theme.textTheme.titleLarge,
        _ => theme.textTheme.titleMedium,
      };
      out.add(Padding(
          padding: EdgeInsets.only(top: level <= 2 ? 18 : 12, bottom: 4),
          child: Text.rich(inlineSpan(text, style!.copyWith(fontWeight: FontWeight.w700)))));
      i++;
      continue;
    }
    if (trimmed.startsWith('|')) {
      flush();
      final rows = <List<String>>[];
      while (i < lines.length && lines[i].trim().startsWith('|')) {
        final cells = lines[i].trim().split('|');
        final row = cells.sublist(1, cells.length - 1).map((c) => c.trim()).toList();
        if (!row.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) rows.add(row);
        i++;
      }
      out.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.all(color: scheme.outlineVariant, width: 0.8),
            children: [
              for (final (k, r) in rows.indexed)
                TableRow(
                  decoration: k == 0 ? BoxDecoration(color: scheme.surfaceContainerHighest) : null,
                  children: [
                    for (final c in r)
                      Padding(
                        padding: const EdgeInsets.all(6),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 260),
                          child: Text.rich(inlineSpan(c, body.copyWith(fontWeight: k == 0 ? FontWeight.w700 : null))),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ));
      continue;
    }
    final bullet = RegExp(r'^(\s*)(-|\d+\.)\s+(.*)$').firstMatch(line);
    if (bullet != null) {
      flush();
      final depth = bullet.group(1)!.length ~/ 2;
      var text = bullet.group(3)!;
      i++;
      // продолжение пункта на следующих строках с отступом
      while (i < lines.length &&
          lines[i].startsWith(' ') &&
          lines[i].trim().isNotEmpty &&
          RegExp(r'^\s*(-|\d+\.)\s+').firstMatch(lines[i]) == null) {
        text += ' ${lines[i].trim()}';
        i++;
      }
      final mark = bullet.group(2) == '-' ? '•' : bullet.group(2)!;
      out.add(Padding(
        padding: EdgeInsets.only(left: 8.0 + depth * 16, top: 2, bottom: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 18, child: Text(mark, style: body)),
          Expanded(child: Text.rich(inlineSpan(text, body))),
        ]),
      ));
      continue;
    }
    para.add(trimmed);
    i++;
  }
  flush();
  return out;
}
