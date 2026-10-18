import 'package:carden/core/haptics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Haptics stay gentle and few (owner, 2026-10-18; docs/native-ui.md, "Haptics"): never two
/// within 70 ms, at most 10 a second, a run of ticks is a handful whatever the board's size, a
/// success always plays, nothing with Settings > Haptics off or on the web.
void main() {
  Duration ms(int v) => Duration(milliseconds: v);

  group('planTicks', () {
    test('keeps ticks at least 70 ms apart, in order', () {
      final plan = Haptics.planTicks([ms(0), ms(10), ms(50), ms(80), ms(100), ms(160), ms(150)]);
      expect(plan, [ms(0), ms(80), ms(150)]);
    });

    test('a giant deal (300 cards leaving within half a second) is a handful of ticks', () {
      final leave = [for (var i = 0; i < 300; i++) ms(i * 470 ~/ 300)];
      final plan = Haptics.planTicks(leave);
      expect(plan.length, HapticRun.maxTicks);
      for (var i = 1; i < plan.length; i++) {
        expect(plan[i] - plan[i - 1], greaterThanOrEqualTo(HapticRun.tickGap));
      }
      expect(plan.first, Duration.zero, reason: 'from the first card');
      expect(plan.last, greaterThan(ms(400)), reason: 'spread over the whole sweep, not bunched at its start');
    });

    test('nothing to play', () {
      expect(Haptics.planTicks(const []), isEmpty);
      expect(Haptics.planTicks([ms(0), ms(100)], max: 0), isEmpty);
      expect(Haptics.planTicks([ms(0), ms(100), ms(200)], max: 1), [ms(0)]);
    });
  });

  group('HapticGate', () {
    test('never two within 70 ms', () {
      final gate = HapticGate();
      final t0 = DateTime(2026, 10, 18);
      expect(gate.allow(t0), isTrue);
      expect(gate.allow(t0.add(ms(30))), isFalse);
      expect(gate.allow(t0.add(ms(69))), isFalse);
      expect(gate.allow(t0.add(ms(70))), isTrue);
    });

    test('at most 10 in any second, then free again', () {
      final gate = HapticGate();
      final t0 = DateTime(2026, 10, 18);
      var played = 0;
      // A storm: a touch asked for every 16 ms (each frame) for a second.
      for (var i = 0; i < 63; i++) {
        if (gate.allow(t0.add(ms(i * 16)))) played++;
      }
      expect(played, lessThanOrEqualTo(10));
      expect(played, greaterThanOrEqualTo(8), reason: 'still a steady few');
      expect(gate.allow(t0.add(ms(2100))), isTrue, reason: 'a moment later it plays again');
    });
  });

  group('Haptics', () {
    final played = <HapticKind>[];
    var clock = DateTime(2026, 10, 18);

    setUp(() {
      played.clear();
      clock = DateTime(2026, 10, 18);
      Haptics.gate.reset();
      Haptics.enabled = true;
      Haptics.debugWeb = false;
      Haptics.debugSink = played.add;
      Haptics.now = () => clock;
    });

    tearDown(() {
      Haptics.debugSink = null;
      Haptics.now = DateTime.now;
      Haptics.debugWeb = false;
      Haptics.enabled = true;
      Haptics.gate.reset();
    });

    test('gentle kinds only, through the gate; a success always plays', () {
      Haptics.light();
      Haptics.selection(); // same moment: dropped
      Haptics.success(); // never dropped
      clock = clock.add(ms(80));
      Haptics.medium();
      expect(played, [HapticKind.light, HapticKind.success, HapticKind.medium]);
    });

    test('off in Settings, and on the web: nothing', () {
      Haptics.enabled = false;
      Haptics.light();
      Haptics.success();
      Haptics.enabled = true;
      Haptics.debugWeb = true;
      Haptics.light();
      Haptics.success();
      expect(played, isEmpty);
    });

    testWidgets('a run: its ticks, then the landing; a cancelled run stops', (tester) async {
      // The test's own clock, which moves as its timers fire.
      Haptics.now = () => tester.binding.clock.now();
      Future<void> wait(int v) => tester.pump(ms(v));

      // A deal on a giant board: 300 cards leaving, then one light touch as they land.
      Haptics.run([for (var i = 0; i < 300; i++) ms(i * 470 ~/ 300)], lastAt: ms(990));
      for (var i = 0; i < 70; i++) {
        await wait(16);
      }
      expect(played.where((k) => k == HapticKind.selection).length, HapticRun.maxTicks);
      expect(played.last, HapticKind.light, reason: 'the cards land');
      expect(played.length, HapticRun.maxTicks + 1);

      played.clear();
      final run = Haptics.run([ms(0), ms(90), ms(180)], lastAt: ms(280));
      await wait(100);
      run.cancel();
      await wait(400);
      expect(played.length, 2, reason: 'the ticks after the cancel never play');
    });
  });
}
