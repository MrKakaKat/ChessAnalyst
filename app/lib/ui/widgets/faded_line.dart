/// One line of text that scrolls sideways instead of wrapping, its right
/// edge fading out (engine lines).
library;

import 'package:flutter/material.dart';

class FadedLine extends StatelessWidget {
  const FadedLine(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0, 0.85, 1],
        ).createShader(rect),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(right: 32),
          child: Text(text, style: style, maxLines: 1, softWrap: false),
        ),
      );
}
