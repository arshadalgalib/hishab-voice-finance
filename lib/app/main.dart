import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

/// Entry point.
///
/// `ProviderScope` is the single composition root: every database, service and
/// clock in the app is created through it, which is what makes the whole
/// application testable by overriding providers instead of using globals.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: HishabApp()));
}
