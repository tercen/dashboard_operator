import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sci_http_client/error.dart';

import 'package:tercen_dashboard/src/app.dart';
import 'package:tercen_dashboard/src/session.dart';
import 'package:tercen_dashboard/src/theme.dart';
import 'package:tercen_dashboard/src/user_filters.dart';

import '../support/fake_data.dart';

/// Every screen, in both themes, on invented data (test/support), plus the
/// narrow layout with its drawer open, the "Not authorized" page, the
/// manager's shell, the Users table paged, truncated, with many or very
/// long tags, with its widest row, with a user's activity open and while
/// the activity loads, with the filter bar set to a window or to MAU and a
/// domain excluded, the Create user dialog filled in and refused, and the
/// Edit tags dialog with a tag added and a duplicate refused. The PNGs under test/goldens/ are what the Tercen colour
/// scheme looks like; update them with
/// `flutter test --update-goldens test/goldens`.
void main() {
  setUpAll(_loadFonts);

  const sections = [
    'Overview',
    'Usage',
    'Tasks',
    'Workers',
    'Users',
    'Storage',
    'GC',
    'Audit',
    'Settings',
  ];

  for (final (mode, name) in [
    (ThemeMode.dark, 'black'),
    (ThemeMode.light, 'white'),
  ]) {
    for (final section in sections) {
      testWidgets('$section, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession());
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text(section)));
        await tester.pumpAndSettle();

        // The capture shows the screen that was asked for, not a frame of
        // the rail still moving off Overview.
        _expectSelected(tester, sections.indexOf(section));
        await _expectGolden('${section.toLowerCase()}_$name.png');
        await _unmount(tester);
      });
    }

    // The Users table past one page: on page 2 of 3, scrolled down to the
    // pager, with its rows-per-page menu and first/last buttons.
    testWidgets('Users, many pages, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: ManyUsersData(120, total: 120, truncated: false));
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Users')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Next page'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Next page'));
      await tester.pumpAndSettle();

      expect(find.text('51–100 of 120'), findsOneWidget);
      expect(find.text('Rows per page:'), findsOneWidget);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_paged_$name.png');
      await _unmount(tester);
    });

    // A server that returned only part of the list says so above the table.
    testWidgets('Users, truncated, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: ManyUsersData(1000, total: 1840, truncated: true));
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Users')));
      await tester.pumpAndSettle();

      expect(
          find.text('Showing 1000 of 1840 users — the server returned only '
              'the first 1000'),
          findsOneWidget);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_truncated_$name.png');
      await _unmount(tester);
    });

    // A user with 30 tags, and one with a single 300-character tag: the
    // Tags cell stays bounded — two chips and "+N", each chip cut with an
    // ellipsis — and the table does not grow past the screen.
    for (final (state, tags) in [
      ('many', [for (var i = 1; i <= 30; i++) 'tag-$i']),
      ('long', [('very-long-tag-' * 22).substring(0, 300)]),
    ]) {
      testWidgets('Users, tags $state, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession(),
            data: TaggedUsersData(tags));
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text('Users')));
        await tester.pumpAndSettle();

        expect(find.text('tagged'), findsOneWidget);
        _expectSelected(tester, sections.indexOf('Users'));
        await _expectGolden('users_tags_${state}_$name.png');
        await _unmount(tester);
      });
    }

    // The widest row the fixtures allow, at 1280 px with the bundled fonts:
    // every role, a cut object name with "+9", a four-digit lower bound, a
    // four-digit count, two full tag chips and "+998". With the activity
    // columns it is wider than the card: the table scrolls, with its
    // scrollbar showing. The edge tests below measure it.
    testWidgets('Users, worst-case row, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: TaggedUsersData.worstCase());
      await _openUsers(tester);

      expect(find.text('+998'), findsOneWidget);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_worst_case_$name.png');
      await _unmount(tester);
    });

    // The activity columns open for ada: her last ten objects in her row —
    // links, a deleted workflow struck through, a file whose project is gone
    // as plain text — beside a lower-bound count, "none", and linus's
    // unknowns.
    testWidgets('Users, activity open, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession());
      await _openUsers(tester);
      await tester.tap(find.byKey(const Key('activity-toggle')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('activity-expanded')), findsOneWidget);
      expect(find.text('Panel 9 analysis'), findsOneWidget);
      expect(tester.takeException(), isNull);
      _expectSelected(tester, sections.indexOf('Users'));
      await _expectGolden('users_activity_open_$name.png');
      await _unmount(tester);
    });

    // The filter bar set: a chosen window, with its Days in window column,
    // and tercen.example excluded — admin's row gone and out of the count.
    // Then the MAU preset over the same exclusion, on the fixed clock:
    // ada and margaret were active, grace was not, and linus's activity
    // could not be counted, so the MAU reads 2 to 3.
    for (final (state, filters) in [
      (
        'window',
        const UserFilters(
            mode: WindowMode.custom,
            from: '2026-09-01',
            to: '2026-09-21',
            excluded: ['tercen.example']),
      ),
      (
        'mau',
        const UserFilters(mode: WindowMode.mau, excluded: ['tercen.example']),
      ),
    ]) {
      testWidgets('Users, filtered by $state, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession(),
            data: FilteredUsersData(filters));
        await _openUsers(tester);

        expect(find.text('admin@tercen.example'), findsNothing);
        expect(find.byKey(const Key('excluded-tercen.example')),
            findsOneWidget);
        expect(find.text('DAYS IN\nWINDOW'), findsOneWidget);
        expect(find.text('grace'), state == 'mau' ? findsNothing : findsOneWidget);
        expect(tester.takeException(), isNull);
        _expectSelected(tester, sections.indexOf('Users'));
        await _expectGolden('users_filtered_${state}_$name.png');
        await _unmount(tester);
      });
    }

    // While listUserActivity is still counting: the list is there, the
    // activity cells say so, and a line above the table explains.
    testWidgets('Users, activity loading, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          data: ActivityLoadingData(), settle: false);
      await tester.tap(find.descendant(
          of: find.byType(NavigationRail), matching: find.text('Users')));
      // The spinner never settles: step past the rail's transition instead.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('ada'), findsOneWidget);
      expect(find.byKey(const Key('activity-loading')), findsNWidgets(10));
      await _expectGolden('users_activity_loading_$name.png');
      await _unmount(tester);
    });

    // The Create user dialog, filled in with an invented user, and the same
    // dialog after the server refused it: the error shown, the input kept.
    for (final (state, data) in [
      ('filled', FakeDashboardData()),
      ('refused', _RefusingData()),
    ]) {
      testWidgets('Create user dialog, $state, $name theme', (tester) async {
        await _pumpApp(tester, mode, fakeAdminSession(), data: data);
        await tester.tap(find.descendant(
            of: find.byType(NavigationRail), matching: find.text('Users')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Create user'));
        await tester.pumpAndSettle();
        await tester.enterText(
            find.byKey(const Key('create-user-name')), 'new-user');
        await tester.enterText(find.byKey(const Key('create-user-email')),
            'new.user@example.test');
        await tester.enterText(
            find.byKey(const Key('create-user-password')), 'invented');
        if (state == 'refused') {
          await tester.tap(find.widgetWithText(FilledButton, 'Create'));
        }
        // The caret blinks; settle on a fixed frame without the focus.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('create-user-error')),
            state == 'refused' ? findsOneWidget : findsNothing);
        await _expectGolden('create_user_${state}_$name.png');
        await _unmount(tester);
      });
    }

    // ada's tags being edited: one added, then a duplicate typed and
    // refused, with the reason under the field.
    testWidgets('Edit tags dialog, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession());
      await _openUsers(tester);
      await tester.tap(find.byKey(const Key('edit-tags--user-ada')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byKey(const Key('edit-tags-field')), 'follow-up');
      await tester.tap(find.byKey(const Key('edit-tags-add')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('edit-tags-field')), 'pilot');
      await tester.tap(find.byKey(const Key('edit-tags-add')));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      expect(find.text('"pilot" is already a tag'), findsOneWidget);
      await _expectGolden('edit_tags_$name.png');
      await _unmount(tester);
    });

    testWidgets('narrow layout, drawer open, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeAdminSession(),
          size: const Size(390, 844));
      expect(find.byType(NavigationRail), findsNothing);
      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.byType(Drawer), findsOneWidget);
      await _expectGolden('narrow_drawer_$name.png');
      await _unmount(tester);
    });

    testWidgets('not authorized, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeSession('ada', const []));

      expect(find.text('Not authorized'), findsOneWidget);
      expect(find.byType(DashboardShell), findsNothing);
      await _expectGolden('not_authorized_$name.png');
      await _unmount(tester);
    });

    testWidgets('manager shell, $name theme', (tester) async {
      await _pumpApp(tester, mode, fakeSession('grace', const ['manager']));

      // A manager without admin gets the usage views only.
      final rail =
          tester.widget<NavigationRail>(find.byType(NavigationRail));
      expect(rail.destinations, hasLength(1));
      expect(find.text('Usage'), findsWidgets);
      _expectSelected(tester, 0);
      await _expectGolden('manager_$name.png');
      await _unmount(tester);
    });
  }

  // At 1280 px the worst-case row, activity columns included, is wider
  // than the card: nothing overflows, the table scrolls, and its
  // scrollbar shows.
  testWidgets('Users, worst-case row scrolls at 1280 px', (tester) async {
    await _pumpApp(tester, ThemeMode.light, fakeAdminSession(),
        data: TaggedUsersData.worstCase());
    await _openUsers(tester);

    expect(tester.takeException(), isNull);
    expect(tester.view.physicalSize.width, 1280);
    expect(_tableScroll(tester).maxScrollExtent, greaterThan(0));
    final scrollbar = tester.widget<Scrollbar>(find
        .ancestor(of: find.byType(DataTable), matching: find.byType(Scrollbar))
        .first);
    expect(scrollbar.thumbVisibility, isTrue);
    await _unmount(tester);
  });

  // The edge of the worst case: at 1728 px (a 16-inch laptop) with the
  // bundled fonts, the widest row the fixtures allow fits inside the card.
  // Nothing overflows, there is nothing to scroll to, and the "+N" chip
  // and the Edit tags button — the last things in the row — end inside
  // the card and the screen.
  testWidgets('Users, worst-case row fits at 1728 px', (tester) async {
    await _pumpApp(tester, ThemeMode.light, fakeAdminSession(),
        data: TaggedUsersData.worstCase(), size: const Size(1728, 800));
    await _openUsers(tester);

    expect(tester.takeException(), isNull);
    expect(tester.view.physicalSize.width, 1728);
    final card = tester.getRect(find.byType(PaginatedDataTable));
    expect(card.right, lessThanOrEqualTo(1728));
    expect(tester.getRect(find.byType(DataTable)).right,
        lessThanOrEqualTo(card.right));
    // The table's own width, before the card stretches it: at least 16 px
    // to spare, so the fit is not a matter of a fraction of a pixel.
    final table = tester.renderObject<RenderBox>(find.descendant(
        of: find.byType(DataTable), matching: find.byType(Table)));
    expect(table.getMaxIntrinsicWidth(double.infinity),
        lessThanOrEqualTo(card.width - 16));
    expect(_tableScroll(tester).maxScrollExtent, 0);

    final more = tester.getRect(find.byKey(const Key('tags-more')));
    expect(tester.widget<Text>(find.descendant(
            of: find.byKey(const Key('tags-more')),
            matching: find.byType(Text))).data,
        '+998');
    expect(more.right, lessThanOrEqualTo(card.right));
    expect(
        tester
            .getRect(find.byKey(const Key('edit-tags-north-user-worst-case')))
            .right,
        lessThanOrEqualTo(card.right));
    // Every text in the table, the "+N" labels and "≥1234" included, is
    // laid out whole: no text is cut by its cell. The long tags (W…) and
    // the long object name (M…) are cut on purpose, with an ellipsis.
    expect(find.text('≥1234'), findsOneWidget);
    for (final element in find
        .descendant(of: find.byType(DataTable), matching: find.byType(Text))
        .evaluate()) {
      final text = element.widget as Text;
      final paragraph = element.renderObject as RenderParagraph?;
      final label = text.data ?? '';
      if (paragraph == null ||
          label.startsWith('W') ||
          label.startsWith('MMM')) {
        continue;
      }
      expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      expect(paragraph.size.width,
          greaterThanOrEqualTo(paragraph.getMaxIntrinsicWidth(0) - 0.5),
          reason: label);
      expect(tester.getRect(find.byWidget(text)).right,
          lessThanOrEqualTo(card.right),
          reason: label);
    }
    await _unmount(tester);
  });

  // A row wider than the card — here a longer email than any fixture's —
  // is not cut off without a sign: the table scrolls, and its horizontal
  // scrollbar is on screen.
  testWidgets('Users, a row wider than the card shows a scrollbar',
      (tester) async {
    await _pumpApp(tester, ThemeMode.light, fakeAdminSession(),
        data: TaggedUsersData.worstCase(
            name: 'a-much-longer-invented-name-than-the-card-has-room-for'));
    await _openUsers(tester);

    expect(tester.takeException(), isNull);
    expect(_tableScroll(tester).maxScrollExtent, greaterThan(0));
    final scrollbar = tester.widget<Scrollbar>(find
        .ancestor(of: find.byType(DataTable), matching: find.byType(Scrollbar))
        .first);
    expect(scrollbar.thumbVisibility, isTrue);
    await _unmount(tester);
  });
}

/// Opens the Users screen from the rail and lets it settle.
Future<void> _openUsers(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(NavigationRail), matching: find.text('Users')));
  await tester.pumpAndSettle();
}

/// The horizontal scroll view that holds the Users table.
ScrollPosition _tableScroll(WidgetTester tester) => tester
    .state<ScrollableState>(find
        .ancestor(of: find.byType(DataTable), matching: find.byType(Scrollable))
        .first)
    .position;

/// [FakeDashboardData] whose server refuses every new user, with an
/// invented reason.
class _RefusingData extends FakeDashboardData {
  @override
  Future<void> createUser(
          {required String name,
          required String email,
          required String password}) async =>
      throw ServiceError(400, 'user.create.username.not.available',
          'Username "$name" is not available.');
}

/// The real app below the session: [RoleGate] picks the shell or the
/// "Not authorized" page, as it does in the browser. Pumped to rest.
Future<void> _pumpApp(
  WidgetTester tester,
  ThemeMode mode,
  DashboardSession session, {
  Size size = const Size(1280, 800),
  FakeDashboardData? data,
  bool settle = true,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final theme = ThemeController();
  addTearDown(theme.dispose);

  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: DashboardTheme.light,
    darkTheme: DashboardTheme.dark,
    themeMode: mode,
    home: RoleGate(
      session: session,
      theme: theme,
      data: data ?? FakeDashboardData(),
    ),
  ));
  // Load, let the workflow-name lookups resolve, and finish every
  // transition before anything is captured.
  if (settle) await tester.pumpAndSettle();
}

void _expectSelected(WidgetTester tester, int index) {
  final rail = tester.widget<NavigationRail>(find.byType(NavigationRail));
  expect(rail.selectedIndex, index);
  expect(tester.binding.hasScheduledFrame, isFalse,
      reason: 'an animation is still running');
}

Future<void> _expectGolden(String file) => expectLater(
    find.byType(MaterialApp), matchesGoldenFile(file));

/// Panels refresh on a timer; unmount so none outlives the test.
Future<void> _unmount(WidgetTester tester) =>
    tester.pumpWidget(const SizedBox.shrink());

/// `flutter test` draws every glyph as a box unless fonts are loaded:
/// load the app's own (Fira Sans, Material Icons) from the font manifest.
/// There is no bundled monospace face, so ids and URIs are drawn in Fira
/// Sans here; in a browser they get the system monospace.
Future<void> _loadFonts() async {
  final manifest = json.decode(
      await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final family in manifest.cast<Map<String, dynamic>>()) {
    final name = family['family'] as String;
    final assets = [
      for (final font in (family['fonts'] as List).cast<Map>())
        '${font['asset']}',
    ];
    for (final loaderName in [
      name,
      if (name == TercenTokens.fontFamily) 'monospace',
    ]) {
      final loader = FontLoader(loaderName);
      for (final asset in assets) {
        loader.addFont(rootBundle.load(asset));
      }
      await loader.load();
    }
  }
}
