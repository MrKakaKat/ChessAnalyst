/// Own board squares: a picture from the device, cut to a square — drag to
/// move it, pinch or the slider to zoom — and saved as a 256×256 PNG for the
/// light or the dark squares (Settings → Board → Own squares).
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

/// Picks a picture and lets the user cut a square from it; the square as PNG,
/// or null when cancelled.
Future<Uint8List?> pickSquareImage(BuildContext context, String title) async {
  final file = await FilePicker.pickFile(type: FileType.image);
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final ui.Image image;
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    image = (await codec.getNextFrame()).image;
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This picture could not be read.')));
    }
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CropScreen(image: image, title: title)));
}

class _CropScreen extends StatefulWidget {
  const _CropScreen({required this.image, required this.title});

  final ui.Image image;
  final String title;

  @override
  State<_CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<_CropScreen> {
  static const _maxZoom = 8.0;

  double _side = 280;
  double _zoom = 1;
  Offset _offset = Offset.zero;
  bool _placed = false;

  double _zoomAtStart = 1;
  Offset _focusAtStart = Offset.zero;
  Offset _offsetAtStart = Offset.zero;

  double get _w => widget.image.width.toDouble();
  double get _h => widget.image.height.toDouble();

  /// Screen pixels per image pixel: the picture covers the square at zoom 1.
  double get _scale => _side / math.min(_w, _h) * _zoom;

  /// Keeps the square inside the picture.
  Offset _clamp(Offset o) {
    final dw = _w * _scale, dh = _h * _scale;
    return Offset(o.dx.clamp(_side - dw, 0.0), o.dy.clamp(_side - dh, 0.0));
  }

  /// Zooms to [z] keeping the point [focus] of the square in place.
  void _zoomTo(double z, Offset focus, {Offset? from, double? fromZoom}) {
    final z0 = fromZoom ?? _zoom, o0 = from ?? _offset;
    final s0 = _side / math.min(_w, _h) * z0;
    final s1 = _side / math.min(_w, _h) * z;
    final imgPoint = (focus - o0) / s0;
    _zoom = z;
    _offset = _clamp(focus - imgPoint * s1);
  }

  Future<void> _save() async {
    const out = 256.0;
    final s = _scale;
    final src = Rect.fromLTWH(-_offset.dx / s, -_offset.dy / s, _side / s, _side / s);
    final rec = ui.PictureRecorder();
    Canvas(rec).drawImageRect(widget.image, src, const Rect.fromLTWH(0, 0, out, out),
        Paint()..filterQuality = FilterQuality.high);
    final img = await rec.endRecording().toImage(out.toInt(), out.toInt());
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (!mounted || data == null) return;
    Navigator.pop(context, data.buffer.asUint8List());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [TextButton(onPressed: _save, child: const Text('Use'))],
      ),
      body: LayoutBuilder(builder: (context, box) {
        _side = math.min(box.maxWidth - 48, 360).toDouble();
        if (!_placed) {
          // сначала — середина картинки
          _placed = true;
          final s = _scale;
          _offset = _clamp(Offset((_side - _w * s) / 2, (_side - _h * s) / 2));
        } else {
          _offset = _clamp(_offset);
        }
        final s = _scale;
        return ListView(padding: const EdgeInsets.all(24), children: [
          Center(
            child: GestureDetector(
              onScaleStart: (d) {
                _zoomAtStart = _zoom;
                _focusAtStart = d.localFocalPoint;
                _offsetAtStart = _offset;
              },
              onScaleUpdate: (d) => setState(() {
                final z = (_zoomAtStart * d.scale).clamp(1.0, _maxZoom);
                // перетаскивание и щипок вместе: точка под пальцами остаётся под ними
                _zoomTo(z, _focusAtStart, from: _offsetAtStart, fromZoom: _zoomAtStart);
                _offset = _clamp(_offset + (d.localFocalPoint - _focusAtStart));
              }),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox.square(
                  dimension: _side,
                  child: Stack(children: [
                    Positioned(
                      left: _offset.dx,
                      top: _offset.dy,
                      width: _w * s,
                      height: _h * s,
                      child: RawImage(image: widget.image, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
                    ),
                    // рамка квадрата
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                            decoration: BoxDecoration(border: Border.all(color: scheme.primary, width: 2))),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.zoom_out_rounded, size: 20),
            Expanded(
              child: Slider(
                value: _zoom,
                min: 1,
                max: _maxZoom,
                onChanged: (v) => setState(() => _zoomTo(v, Offset(_side / 2, _side / 2))),
              ),
            ),
            const Icon(Icons.zoom_in_rounded, size: 20),
          ]),
          Text('Drag to move the picture, pinch or use the slider to zoom. The square becomes one board square.',
              style: TextStyle(fontSize: 12, color: scheme.outline)),
        ]);
      }),
    );
  }
}
