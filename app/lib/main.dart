import 'package:flutter/material.dart';

// dart2js (the JS web build) lacks the 64-bit ints dartchess needs; it gets a stub.
import 'app.dart' if (dart.library.html) 'app_unsupported.dart';

void main() => runApp(const ChessIdeasApp());
