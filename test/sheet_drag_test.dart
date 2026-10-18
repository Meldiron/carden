// Sheets behave like iOS sheets (owner, 2026-10-18; lib/widgets/sheets.dart, docs/native-ui.md
// "Sheets"): a drag down at the top of the content closes them, a drag lower in the content
// scrolls first, the grabber drags too, a fast flick closes, no sheet reaches the status bar (a tap
// on the strip above closes it), footer buttons stay pinned, and the full-height sheets (Store,
// Wheel, Account) close the same way.
import 'package:carden/core/a11y.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/glass.dart';
import 'package:carden/widgets/sheets.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _phone = Size(390, 844); // iPhone 13 Pro, the owner's phone
const _statusBar = 47.0;
const _homeIndicator = 34.0;

void _phoneView(WidgetTester tester) {
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: _statusBar, bottom: _homeIndicator);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar, bottom: _homeIndicator);
  addTearDown(tester.view.reset);
}

Widget _rows(int n) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (var i = 0; i < n; i++) SizedBox(height: 48, child: Text('Row $i'))],
    );

/// Pumps a page with an Open button and opens a sheet built by [builder]; returns what the sheet
/// gave back once it closed (through [result]).
Future<List<Object?>> _open(WidgetTester tester, WidgetBuilder builder, {bool scrollable = false, bool dismissible = true, bool reduceMotion = false}) async {
  _phoneView(tester);
  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light(),
    builder: (context, child) => A11y(prefs: Accessibility(reduceMotion: reduceMotion), child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () async => results.add(await showAppSheet<Object>(context, scrollable: scrollable, dismissible: dismissible, builder: builder)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
  return results;
}

ScrollPosition _sheetScroll(WidgetTester tester) =>
    tester.state<ScrollableState>(find.descendant(of: find.byKey(SheetScrollBody.scrollKey), matching: find.byType(Scrollable)).first).position;

Rect _sheet(WidgetTester tester) => tester.getRect(find.byType(GlassSheet));

void main() {
  testWidgets('no sheet reaches the status bar: it stops at the top gap, and a tap above closes it', (tester) async {
    await _open(tester, (_) => _rows(60));
    final top = _sheet(tester).top;
    expect(top, closeTo(_phone.height * SheetMetrics.topGapRatio, 0.5));
    expect(top - _statusBar, greaterThan(16), reason: 'a strip of the page stays in view under the status bar');
    expect(_sheet(tester).bottom, _phone.height);
    await tester.tapAt(Offset(_phone.width / 2, top - 8));
    await tester.pumpAndSettle();
    expect(find.text('Row 0'), findsNothing);
  });

  testWidgets('a drag down at the top of the content closes the sheet', (tester) async {
    await _open(tester, (_) => _rows(60));
    expect(_sheetScroll(tester).pixels, 0);
    await tester.drag(find.text('Row 2'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Row 2'), findsNothing);
  });

  testWidgets('the sheet follows the finger instead of pulling the content past its top', (tester) async {
    await _open(tester, (_) => _rows(60));
    final top = _sheet(tester).top;
    final rowTop = tester.getRect(find.text('Row 0')).top;
    final gesture = await tester.startGesture(tester.getCenter(find.text('Row 2')));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // The whole sheet moved down; the content did not move inside it (no empty band over the title).
    final moved = _sheet(tester).top - top;
    expect(moved, greaterThan(60));
    expect(tester.getRect(find.text('Row 0')).top - rowTop, closeTo(moved, 1));
    expect(_sheetScroll(tester).pixels, 0);
    // Let go slowly after a short pull: it settles back open.
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(_sheet(tester).top, closeTo(top, 0.5));
    expect(find.text('Row 0'), findsOneWidget);
  });

  testWidgets('a drag down lower in the content scrolls it up first, then the same pull closes the sheet', (tester) async {
    await _open(tester, (_) => _rows(60));
    final top = _sheet(tester).top;
    await tester.timedDrag(find.text('Row 8'), const Offset(0, -600), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    final scrolled = _sheetScroll(tester).pixels;
    expect(scrolled, greaterThan(400));

    // Down by less than the scroll: only the content moves.
    await tester.timedDrag(find.byKey(SheetScrollBody.scrollKey), const Offset(0, 200), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(_sheetScroll(tester).pixels, lessThan(scrolled - 150));
    expect(_sheetScroll(tester).pixels, greaterThan(0));
    expect(_sheet(tester).top, closeTo(top, 0.5), reason: 'the sheet stays open while the content scrolls');

    // One long pull: the content reaches its top, then the sheet goes down and closes.
    await tester.timedDrag(find.byKey(SheetScrollBody.scrollKey), Offset(0, _sheetScroll(tester).pixels + 320), const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsNothing);
  });

  testWidgets('a fast flick down at the top closes it, a short slow pull does not', (tester) async {
    await _open(tester, (_) => _rows(60));
    await tester.timedDrag(find.text('Row 2'), const Offset(0, 90), const Duration(milliseconds: 900));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsOneWidget);
    await tester.fling(find.text('Row 2'), const Offset(0, 90), 1500);
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsNothing);
  });

  testWidgets('the grabber drags the sheet, and a short sheet drags from anywhere', (tester) async {
    await _open(tester, (_) => _rows(60));
    await tester.drag(find.byKey(const ValueKey('sheet-grabber')), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsNothing);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsOneWidget);
    Navigator.of(tester.element(find.byType(GlassSheet))).pop();
    await tester.pumpAndSettle();

    await _open(tester, (_) => const Padding(padding: EdgeInsets.all(20), child: Text('Short sheet')));
    expect(_sheet(tester).height, lessThan(200));
    await tester.drag(find.text('Short sheet'), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(find.text('Short sheet'), findsNothing);
  });

  testWidgets('a sheet that cannot be dismissed ignores drags and the dim', (tester) async {
    await _open(tester, (_) => _rows(60), dismissible: false);
    final top = _sheet(tester).top;
    await tester.drag(find.text('Row 2'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(_sheet(tester).top, closeTo(top, 0.5));
    await tester.tapAt(Offset(_phone.width / 2, top - 8));
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsOneWidget);
  });

  testWidgets('Reduce motion: the sheet fades, and a drag still closes it', (tester) async {
    await _open(tester, (_) => _rows(60), reduceMotion: true);
    expect(_sheet(tester).top, closeTo(_phone.height * SheetMetrics.topGapRatio, 0.5));
    await tester.drag(find.text('Row 2'), const Offset(0, 400));
    await tester.pump();
    expect(find.byType(FadeTransition), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.byType(GlassSheet), findsNothing);
  });

  testWidgets('a footer stays pinned at the bottom while the list above it scrolls', (tester) async {
    final results = await _open(
      tester,
      (context) => SheetScrollBody(
        footer: Padding(
          padding: const EdgeInsets.all(20),
          child: TextButton(onPressed: () => Navigator.of(context).pop('picked'), child: const Text('Unlock anyway')),
        ),
        child: _rows(40),
      ),
      scrollable: true,
    );
    final footer = tester.getRect(find.text('Unlock anyway'));
    expect(footer.bottom, lessThan(_phone.height - _homeIndicator), reason: 'above the home indicator');
    expect(footer.bottom, greaterThan(_phone.height - _homeIndicator - 80), reason: 'at the bottom of the sheet');
    expect(tester.getRect(find.byKey(SheetScrollBody.scrollKey)).bottom, lessThanOrEqualTo(footer.top), reason: 'the list ends above it');
    await tester.timedDrag(find.text('Row 4'), const Offset(0, -500), const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(_sheetScroll(tester).pixels, greaterThan(300));
    expect(tester.getRect(find.text('Unlock anyway')), footer, reason: 'the footer did not move');
    await tester.tap(find.text('Unlock anyway'));
    await tester.pumpAndSettle();
    expect(results, ['picked']);
  });

  testWidgets('a scroll view inside the content closes the sheet from its top too', (tester) async {
    await _open(tester, (_) => SizedBox(height: 500, child: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 48, child: Text('Item $i'))])));
    await tester.drag(find.text('Item 2'), const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Item 2'), findsNothing);
  });

  group('full-height sheets (Store, Wheel, Account)', () {
    Future<void> openFull(WidgetTester tester, {bool reduceMotion = false}) async {
      _phoneView(tester);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Center(child: Text('Home')))),
        GoRoute(
          path: '/store',
          pageBuilder: (_, s) => SheetPage<void>(
            key: s.pageKey,
            child: Scaffold(body: ListView(children: [for (var i = 0; i < 40; i++) SizedBox(height: 60, child: Text('Offer $i'))])),
          ),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => A11y(prefs: Accessibility(reduceMotion: reduceMotion), child: child!),
      ));
      router.push('/store');
      await tester.pumpAndSettle();
      expect(find.text('Offer 0'), findsOneWidget);
    }

    testWidgets('the stacked sheet closes with a drag down at the top of its list', (tester) async {
      await openFull(tester);
      expect(ModalRoute.of(tester.element(find.text('Offer 0'))), isA<CupertinoSheetRoute<void>>());
      expect(tester.getRect(find.text('Offer 0')).top, greaterThan(_statusBar), reason: 'below the status bar');
      // A drag lower in a scrolled list scrolls first.
      await tester.timedDrag(find.text('Offer 3'), const Offset(0, -400), const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      await tester.timedDrag(find.text('Offer 8'), const Offset(0, 150), const Duration(milliseconds: 800));
      await tester.pumpAndSettle();
      expect(find.text('Offer 8'), findsOneWidget, reason: 'still open: the list scrolled');
      // A long fast pull: the list reaches its top, then the sheet goes.
      await tester.fling(find.text('Offer 8'), const Offset(0, 900), 2500);
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('the stacked sheet closes with a drag down when its list is at the top', (tester) async {
      await openFull(tester);
      await tester.drag(find.text('Offer 2'), const Offset(0, 600));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('a tap on the strip above the stacked sheet closes it', (tester) async {
      await openFull(tester);
      await tester.tapAt(const Offset(195, 30));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
    });

    testWidgets('with Reduce motion it fades in as a sheet, below the status bar, and drags closed', (tester) async {
      await openFull(tester, reduceMotion: true);
      expect(ModalRoute.of(tester.element(find.text('Offer 0'))), isA<GlassSheetRoute<void>>());
      expect(tester.getRect(find.byType(Scaffold).last).top, closeTo(_phone.height * SheetMetrics.topGapRatio, 0.5));
      await tester.drag(find.text('Offer 2'), const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsNothing);
    });
  });
}
