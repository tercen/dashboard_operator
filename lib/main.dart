import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/session.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final session = DashboardSession();
  Object? initError;
  try {
    await session.initialize();
  } catch (e) {
    initError = e;
  }

  runApp(DashboardApp(session: session, initError: initError));
}
