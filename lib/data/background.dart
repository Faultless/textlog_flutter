import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:workmanager/workmanager.dart';

import '../core/notification_plan.dart';
import 'api.dart';
import 'local_store.dart';
import 'notifications.dart';

/// Polling for activity while the app is not running.
///
/// **Why polling and not push.** textlog does have push, but it is Web Push: the
/// subscription endpoints live under `/account/`, authenticate with a *session cookie*
/// rather than a bearer token, and expect a browser push endpoint with its own key
/// pair. None of that is reachable from a Flutter app. Instant delivery would need an
/// endpoint under `/api/v1/` that takes an FCM or APNs device token — the same shape
/// of gap the write endpoints used to be.
///
/// So this polls `/activities/to-me`, which is precisely replies, mentions and follows
/// of you. The cost is latency: Android will not run periodic work more often than
/// every fifteen minutes, and iOS decides for itself when a background refresh is
/// worth the battery, which can be a good deal longer. That is a real limitation and
/// the setting says so rather than implying instant delivery.
abstract final class Background {
  static const _task = 'textlog-activity-poll';

  /// Android's floor. Asking for less is silently rounded up to this.
  static const interval = Duration(minutes: 15);

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  /// Wire the isolate entry points. Idempotent, and called from every isolate that
  /// needs them — including the one the OS spawns for a periodic poll.
  static Future<void> ready() async {
    // Registered here rather than left to the app, because a notification action
    // arrives in a fresh isolate that never ran `main`.
    await Notifications.ready(onBackground: notificationActionEntry);
    if (!supported) return;
    await Workmanager().initialize(callbackDispatcher);
  }

  static Future<void> schedule() async {
    if (!supported) return;
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: interval,
      // No point waking to poll with no connection.
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  static Future<void> cancel() async {
    if (!supported) return;
    await Workmanager().cancelByUniqueName(_task);
  }

  /// One poll. Returns false only when something went wrong worth retrying.
  ///
  /// Runs in a background isolate, so everything it needs comes out of [LocalStore]
  /// rather than from a provider.
  static Future<bool> poll() async {
    // A fresh isolate: nothing the app set up at launch exists here.
    await Notifications.ready(onBackground: notificationActionEntry);

    final preferences = await LocalStore.preferences();
    if (!preferences.enabled) return true;

    final token = await LocalStore.token();
    if (token == null) return true;

    final client = http.Client();
    try {
      final api = TextlogApi(client);
      final page = await api.activities(token, ActivityScope.toMe, limit: 20);

      final plan = planNotifications(
        activities: page.items,
        alreadyAnnounced: await LocalStore.announced(),
        preferences: preferences,
        viewerHandle: await LocalStore.handle(),
      );

      // Remembered before anything is shown. Announcing twice is worse than not
      // announcing at all, and a crash between the two should fail quiet.
      await LocalStore.remember(plan.announced);

      // The first poll takes a baseline instead of announcing one. Everything
      // unread at the moment you switched notifications on has already been seen
      // somewhere, most likely on the website — telling you about it is noise, and
      // it is the *next* reply you actually want to hear about.
      if (!await LocalStore.primed()) {
        await LocalStore.markPrimed();
        return true;
      }

      for (final notification in plan.notifications) {
        await Notifications.show(notification);
      }
      await Notifications.summarise(plan.notifications.length);
      return true;
    } catch (error) {
      // A failed poll is not worth a retry storm; the next one is fifteen minutes away.
      debugPrint('textlog: activity poll failed: $error');
      return true;
    } finally {
      client.close();
    }
  }

  /// A notification action, possibly with the app closed.
  static Future<void> handleAction({
    String? actionId,
    String? payload,
    String? input,
  }) async {
    final token = await LocalStore.token();
    if (token == null) return;
    final details = decodePayload(payload);

    final client = http.Client();
    try {
      final api = TextlogApi(client);
      switch (actionId) {
        case Notifications.replyAction:
          final parentId = details['reply_to'] as int?;
          final body = input?.trim() ?? '';
          if (parentId == null || body.isEmpty) return;
          await api.createPost(token, body, parentId: parentId);
        case Notifications.markReadAction:
          final activityId = details['activity'] as String?;
          if (activityId == null) return;
          await api.markRead(token, ActivityScope.toMe, [activityId]);
      }
    } catch (error) {
      // There is no UI to report to from a background isolate, but swallowing this
      // without trace made a broken quick reply indistinguishable from a working
      // one during development. A line in the log is the least it can do.
      debugPrint('textlog: notification action $actionId failed: $error');
    } finally {
      client.close();
    }
  }
}

/// The isolate the OS starts for periodic work.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((_, _) => Background.poll());
}

/// The isolate the OS starts when a notification action is used.
///
/// Top-level and marked for the tree shaker, because it is the *entry point* — it
/// cannot rely on anything `main` did, which is exactly the bug that made a quick
/// reply look like it worked and post nothing.
@pragma('vm:entry-point')
void notificationActionEntry(NotificationResponse response) {
  // Fire and forget: the plugin's contract does not await this, and the isolate is
  // torn down when the future completes either way.
  Background.handleAction(
    actionId: response.actionId,
    payload: response.payload,
    input: response.input,
  );
}
