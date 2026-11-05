import 'dart:ui';

import 'package:chessanalyst/ui/icon_paths.dart';
import 'package:chessanalyst/ui/step_icons.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all icon paths parse into non-empty shapes', () {
    for (final d in [questionPath, bangPath, starPath, thumbPath, bookPath, checkPath, barPath, arrowPath]) {
      expect(parseSvgPath(d).getBounds().isEmpty, isFalse);
    }
  });

  test('every kind draws', () {
    for (final k in iconKinds) {
      final rec = PictureRecorder();
      drawStepGlyph(Canvas(rec), k, 40, const Color(0xFFFFFFFF));
      rec.endRecording();
    }
  });
}
