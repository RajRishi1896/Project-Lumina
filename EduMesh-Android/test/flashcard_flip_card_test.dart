import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:edumesh_android/core/models/flashcard_models.dart';
import 'package:edumesh_android/core/navigation/lumina_transitions.dart';
import 'package:edumesh_android/core/providers/animation_prefs.dart';
import 'package:edumesh_android/features/dashboard/presentation/flashcard_flip_card.dart';
import 'package:edumesh_android/l10n/app_localizations.dart';

FlashcardCard _card({String? front, String? back}) => FlashcardCard(
      id: 'c1',
      deckId: 'd1',
      front: front ?? 'What planet is known as the Red Planet?',
      back: back ?? 'Mars',
      ease: 2.5,
      intervalDays: 0,
      dueAt: 0,
    );

Widget _harness(
  WidgetTester tester,
  AnimationController controller, {
  FlashcardCard? card,
  bool disableAnimations = false,
}) {
  var harnessFlipped = false;
  return ScreenUtilInit(
    designSize: const Size(360, 800),
    minTextAdapt: true,
    splitScreenMode: true,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Builder(
          builder: (context) => Scaffold(
            body: FlashcardFlipCard(
              flipController: controller,
              subject: 'Biology 101',
              card: card ?? _card(),
              onFlip: () {
                // Same gate the study page uses: global setting + reduced
                // motion.
                final animate = LuminaTransitions.enabled(context);
                harnessFlipped = !harnessFlipped;
                final target = harnessFlipped ? 1.0 : 0.0;
                if (!animate) {
                  controller.value = target;
                } else {
                  controller.animateTo(target, curve: Curves.easeOut);
                }
              },
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AnimationPrefs().resetForTest();
  });

  testWidgets('flip is instant when the global setting is OFF', (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller));

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pump(); // single frame

    expect(AnimationPrefs().enabled, false);
    expect(controller.value, 1.0);
    expect(find.text('Mars'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('flip animates when the global setting is ON', (tester) async {
    SharedPreferences.setMockInitialValues({AnimationPrefs.prefKey: true});
    await AnimationPrefs().load();
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller));

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(controller.value, greaterThan(0.0));
    expect(controller.value, lessThan(1.0));
    await tester.pumpAndSettle();
    expect(controller.value, 1.0);
    expect(find.text('Mars'), findsOneWidget);
    controller.dispose();
  });
  testWidgets('flip reveals the answer side with front content hidden',
      (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller));

    expect(find.text('What planet is known as the Red Planet?'), findsOneWidget);
    expect(find.text('Mars'), findsNothing);

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pumpAndSettle();

    expect(find.text('Mars'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('What planet is known as the Red Planet?'), findsNothing);

    // Flip back restores the question side.
    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pumpAndSettle();
    expect(find.text('What planet is known as the Red Planet?'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('rapid taps never corrupt state or throw', (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller));

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byType(FlashcardFlipCard), warnIfMissed: false);
    }
    await tester.pumpAndSettle();

    // Even number of taps returns to the front; controller settled at 0.
    expect(controller.value, 0.0);
    expect(tester.takeException(), isNull);
    controller.dispose();
  });

  testWidgets('long educational text wraps without truncation or overflow',
      (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    final longCard = _card(
      front:
          'Explain in detail how the process of cellular respiration converts biochemical energy from nutrients into adenosine triphosphate, and why this matters for muscle function during long-distance running.',
      back:
          'Cellular respiration is a set of metabolic reactions that take place in the cells of organisms to convert biochemical energy from nutrients into adenosine triphosphate, and then release waste products. During long-distance running the muscles rely on this aerobic pathway for sustained energy output.',
    );
    await tester.pumpWidget(_harness(tester, controller, card: longCard));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('adenosine triphosphate'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('renders without exceptions at all eight target sizes',
      (tester) async {
    final sizes = [
      const Size(360, 640), // phone portrait
      const Size(430, 900), // large phone portrait
      const Size(640, 360), // phone landscape
      const Size(900, 430), // large phone landscape
      const Size(800, 1280), // tablet portrait
      const Size(1280, 1920), // large tablet portrait
      const Size(1280, 800), // tablet landscape
      const Size(1920, 1280), // large tablet landscape
    ];
    for (final size in sizes) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final controller =
          AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
      await tester.pumpWidget(_harness(tester, controller));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'front at $size');

      await tester.tap(find.byType(FlashcardFlipCard), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'back at $size');
      controller.dispose();
    }
  });

  testWidgets('semantics describe the current side and the flip action',
      (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_harness(tester, controller));

    // Front side: question text with flip hint in the label.
    expect(
      find.bySemanticsLabel(
          RegExp(r'^Front: What planet is known as the Red Planet\?')),
      findsOneWidget,
    );

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pumpAndSettle();

    // Back side: answer text.
    expect(find.bySemanticsLabel(RegExp(r'^Answer: Mars')), findsOneWidget);
    semantics.dispose();
    controller.dispose();
  });

  testWidgets('reduced motion swaps sides instantly', (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller, disableAnimations: true));

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pump(); // Single frame: no settle, so any animation would show.

    expect(controller.value, 1.0);
    expect(find.text('Mars'), findsOneWidget);
    controller.dispose();
  });

  testWidgets('disposing the page mid-animation does not tick a disposed controller',
      (tester) async {
    final controller = AnimationController(vsync: tester, duration: const Duration(milliseconds: 160));
    await tester.pumpWidget(_harness(tester, controller));

    await tester.tap(find.byType(FlashcardFlipCard));
    await tester.pump(const Duration(milliseconds: 40)); // Mid-flight.

    // Unmount the tree; the state must dispose the controller. A later frame
    // would throw "used after being disposed" if it leaked.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 200));
    expect(tester.takeException(), isNull);
  });
}
