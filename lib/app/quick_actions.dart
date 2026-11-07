import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

import '../features/library/application/library_controller.dart';
import 'router.dart';

/// The shortcuts shown when you long-press the app icon.
enum QuickAction {
  continueReading('continue', 'Continue reading', 'ic_launcher'),
  addTask('add_task', 'Add a task', 'ic_launcher'),
  today('today', 'Planner: today', 'ic_launcher'),
  library('library', 'Library', 'ic_launcher');

  const QuickAction(this.type, this.label, this.icon);
  final String type, label, icon;
  static QuickAction? of(String type) =>
      values.where((a) => a.type == type).firstOrNull;
}

/// The phone side of shortcuts. An interface so tests need no native plugin.
abstract class QuickActionsPort {
  /// Registers the shortcuts and calls [onAction] with the type of the one that was tapped.
  void start(List<QuickAction> items, void Function(String type) onAction);
}

class PluginQuickActions implements QuickActionsPort {
  @override
  void start(List<QuickAction> items, void Function(String type) onAction) {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      const qa = QuickActions();
      qa.initialize(onAction);
      qa.setShortcutItems([
        for (final a in items)
          ShortcutItem(type: a.type, localizedTitle: a.label, icon: a.icon),
      ]);
    } catch (_) {
      // shortcuts are a convenience; never stop the app for them
    }
  }
}

final quickActionsProvider = Provider<QuickActionsPort>(
  (ref) => PluginQuickActions(),
);

/// Bumped when "Add a task" is chosen: Home focuses its quick-add box.
class FocusQuickAdd extends Notifier<int> {
  @override
  int build() => 0;
  void request() => state++;
}

final focusQuickAddProvider = NotifierProvider<FocusQuickAdd, int>(
  FocusQuickAdd.new,
);

/// Does what a tapped shortcut asks.
void handleQuickAction(WidgetRef ref, String type) {
  final router = ref.read(routerProvider);
  switch (QuickAction.of(type)) {
    case QuickAction.continueReading:
      final books = ref.read(booksProvider).value ?? const [];
      final recent = recentBooks(books, limit: 1);
      if (recent.isEmpty) {
        router.go(Routes.library);
      } else {
        router.go(Routes.library);
        router.push('${Routes.library}/read/${recent.first.id}');
      }
    case QuickAction.addTask:
      router.go(Routes.home);
      ref.read(focusQuickAddProvider.notifier).request();
    case QuickAction.today:
      router.go(Routes.planner);
    case QuickAction.library:
      router.go(Routes.library);
    case null:
      break;
  }
}
