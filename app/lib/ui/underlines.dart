/// Mistakes the player underlined: not understood as mistakes at the time.
/// They weigh double in the weakness profile, so puzzles like them come up
/// more often. Kept on the device as "gameId:ply".
library;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Underlines extends ChangeNotifier {
  static const _key = 'underlined';
  Set<String> _keys = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final p = await SharedPreferences.getInstance();
      _keys = {...?p.getStringList(_key)};
    } catch (_) {}
    _loaded = true;
    notifyListeners();
  }

  bool has(String gameId, int ply) => _keys.contains('$gameId:$ply');

  Future<void> toggle(String gameId, int ply) async {
    final k = '$gameId:$ply';
    if (!_keys.remove(k)) _keys.add(k);
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_key, _keys.toList());
    } catch (_) {}
  }
}

final underlines = Underlines()..load();
