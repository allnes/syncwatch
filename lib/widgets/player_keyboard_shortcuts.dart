import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Player commands take priority over a focused control's Space activation.
/// Other routes and windows keep their own keyboard handling.
class PlayerKeyboardShortcuts extends StatefulWidget {
  const PlayerKeyboardShortcuts({
    super.key,
    required this.focusNode,
    required this.onKeyEvent,
    required this.child,
    this.enabled = true,
    this.fullscreen = false,
  });

  final FocusNode focusNode;
  final ValueChanged<KeyEvent> onKeyEvent;
  final Widget child;
  final bool enabled;
  final bool fullscreen;

  @override
  State<PlayerKeyboardShortcuts> createState() =>
      _PlayerKeyboardShortcutsState();
}

class _PlayerKeyboardShortcutsState extends State<PlayerKeyboardShortcuts> {
  @override
  void initState() {
    super.initState();
    FocusManager.instance.addEarlyKeyEventHandler(_handleKey);
  }

  KeyEventResult _handleKey(KeyEvent event) {
    if (!widget.enabled || !widget.focusNode.hasFocus) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final handled =
        const [
          LogicalKeyboardKey.arrowLeft,
          LogicalKeyboardKey.arrowRight,
          LogicalKeyboardKey.arrowUp,
          LogicalKeyboardKey.arrowDown,
          LogicalKeyboardKey.space,
          LogicalKeyboardKey.keyM,
          LogicalKeyboardKey.keyF,
        ].contains(key) ||
        (key == LogicalKeyboardKey.escape && widget.fullscreen);
    if (!handled) return KeyEventResult.ignored;
    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      widget.onKeyEvent(event);
    }
    return KeyEventResult.handled;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_handleKey);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      Focus(focusNode: widget.focusNode, autofocus: true, child: widget.child);
}
