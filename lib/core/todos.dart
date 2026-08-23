/// Port of the server's `src/todos.ts`.
///
/// Like a poll, a checklist lives *in the body*: a line containing `#todo`, then one
/// `[ ]` or `[x]` line per item. So the app has to parse it for the same two reasons
/// — without it the item lines render as ordinary text, and with it they can be drawn
/// as a list.
///
/// Unlike a poll, there is no endpoint for ticking one off. Toggling rewrites the
/// body and saves it as an edit, which means **only the author can tick their own
/// list** — the same rule the site has, and a consequence of the design rather than a
/// limitation of the client.
library;

import 'content.dart';

final class TodoItem {
  const TodoItem({required this.label, required this.checked, required this.line});

  final String label;
  final bool checked;

  /// Which line of the body it came from, so a toggle can rewrite exactly that one.
  final int line;
}

final class Todo {
  const Todo({required this.items});

  final List<TodoItem> items;

  int get checked => items.where((item) => item.checked).length;

  bool get complete => items.isNotEmpty && checked == items.length;
}

final _marker = RegExp(r'#todo\b', caseSensitive: false);
final _item = RegExp(r'^\s*\[([ xX])\][ \t]?(.*)$');

/// The checklist in [body], or null when there is not one.
///
/// A `#todo` inside a code span does not start a list, which is why this looks for
/// the marker in the code-stripped copy but reads the items from the original.
Todo? parseTodo(String body) {
  final lines = body.split('\n');
  final marker = withoutMarkdownCode(body).split('\n').indexWhere(_marker.hasMatch);
  if (marker < 0) return null;

  final items = <TodoItem>[];
  for (var offset = marker + 1; offset < lines.length; offset++) {
    final match = _item.firstMatch(lines[offset]);
    // A line that is not an item is just text between them, and is left alone.
    if (match == null || match[2]!.trim().isEmpty) continue;
    items.add(TodoItem(
      label: match[2]!.trimRight(),
      checked: match[1]!.toLowerCase() == 'x',
      line: offset,
    ));
  }

  return items.isEmpty ? null : Todo(items: items);
}

/// The body with the item lines removed, which is what renders above the list.
String todoDisplayBody(String body) {
  if (parseTodo(body) == null) return body;
  final lines = body.split('\n');
  final marker = withoutMarkdownCode(body).split('\n').indexWhere(_marker.hasMatch);
  return lines.sublist(0, marker + 1).join('\n').trimRight();
}

/// Flip one item, giving back the body to save. Null when there is no such item.
String? toggleTodo(String body, int itemIndex) {
  final todo = parseTodo(body);
  if (todo == null || itemIndex < 0 || itemIndex >= todo.items.length) return null;

  final item = todo.items[itemIndex];
  final lines = body.split('\n');
  // Mapped, not a plain replacement: Dart does not interpolate `$1` in a String
  // replacement, so the groups have to be spliced back by hand.
  lines[item.line] = lines[item.line].replaceFirstMapped(
    RegExp(r'^(\s*\[)[ xX](\])'),
    (match) => '${match[1]}${item.checked ? ' ' : 'x'}${match[2]}',
  );
  return lines.join('\n');
}
