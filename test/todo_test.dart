import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/todos.dart';

void main() {
  group('parsing', () {
    test('a #todo line and its items', () {
      final todo = parseTodo('shopping #todo\n[ ] bread\n[x] milk')!;
      expect(todo.items.map((item) => item.label), ['bread', 'milk']);
      expect(todo.items.map((item) => item.checked), [false, true]);
      expect(todo.checked, 1);
      expect(todo.complete, isFalse);
    });

    test('an all-ticked list is complete', () {
      expect(parseTodo('done #todo\n[x] a\n[x] b')!.complete, isTrue);
    });

    test('an upper-case X ticks it too', () {
      expect(parseTodo('q #todo\n[X] a\n[ ] b')!.items.first.checked, isTrue);
    });

    test('the marker may sit anywhere on its line', () {
      expect(parseTodo('my #todo list\n[ ] a'), isNotNull);
    });

    test('lines between items are not items', () {
      final todo = parseTodo('q #todo\n[ ] a\nsome prose\n[ ] b')!;
      expect(todo.items.map((item) => item.label), ['a', 'b']);
    });

    test('an empty item is not an item', () {
      expect(parseTodo('q #todo\n[ ]   \n[ ] real')!.items.map((i) => i.label), ['real']);
    });

    test('a marker with no items is not a list', () {
      expect(parseTodo('just talking about #todo lists'), isNull);
    });

    test('no marker is not a list', () {
      expect(parseTodo('[ ] not a list without the tag'), isNull);
    });

    test('a marker inside code does not start one', () {
      expect(parseTodo('`#todo`\n[ ] a'), isNull);
    });

    test('items before the marker are not items', () {
      final todo = parseTodo('[ ] before\nq #todo\n[ ] after')!;
      expect(todo.items.map((item) => item.label), ['after']);
    });
  });

  group('the body above the list', () {
    test('has the item lines stripped', () {
      expect(todoDisplayBody('shopping #todo\n[ ] bread\n[x] milk'), 'shopping #todo');
    });

    test('is untouched when there is no list', () {
      expect(todoDisplayBody('just a post'), 'just a post');
      expect(todoDisplayBody('about #todo lists'), 'about #todo lists');
    });

    test('keeps what came before the marker', () {
      expect(
        todoDisplayBody('a line\nand another\nlist #todo\n[ ] a'),
        'a line\nand another\nlist #todo',
      );
    });
  });

  group('toggling', () {
    test('ticks an unticked item', () {
      expect(toggleTodo('q #todo\n[ ] a\n[ ] b', 0), 'q #todo\n[x] a\n[ ] b');
    });

    test('unticks a ticked one', () {
      expect(toggleTodo('q #todo\n[x] a', 0), 'q #todo\n[ ] a');
    });

    test('touches only the item asked for', () {
      expect(toggleTodo('q #todo\n[ ] a\n[ ] b\n[ ] c', 1), 'q #todo\n[ ] a\n[x] b\n[ ] c');
    });

    test('leaves prose between items alone', () {
      expect(
        toggleTodo('q #todo\n[ ] a\nprose\n[ ] b', 1),
        'q #todo\n[ ] a\nprose\n[x] b',
      );
    });

    test('keeps the indentation it found', () {
      expect(toggleTodo('q #todo\n  [ ] a', 0), 'q #todo\n  [x] a');
    });

    test('an index that does not exist changes nothing', () {
      expect(toggleTodo('q #todo\n[ ] a', 5), isNull);
      expect(toggleTodo('q #todo\n[ ] a', -1), isNull);
      expect(toggleTodo('no list here', 0), isNull);
    });

    test('round-trips', () {
      const body = 'q #todo\n[ ] a\n[x] b';
      final once = toggleTodo(body, 0)!;
      expect(toggleTodo(once, 0), body);
    });
  });
}
