import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/notification_plan.dart';

/// The bridge to the OS notification centre.
///
/// Kept in `data/` with the rest of the I/O, and deliberately dependency-free beyond
/// the plugin so the **background isolate** can use it — the isolate that raises a
/// notification has none of the app's providers, and half of this file exists to be
/// callable from there.
abstract final class Notifications {
  static final _plugin = FlutterLocalNotificationsPlugin();

  /// Where a tapped notification wants to go. `main.dart` listens and navigates.
  ///
  /// A plain notifier rather than a provider, because the tap can arrive before the
  /// app has a widget tree to put a provider in.
  static final route = ValueNotifier<String?>(null);

  /// Replies typed into a notification, so the app can refresh what they landed on.
  static final replied = ValueNotifier<int?>(null);

  static const _channelId = 'textlog-activity';
  static const _group = 'textlog-activity-group';

  /// The iOS/macOS category carrying the reply and mark-read actions.
  static const _replyCategory = 'textlog-reply';
  static const _plainCategory = 'textlog-plain';

  static const replyAction = 'reply';
  static const markReadAction = 'mark-read';

  static var _ready = false;

  /// Only these can raise a notification. Web has no way to, and Windows/Linux are
  /// not built.
  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  /// Safe to call more than once, and from either isolate.
  ///
  /// [onBackground] must be a top-level function: the OS runs a notification action
  /// in a **fresh isolate** that never executed `main`, so anything the app set up at
  /// launch is simply not there. That is not a detail — it is the difference between
  /// a quick reply that posts and one that silently does nothing.
  static Future<void> ready({
    required DidReceiveBackgroundNotificationResponseCallback onBackground,
  }) async {
    if (_ready || !supported) return;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    final darwin = DarwinInitializationSettings(
      // Asked for separately, so the prompt arrives when the reader turns the
      // setting on rather than the first time the app opens.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          _replyCategory,
          actions: [
            DarwinNotificationAction.text(
              replyAction,
              'Reply',
              buttonTitle: 'Send',
              placeholder: 'Reply to this post',
            ),
            DarwinNotificationAction.plain(markReadAction, 'Mark read'),
          ],
          options: {DarwinNotificationCategoryOption.hiddenPreviewShowTitle},
        ),
        DarwinNotificationCategory(
          _plainCategory,
          actions: [DarwinNotificationAction.plain(markReadAction, 'Mark read')],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: darwin, macOS: darwin),
      // Both paths run the same handler. Which one the OS uses depends on whether
      // the app happens to be alive, and a quick reply that works only when the app
      // is closed is worse than one that never works — at least that gets noticed.
      onDidReceiveNotificationResponse: (response) => _onResponse(response, onBackground),
      onDidReceiveBackgroundNotificationResponse: onBackground,
    );
    _ready = true;
  }

  /// Ask for permission, and say whether it was given.
  ///
  /// Android has had a runtime notification permission since 13; before that it is
  /// granted by installing the app, and the plugin answers accordingly.
  static Future<bool> requestPermission() async {
    if (!supported) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final ios = _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
      return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }
    final macos = _plugin
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
    return await macos?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  /// Raise one. Grouped, so a handful arriving together collapse into a stack
  /// rather than filling the shade.
  /// Callers must have called [ready] first — including the background isolate,
  /// which does so through `Background.poll`.
  static Future<void> show(PendingNotification notification) async {
    if (!supported) return;

    final actions = <AndroidNotificationAction>[
      if (notification.canReply)
        const AndroidNotificationAction(
          replyAction,
          'Reply',
          // What makes the shade offer a text field rather than just a button.
          inputs: [AndroidNotificationActionInput(label: 'Reply to this post')],
          showsUserInterface: false,
          cancelNotification: true,
        ),
      const AndroidNotificationAction(
        markReadAction,
        'Mark read',
        showsUserInterface: false,
        cancelNotification: true,
      ),
    ];

    await _plugin.show(
      id: notification.systemId,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Activity',
          channelDescription: 'Replies, mentions and follows',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          groupKey: _group,
          // The body is usually longer than one line.
          styleInformation: BigTextStyleInformation(notification.body),
          actions: actions,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier:
              notification.canReply ? _replyCategory : _plainCategory,
          threadIdentifier: _group,
        ),
        macOS: DarwinNotificationDetails(
          categoryIdentifier:
              notification.canReply ? _replyCategory : _plainCategory,
          threadIdentifier: _group,
        ),
      ),
      payload: jsonEncode({
        'route': notification.route,
        'activity': notification.activityId,
        'reply_to': notification.replyToPostId,
      }),
    );
  }

  /// The Android summary that heads a group. Without it a stack of notifications has
  /// no title of its own.
  static Future<void> summarise(int count) async {
    if (!supported || defaultTargetPlatform != TargetPlatform.android || count < 2) {
      return;
    }
    await _plugin.show(
      id: _group.hashCode & 0x7fffffff,
      title: 'textlog',
      body: '$count new',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Activity',
          channelDescription: 'Replies, mentions and follows',
          groupKey: _group,
          setAsGroupSummary: true,
          importance: Importance.low,
        ),
      ),
    );
  }

  static Future<void> clearAll() async {
    if (!supported) return;
    await _plugin.cancelAll();
  }

  /// A notification tapped or acted on while the app was already running.
  static void _onResponse(
    NotificationResponse response,
    DidReceiveBackgroundNotificationResponseCallback onAction,
  ) {
    final payload = _decode(response.payload);
    switch (response.actionId) {
      case replyAction:
        onAction(response);
        // …and tell the screen behind it to catch up once that lands.
        replied.value = payload['reply_to'] as int?;
      case markReadAction:
        onAction(response);
      default:
        // A plain tap: no work, just go there.
        route.value = payload['route'] as String?;
    }
  }

  /// What the app was launched by, if it was launched by a notification.
  static Future<String?> launchRoute() async {
    if (!supported) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp != true) return null;
    return _decode(details?.notificationResponse?.payload)['route'] as String?;
  }
}

/// Shared with the background handler, which needs the same payload shape.
Map<String, dynamic> decodePayload(String? payload) => _decode(payload);

Map<String, dynamic> _decode(String? payload) {
  if (payload == null || payload.isEmpty) return const {};
  try {
    final decoded = jsonDecode(payload);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}
