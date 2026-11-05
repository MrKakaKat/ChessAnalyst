/// Stub for the JS web build. The chess library (dartchess) uses 64-bit
/// bitboards that JavaScript lacks, so in a browser the app runs only as
/// WebAssembly. A browser without WasmGC gets this screen.
library;

import 'package:flutter/material.dart';

import 'ui/theme.dart';

class ChessIdeasApp extends StatelessWidget {
  const ChessIdeasApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ChessAnalyst',
      debugShowCheckedModeBanner: false,
      theme: appTheme(Brightness.light),
      darkTheme: appTheme(Brightness.dark),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'This app needs a browser with WebAssembly GC: Chrome or Edge 119+, Firefox 120+, Safari 18.2+.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
