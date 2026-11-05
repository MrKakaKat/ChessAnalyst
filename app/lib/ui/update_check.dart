/// Update notice: once a day at start the app asks GitHub for the latest
/// release of ChessAnalyst and, when it is newer than this build, offers it.
///
/// [авторское] No server of our own: the public releases page answers
/// anyone (api.github.com, no key; 60 requests an hour per address, one a
/// day is used). Only the request itself is sent — no data about the user or
/// the games. The version of this build comes from the release build
/// (--dart-define=APP_VERSION=1.2.2); test builds without it never ask.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

const appVersion = String.fromEnvironment('APP_VERSION');
const releasesRepo = 'MrKakaKat/ChessAnalyst';

/// A newer release: its version, notes and page.
class Release {
  const Release(this.version, this.notes, this.page, this.apk);

  final String version, notes, page;
  final String? apk;
}

/// Whether [a] is a newer version than [b] ("1.2.10" > "1.2.9").
bool newerVersion(String a, String b) {
  List<int> parts(String v) => [for (final x in v.replaceFirst('v', '').split('.')) int.tryParse(x) ?? 0];
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 4; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// The latest release when it is newer than this build (null otherwise, on
/// test builds, offline, or when it was checked less than a day ago and
/// [force] is false).
Future<Release?> checkForUpdate({bool force = false}) async {
  if (appVersion.isEmpty) return null;
  try {
    final p = await SharedPreferences.getInstance();
    final last = DateTime.tryParse(p.getString('update.checked') ?? '');
    if (!force && last != null && DateTime.now().difference(last) < const Duration(days: 1)) return null;
    final r = await http
        .get(Uri.parse('https://api.github.com/repos/$releasesRepo/releases/latest'),
            headers: {'Accept': 'application/vnd.github+json'})
        .timeout(const Duration(seconds: 10));
    await p.setString('update.checked', DateTime.now().toIso8601String());
    if (r.statusCode != 200) return null;
    final j = jsonDecode(r.body) as Map<String, dynamic>;
    final tag = (j['tag_name'] as String? ?? '').replaceFirst('v', '');
    if (!newerVersion(tag, appVersion)) return null;
    // окно о той же версии — один раз
    if (!force && p.getString('update.shown') == tag) return null;
    await p.setString('update.shown', tag);
    String? apk;
    for (final a in (j['assets'] as List? ?? const [])) {
      final name = (a as Map)['name'] as String? ?? '';
      if (name.endsWith('.apk')) apk = a['browser_download_url'] as String?;
    }
    return Release(tag, j['body'] as String? ?? '', j['html_url'] as String? ?? '', apk);
  } catch (_) {
    return null;
  }
}

/// Shows the notice about [r].
Future<void> showUpdate(BuildContext context, Release r) => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.system_update_rounded),
        title: Text('ChessAnalyst ${r.version} is out'),
        content: SingleChildScrollView(
          child: Text(
            'You have $appVersion. The new version installs over this one; your games and settings stay.'
            '${r.notes.trim().isEmpty ? '' : '\n\n${r.notes.trim()}'}',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              // на Android — сразу APK, в браузере — страница релиза
              final url = Theme.of(context).platform == TargetPlatform.android && r.apk != null ? r.apk! : r.page;
              launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
