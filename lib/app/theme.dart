import 'package:flutter/material.dart';

/// Semantic colours used by amounts, charts and badges.
///
/// Income and expense are *never* distinguished by colour alone: every amount
/// also carries a `+`/`−` sign and an icon, which keeps the app usable for
/// colour-blind users and in bright sunlight.
class AppColors {
  const AppColors._();

  static const Color seed = Color(0xFF00695C);

  static const Color income = Color(0xFF2E7D32);
  static const Color expense = Color(0xFFC62828);
  static const Color transfer = Color(0xFF1565C0);
  static const Color warning = Color(0xFFEF6C00);

  static Color forType(Object type) {
    final name = type.toString();
    if (name.contains('income')) return income;
    if (name.contains('transfer')) return transfer;
    return expense;
  }
}

/// Maps the icon *names* stored in the database to real [IconData].
///
/// Storing names instead of code points keeps icon tree-shaking working and
/// means a re-themed icon set never invalidates stored rows.
class CategoryIcons {
  const CategoryIcons._();

  static const IconData fallback = Icons.category_outlined;

  static const Map<String, IconData> _byName = <String, IconData>{
    'restaurant': Icons.restaurant,
    'shopping_basket': Icons.shopping_basket,
    'directions_bus': Icons.directions_bus,
    'shopping_bag': Icons.shopping_bag,
    'home': Icons.home_rounded,
    'bolt': Icons.bolt,
    'school': Icons.school,
    'medical_services': Icons.medical_services,
    'smartphone': Icons.smartphone,
    'wifi': Icons.wifi,
    'subscriptions': Icons.subscriptions,
    'movie': Icons.movie,
    'flight': Icons.flight,
    'spa': Icons.spa,
    'volunteer_activism': Icons.volunteer_activism,
    'request_quote': Icons.request_quote,
    'receipt_long': Icons.receipt_long,
    'category': Icons.category,
    'payments': Icons.payments,
    'laptop': Icons.laptop_mac,
    'storefront': Icons.storefront,
    'science': Icons.science,
    'card_giftcard': Icons.card_giftcard,
    'trending_up': Icons.trending_up,
    'replay': Icons.replay,
    'apartment': Icons.apartment,
    'account_balance': Icons.account_balance,
    'savings': Icons.savings,
  };

  /// Names offered when the user creates their own category.
  static List<String> get names => _byName.keys.toList(growable: false);

  static IconData resolve(String? name) =>
      name == null ? fallback : (_byName[name] ?? fallback);
}

/// Material 3 themes.
///
/// Colours come from a single seed so light and dark stay in step. Bengali text
/// intentionally uses the platform font (`Noto Sans Bengali` on Android) rather
/// than a bundled font: bundling a Bengali face would add several megabytes to
/// the APK for a script the operating system already renders correctly.
class AppTheme {
  const AppTheme._();

  static ThemeData light() => _base(Brightness.light);
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.seed,
      brightness: brightness,
    );
    final isLight = brightness == Brightness.light;

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: isLight
            ? scheme.surfaceContainerLow
            : scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        space: 1,
        thickness: 1,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        backgroundColor: scheme.surfaceContainer,
        indicatorColor: scheme.secondaryContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        showDragHandle: true,
      ),
    );
  }
}
