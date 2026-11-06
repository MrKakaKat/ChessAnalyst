/// Notifications about finished analyses, and the order of the start-up
/// windows.
///
/// [авторское] Windows at start never pile up: the update notice about the
/// analysis rules, the new version on GitHub, the battery hint and the
/// question about notifications go one after another through [startupQueue],
/// each when the previous one is closed. The notification question is asked
/// once, after the first analysis is started (when it makes sense), not at
/// the first launch.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Start-up windows, one at a time.
Future<void> _queue = Future.value();

Future<void> startupQueue(Future<void> Function() show) {
  final out = _queue.then((_) => show());
  _queue = out.then((_) {}, onError: (_) {});
  return out;
}

final _plugin = FlutterLocalNotificationsPlugin();
bool _ready = false;

Future<bool> _init() async {
  if (kIsWeb) return false;
  if (_ready) return true;
  try {
    await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')));
    _ready = true;
  } catch (_) {}
  return _ready;
}

/// Asks once whether to notify about finished analyses: our own window
/// first, then the system's permission (Android 13+).
Future<void> askNotifications(BuildContext context) => startupQueue(() async {
      if (kIsWeb) return;
      final p = await SharedPreferences.getInstance();
      if (p.getBool('notify.asked') ?? false) return;
      await p.setBool('notify.asked', true);
      if (!context.mounted) return;
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          icon: const Icon(Icons.notifications_active_outlined),
          title: const Text('Tell you when an analysis is done?'),
          content: const Text(
              'An analysis can take a while. A notification says when a game is ready, with the names of the players.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes')),
          ],
        ),
      );
      await p.setBool('notify.on', yes ?? false);
      if (yes != true || !await _init()) return;
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    });

/// "White — Black analysed" when the user agreed to notifications.
Future<void> notifyAnalysisDone(int id, String title) async {
  try {
    final p = await SharedPreferences.getInstance();
    if (!(p.getBool('notify.on') ?? false) || !await _init()) return;
    await _plugin.show(
      id,
      'Analysis finished',
      title,
      const NotificationDetails(
        android: AndroidNotificationDetails('analysis', 'Finished analyses',
            channelDescription: 'A game analysed on the device is ready', importance: Importance.defaultImportance),
      ),
    );
  } catch (_) {}
}
