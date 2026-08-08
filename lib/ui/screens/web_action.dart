import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../state/pending_write.dart';

/// Writing happens on textlog.cc, in the system browser's own tab — Chrome Custom
/// Tabs on Android, SFSafariViewController on iOS.
///
/// This is not a cosmetic choice. textlog authenticates only by emailing a magic
/// link — there is no password anywhere in its `/enter` flow — and that link always
/// opens in whatever browser the phone considers default. An embedded WebView keeps
/// a private cookie jar, so the session would land somewhere the app could never
/// read and replying would be impossible for everyone, forever. A browser tab shares
/// the browser's cookies, so the link works, and you are still signed in next time.

Future<void> openReply(WidgetRef ref, int postId) {
  ref.read(pendingWriteProvider.notifier).expect(PendingReply(postId));
  return _open('/post/$postId?reply=1');
}

Future<void> openCompose(WidgetRef ref) {
  ref.read(pendingWriteProvider.notifier).expect(const PendingPost());
  return _open('/write');
}

Future<void> _open(String path) async {
  final url = Uri.parse('$textlogOrigin$path');

  // On the web a new tab is the same thing, and already shares the session.
  if (kIsWeb) {
    await launchUrl(url, webOnlyWindowName: '_blank');
    return;
  }

  // Falls back to the full browser app where no Custom Tabs provider is installed.
  if (!await launchUrl(url, mode: LaunchMode.inAppBrowserView)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}
