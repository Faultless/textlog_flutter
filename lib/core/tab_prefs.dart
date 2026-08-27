/// The reader's tab arrangement, applied to whatever tabs a build offers.
///
/// Kept pure and separate from the widget because the interesting cases are all
/// about *disagreement* between a stored preference and the tabs that actually
/// exist: a tab added by a later version, one removed, one that needs signing in,
/// and the reader having hidden everything.
library;

/// [available] in the reader's order, minus the ones they hid.
///
/// Rules, in order of who wins:
///
/// - A tab not in [available] is dropped. A stored order can name `for you` from a
///   session when you were signed in; it must not reappear when you are not.
/// - A tab in [available] but missing from a non-empty [order] is **appended**, not
///   dropped. Otherwise a tab added by a later version would be invisible to anyone
///   who had ever touched this setting, and would look like a broken upgrade.
/// - An empty [order] means "as shipped".
/// - [hidden] applies last, but never to the point of nothing: hiding every tab
///   leaves the first one standing, because a tab row with no tabs is a dead app
///   with no way back to the setting that broke it.
List<T> arrangeTabs<T>(
  List<T> available, {
  required List<String> order,
  required Set<String> hidden,
  required String Function(T) id,
}) {
  final byId = {for (final tab in available) id(tab): tab};

  final arranged = <T>[for (final wanted in order) ?byId[wanted]];
  for (final tab in available) {
    if (!arranged.contains(tab)) arranged.add(tab);
  }

  final shown = [for (final tab in arranged) if (!hidden.contains(id(tab))) tab];
  return shown.isEmpty ? [arranged.first] : shown;
}
