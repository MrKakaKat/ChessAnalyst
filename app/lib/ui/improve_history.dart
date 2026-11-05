/// History of the Start-to-improve work, per position and mode: how often
/// it was tried and solved, whether the last attempt went without an error,
/// and for Foresight the share of ideas matched last time.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ImproveRecord {
  const ImproveRecord({this.tries = 0, this.solved = 0, this.lastClean, this.lastShare});

  final int tries, solved;

  /// The last attempt: solved without a wrong move first.
  final bool? lastClean;

  /// Foresight: the share of the engine's ideas matched last time (0…1).
  final double? lastShare;

  Map<String, dynamic> toJson() => {
        'tries': tries,
        'solved': solved,
        'clean': ?lastClean,
        'share': ?lastShare,
      };

  factory ImproveRecord.fromJson(Map<String, dynamic> j) => ImproveRecord(
        tries: j['tries'] as int? ?? 0,
        solved: j['solved'] as int? ?? 0,
        lastClean: j['clean'] as bool?,
        lastShare: (j['share'] as num?)?.toDouble(),
      );
}

class ImproveHistory {
  static const _key = 'improve.history';

  static String id(String gameId, int ply, String mode) => '$gameId:$ply:$mode';

  static Future<Map<String, ImproveRecord>> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString(_key);
      if (raw == null) return {};
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, ImproveRecord.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  /// Adds an attempt: [solved] in the end, [clean] without an error first,
  /// [share] for Foresight.
  static Future<ImproveRecord> add(String id, {required bool solved, required bool clean, double? share}) async {
    final all = await load();
    final old = all[id] ?? const ImproveRecord();
    final rec = ImproveRecord(
      tries: old.tries + 1,
      solved: old.solved + (solved ? 1 : 0),
      lastClean: clean,
      lastShare: share ?? old.lastShare,
    );
    all[id] = rec;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_key, jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))));
    } catch (_) {}
    return rec;
  }
}
