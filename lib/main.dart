/// Conventional application entry point.
///
/// The real bootstrap lives in `lib/app/main.dart` alongside the rest of the
/// app wiring. This file exists so the standard tooling entry point
/// (`lib/main.dart`) works, e.g. `flutter run`, `flutter build apk`, and the
/// `flutter test` widget-test harness, without requiring a custom `-t` target.
library;

import 'app/main.dart' as app;

void main() => app.main();
