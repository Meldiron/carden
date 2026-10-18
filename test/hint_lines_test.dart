// Every hint and tip card, and every locked card, on the owner's iPhone (390 pt wide) at the default
// text size (owner, TestFlight 2026-10-18: "3 lines of text, that's too much"): a hint or tip fits 2
// lines; a locked card's title and its line say one line each. The real widgets are pumped, and each
// line is laid out again at the width its widget gives it.
//
// The iPhone's own font (San Francisco) is measured where it can be found (on a Mac); elsewhere (CI on
// Linux) Roboto from the Flutter SDK. Each is given a share of the width that makes the copy the owner
// reported come out at the line counts his iPhone showed (the calibration test), so a line that only
// just fits here never breaks on the phone. At Large and Largest the cards wrap more, never overflow.
import 'dart:io';

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/events/events_screen.dart';
import 'package:carden/features/game/game_screen.dart';
import 'package:carden/features/home/guided_start.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _phone = Size(390, 844);

const _family = 'PhoneFont';

/// The app's dark theme with every text in [_family], as every text on the iPhone is in its system font.
ThemeData _theme() {
  final t = AppTheme.dark();
  return t.copyWith(textTheme: t.textTheme.apply(fontFamily: _family));
}

/// The font the lines are measured in, and the share of each width the text may fill with it.
late final double _margin;

/// The Flutter SDK the test runs from (its Roboto is on every machine with Flutter).
String _flutterRoot() {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  final exe = Platform.resolvedExecutable;
  final at = exe.indexOf('/bin/cache/');
  return at < 0 ? exe : exe.substring(0, at);
}

Future<void> _loadFont() async {
  const sf = '/System/Library/Fonts/SFNS.ttf';
  final File font;
  if (File(sf).existsSync()) {
    font = File(sf);
    _margin = 0.96;
  } else {
    font = File('${_flutterRoot()}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf');
    _margin = 0.92;
  }
  // The app names no family (the platform's font); the test theme names this one (_theme).
  final loader = FontLoader(_family)..addFont(Future.value(ByteData.sublistView(font.readAsBytesSync())));
  await loader.load();
}

/// How many lines [text] (default: the paragraph's own) takes at the width the paragraph of [like] is given.
int _lines(WidgetTester tester, Finder like, {String? text}) {
  final p = tester.renderObject<RenderParagraph>(like);
  final span = p.text as TextSpan;
  final painter = TextPainter(
    text: text == null ? span : TextSpan(text: text, style: span.style),
    textDirection: TextDirection.ltr,
    textScaler: p.textScaler,
  )..layout(maxWidth: p.constraints.maxWidth * _margin);
  final n = painter.computeLineMetrics().length;
  painter.dispose();
  return n;
}

/// The one Text inside [widget].
Finder _textIn(Finder widget) => find.descendant(of: widget, matching: find.byType(Text)).first;

Future<void> _pump(WidgetTester tester, Widget child, {double scale = 1, List<Override> overrides = const []}) async {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({'firstSteps': '{"guided":true}'});
  final store = await LocalStore.open();
  await tester.pumpWidget(ProviderScope(
    overrides: [localStoreProvider.overrideWithValue(store), countedSolvesProvider.overrideWithValue(0), ...overrides],
    child: MediaQuery(
      data: MediaQueryData(size: _phone, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(theme: _theme(), home: Scaffold(body: SingleChildScrollView(child: child))),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 600));
}

/// A tip as the Library and the board picker show it: 20 pt from the screen's edges.
Widget _tip(String text) => OneTimeTip(id: 'test', icon: AppIcons.library, text: text, padding: const EdgeInsets.symmetric(horizontal: 20));

/// A locked card as Profile and Quests show it: 20 pt from the screen's edges.
Widget _locked(Reveal r) => Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: LockedSectionCard(reveal: r));

/// The first board's hint, at the bottom of the game screen.
Widget _coach(CoachStep s) => Align(alignment: Alignment.bottomCenter, child: BoardCoach(step: s, onClose: () {}));

void main() {
  setUpAll(_loadFont);

  testWidgets('calibration: the copy the owner reported comes out at the line counts his iPhone showed', (tester) async {
    await _pump(tester, Column(children: [_tip(OneTimeTip.libraryText), _coach(CoachStep.locked), _locked(Reveal.achievements)]));
    final tip = _textIn(find.byType(OneTimeTip));
    expect(_lines(tester, tip, text: 'Start with the free packs. The others open with coins or tickets, and every picture earns coins.'), 3);
    expect(_lines(tester, tip, text: 'Pick a shape and a size. Bigger boards take longer and pay more coins and XP.'), 3);
    expect(_lines(tester, _textIn(find.byType(BoardCoach)), text: 'It locked in place. Cards that belong side by side also join and move together.'), 3);
    final title = find.text(Reveal.achievements.opensAfter(0));
    expect(_lines(tester, title, text: 'Achievements open after 24 more pictures'), 2);
    expect(_lines(tester, find.text(Reveal.achievements.blurb), text: 'Goals across all your play, each with a reward.'), 2);
  });

  group('hints and tips: two lines at most', () {
    for (final step in CoachStep.values) {
      testWidgets('first board, ${step.name}: ${BoardCoach.lineFor(step)}', (tester) async {
        await _pump(tester, _coach(step));
        expect(_lines(tester, find.text(BoardCoach.lineFor(step))), lessThanOrEqualTo(2));
      });
    }
    for (final text in [OneTimeTip.libraryText, OneTimeTip.boardText]) {
      testWidgets('tip: $text', (tester) async {
        await _pump(tester, _tip(text));
        expect(_lines(tester, find.text(text)), lessThanOrEqualTo(2));
      });
    }
    testWidgets('Quests: how a quest is swapped', (tester) async {
      await _pump(tester, const QuestSwipeHint());
      expect(_lines(tester, _textIn(find.byType(QuestSwipeHint))), lessThanOrEqualTo(2));
    });
  });

  group('locked cards: a one-line title and a one-line description', () {
    for (final r in [Reveal.achievements, Reveal.liveEvents]) {
      testWidgets('${r.label} (Profile, Quests)', (tester) async {
        // No pictures yet: the largest count there is.
        await _pump(tester, _locked(r));
        expect(_lines(tester, find.text(r.opensAfter(0))), 1);
        expect(_lines(tester, find.text(r.blurb)), 1);
      });
    }

    // Home's list of what is to come shows four at a time.
    final listed = [for (final r in Reveal.values) if (r.listed) r];
    for (var i = 0; i < listed.length; i += 4) {
      final shown = listed.skip(i).take(4).toList();
      testWidgets('Home, More opens as you play: ${shown.map((r) => r.label).join(', ')}', (tester) async {
        await _pump(tester, const MoreToComeCard(preview: SizedBox(height: 400)), overrides: [upcomingRevealsProvider.overrideWithValue(shown)]);
        expect(_lines(tester, find.text('More opens as you play')), 1);
        expect(_lines(tester, find.text(MoreToComeCard.intro)), 1);
        for (final r in shown) {
          expect(_lines(tester, find.text(r.blurb)), 1, reason: r.blurb);
          // The name and its chip ("2 more pictures") share one line.
          final name = tester.getRect(find.text(r.label)), chip = tester.getRect(find.text(r.more(0)));
          expect((name.center.dy - chip.center.dy).abs(), lessThan(name.height / 2), reason: '${r.label} and its chip on one line');
        }
      });
    }
  });

  group('Large and Largest text: more lines, no overflow', () {
    for (final scale in const [1.5, 2.0]) {
      testWidgets('text ${scale}x', (tester) async {
        await _pump(
          tester,
          Column(children: [
            for (final s in CoachStep.values) _coach(s),
            _tip(OneTimeTip.libraryText),
            _tip(OneTimeTip.boardText),
            const QuestSwipeHint(),
            _locked(Reveal.achievements),
            _locked(Reveal.liveEvents),
            const MoreToComeCard(preview: SizedBox(height: 400)),
          ]),
          scale: scale,
          overrides: [upcomingRevealsProvider.overrideWithValue([for (final r in Reveal.values) if (r.listed) r])],
        );
        expect(tester.takeException(), isNull);
      });
    }
  });
}
