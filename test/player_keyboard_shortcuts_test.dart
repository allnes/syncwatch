import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:syncwatch/widgets/player_keyboard_shortcuts.dart';

void main() {
  testWidgets('Space pauses once without activating the focused back button', (
    tester,
  ) async {
    final playerFocus = FocusNode();
    final buttonFocus = FocusNode();
    addTearDown(playerFocus.dispose);
    addTearDown(buttonFocus.dispose);
    var commands = 0;
    var activations = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerKeyboardShortcuts(
          focusNode: playerFocus,
          onKeyEvent: (_) => commands++,
          child: TextButton(
            focusNode: buttonFocus,
            onPressed: () => activations++,
            child: const Text('Back'),
          ),
        ),
      ),
    );
    buttonFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(commands, 1);
    expect(activations, 0);
    // Enter remains available for intentional keyboard button activation.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(activations, 1);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'another focused route keeps text input and disposal removes handler',
    (tester) async {
      final playerFocus = FocusNode();
      final inputFocus = FocusNode();
      addTearDown(playerFocus.dispose);
      addTearDown(inputFocus.dispose);
      var commands = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Column(
              children: [
                PlayerKeyboardShortcuts(
                  focusNode: playerFocus,
                  onKeyEvent: (_) => commands++,
                  child: const Text('Player'),
                ),
                TextField(focusNode: inputFocus),
              ],
            ),
          ),
        ),
      );
      inputFocus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(commands, 0);
      await tester.pumpWidget(
        const MaterialApp(home: Material(child: TextField(autofocus: true))),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(commands, 0);
    },
  );
}
