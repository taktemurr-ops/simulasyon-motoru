import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simulasyon_motoru/simulasyon_motoru.dart';
import 'package:studio_core/app/game_api.dart';
import 'package:studio_core/core/game_rules.dart';
import 'package:studio_core/core/level_plan.dart';

PlayContext fakeCtx(GeneratedLevel gl, String lang, List<RoundResult> results) => PlayContext(
      spec: gl.spec,
      generated: gl,
      resume: const {},
      pieceColors: const [Color(0xFF3E6FB0), Color(0xFFC8553D), Color(0xFF4F9A6E)],
      background: const [Color(0xFF203040), Color(0xFF304050)],
      colorBlind: false,
      reducedMotion: false,
      leftHanded: false,
      lang: lang,
      t: (k, [p = const {}]) => k,
      finish: results.add,
      saveResume: (_) {},
      requestHint: () async => true,
      requestBooster: () async => true,
      requestContinue: () async => false,
      sfx: (_) {},
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final e in kSimKinds.entries) {
    for (final lang in const ['tr', 'en', 'ar']) {
      testWidgets('${e.key} ($lang): ekran açılır, dokunuşlara dayanır', (tester) async {
        tester.view.physicalSize = const Size(1080, 2280);
        tester.view.devicePixelRatio = 2.75;
        addTearDown(tester.view.reset);
        final rules = simRulesFor('oyun-test-${e.key}', e.key);
        final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
        final gl = rules.build(planner.spec(5));
        final results = <RoundResult>[];
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SafeArea(child: SimStage(ctx: fakeCtx(gl, lang, results), rules: rules))),
        ));
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        final size = tester.view.physicalSize / tester.view.devicePixelRatio;
        for (var y = 60.0; y < size.height - 10; y += size.height / 9) {
          for (var x = 20.0; x < size.width; x += size.width / 6) {
            await tester.tapAt(Offset(x, y));
            await tester.pump(const Duration(milliseconds: 120));
          }
        }
        await tester.dragFrom(Offset(size.width * 0.3, size.height * 0.4), Offset(size.width * 0.3, size.height * 0.1));
        await tester.pump(const Duration(seconds: 2));
        expect(tester.takeException(), isNull);
        // Fotoğraf modunu aç, süs ekle, kapat.
        final cam = find.byIcon(Icons.photo_camera_outlined);
        if (cam.evaluate().isNotEmpty) {
          await tester.tap(cam.first);
          await tester.pump(const Duration(milliseconds: 200));
          await tester.tapAt(Offset(size.width / 2, size.height / 2));
          await tester.pump(const Duration(milliseconds: 200));
          final close = find.byIcon(Icons.close);
          if (close.evaluate().isNotEmpty) await tester.tap(close.first);
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 3));
      });
    }
  }
}
