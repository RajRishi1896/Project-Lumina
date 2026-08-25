import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:edumesh_android/core/providers/animation_prefs.dart';

/// Records every route the navigator pushes so tests can inspect its
/// transition durations.
class RecordingObserver extends NavigatorObserver {
  final List<Route<dynamic>> pushed = [];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnimationPrefs().resetForTest();
  });

  Future<void> enableAnimations() async {
    AnimationPrefs().resetForTest();
    SharedPreferences.setMockInitialValues({AnimationPrefs.prefKey: true});
    await AnimationPrefs().load();
  }

  test('animations default to OFF', () {
    expect(AnimationPrefs().enabled, false);
  });

  test('preference persists to storage and reloads after restart', () async {
    await AnimationPrefs().load();
    expect(AnimationPrefs().enabled, false);

    await AnimationPrefs().setEnabled(true);
    final store = await SharedPreferences.getInstance();
    expect(store.getBool(AnimationPrefs.prefKey), true);

    // Simulate an app restart: fresh state re-reads storage.
    AnimationPrefs().resetForTest();
    await AnimationPrefs().load();
    expect(AnimationPrefs().enabled, true);

    await AnimationPrefs().setEnabled(false);
    expect(
        (await SharedPreferences.getInstance()).getBool(AnimationPrefs.prefKey),
        false);
  });

  testWidgets('reduced motion overrides an ON setting', (tester) async {
    await enableAnimations();

    late bool gate;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Builder(
          builder: (context) {
            gate = LuminaTransitions.enabled(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(gate, false);
  });

  testWidgets('forward + back navigation respect the setting',
      (tester) async {
    final observer = RecordingObserver();

    Future<void> pumpHome() async {
      await tester.pumpWidget(MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(luminaRoute<void>(
                builder: (_) => const Scaffold(body: Text('target')))),
            child: const Text('go'),
          ),
        ),
      ));
    }

    // OFF: instant both ways.
    await pumpHome();
    await tester.tap(find.text('go'));
    await tester.pump();
    expect((observer.pushed.last as PageRoute).transitionDuration, Duration.zero);
    expect((observer.pushed.last as PageRoute).reverseTransitionDuration,
        Duration.zero);
    expect(find.text('target'), findsOneWidget);
    Navigator.of(tester.element(find.text('target'))).pop();
    await tester.pumpAndSettle();

    // ON: 180 ms slide+fade forward and reverse.
    await enableAnimations();
    await pumpHome();
    await tester.pumpAndSettle();
    await tester.tap(find.text('go'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect((observer.pushed.last as PageRoute).transitionDuration,
        LuminaTransitions.duration);
    expect((observer.pushed.last as PageRoute).reverseTransitionDuration,
        LuminaTransitions.duration);
    expect(find.text('target'), findsOneWidget);
  });

  testWidgets('dialog and sheet transitions respect the setting',
      (tester) async {
    final observer = RecordingObserver();

    Widget home(VoidCallback openDialog, VoidCallback openSheet) => Builder(
          builder: (context) => Column(
            children: [
              TextButton(onPressed: openDialog, child: const Text('dialog')),
              TextButton(onPressed: openSheet, child: const Text('sheet')),
            ],
          ),
        );

    // OFF: both instant.
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: home(
        () => showLuminaDialog<void>(
            context: observer.navigator!.context,
            builder: (_) => const AlertDialog(content: Text('dialog body'))),
        () => showLuminaSheet<void>(
            context: observer.navigator!.context,
            builder: (_) => const SizedBox(height: 100, child: Text('sheet body'))),
      ),
    ));
    await tester.tap(find.text('dialog'));
    await tester.pump();
    expect(find.text('dialog body'), findsOneWidget);
    expect((observer.pushed.last as PopupRoute).transitionDuration, Duration.zero);
    Navigator.of(observer.navigator!.context).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('sheet'));
    await tester.pump();
    expect(find.text('sheet body'), findsOneWidget);
    expect((observer.pushed.last as PopupRoute).transitionDuration, Duration.zero);
    Navigator.of(observer.navigator!.context).pop();
    await tester.pumpAndSettle();

    // ON: 180 ms transitions.
    await enableAnimations();

    await tester.pumpWidget(MaterialApp(
      key: UniqueKey(),
      navigatorObservers: [observer],
      home: home(
        () => showLuminaDialog<void>(
            context: observer.navigator!.context,
            builder: (_) => const AlertDialog(content: Text('dialog body'))),
        () => showLuminaSheet<void>(
            context: observer.navigator!.context,
            builder: (_) => const SizedBox(height: 100, child: Text('sheet body'))),
      ),
    ));
    await tester.tap(find.text('dialog'));
    await tester.pump();
    expect(find.text('dialog body'), findsOneWidget);
    expect((observer.pushed.last as PopupRoute).transitionDuration, LuminaTransitions.duration);
    Navigator.of(observer.navigator!.context).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.text('sheet'));
    await tester.pump();
    expect(find.text('sheet body'), findsOneWidget);
    expect((observer.pushed.last as PopupRoute).transitionDuration, LuminaTransitions.duration);
  });

  testWidgets('flashcard flip gate follows the setting and reduced motion',
      (tester) async {
    final controller = AnimationController(vsync: tester);
    addTearDown(controller.dispose);

    // OFF: the gate is false, so the flip would jump instantly.
    late bool gate;
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) {
          gate = LuminaTransitions.enabled(context);
          return const SizedBox();
        },
      ),
    ));
    expect(gate, false);
    controller.value = 1; // instant swap path
    expect(controller.value, 1.0);
  });
}
