import 'package:flutter_test/flutter_test.dart';
import 'package:studio_core/core/level_plan.dart';
import 'package:simulasyon_motoru/simulasyon_motoru.dart';

void main() {
  for (final e in kSimKinds.entries) {
    test('${e.key}: bölümler kurulur ve botla doğrulanır', () {
      final rules = simRulesFor('oyun-test-${e.key}', e.key);
      final planner = LevelPlanner(gameId: rules.gameId, optionalMechanics: const []);
      for (final n in const [1, 7, 40, 300, 5000, 99999]) {
        expect(rules.build(planner.spec(n)).validation.ok, isTrue, reason: '${e.key} $n');
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  }

  test('sayı biçimi', () {
    expect(fmtNum(12), '12');
    expect(fmtNum(1234), '1.23K');
    expect(fmtNum(12345678), '12.3M');
  });

  test('her metin 33 dilde', () {
    for (final e in kSimTexts.entries) {
      expect(e.value.length, 33, reason: e.key);
    }
  });
}
