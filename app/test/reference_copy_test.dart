import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the in-app analysis guide is the same as docs/analysis_guide.md', () {
    // после правки гайда: cp ../docs/analysis_guide.md assets/docs/
    expect(File('assets/docs/analysis_guide.md').readAsStringSync(),
        File('../docs/analysis_guide.md').readAsStringSync());
  });
}
