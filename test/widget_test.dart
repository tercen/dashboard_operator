import 'package:flutter_test/flutter_test.dart';

import 'package:tercen_dashboard/src/app.dart';
import 'package:tercen_dashboard/src/session.dart';

void main() {
  testWidgets('renders the no-session page when init failed', (tester) async {
    await tester.pumpWidget(DashboardApp(
      session: DashboardSession(),
      initError: const SessionError('No Tercen session token.'),
    ));

    expect(find.text('No session'), findsOneWidget);
    expect(find.textContaining('No Tercen session token'), findsOneWidget);
  });
}
