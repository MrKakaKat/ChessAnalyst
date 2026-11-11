import 'package:flutter/material.dart';

ThemeData appTheme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2F5D50), brightness: b),
      useMaterial3: true,
    );

/// System blue: an engine line that needs an only move.
const onlyBlue = Color(0xFF0A84FF);
