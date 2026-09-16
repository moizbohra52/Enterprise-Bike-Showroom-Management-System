import 'package:flutter/material.dart';

/// Centralized color palette.
///
/// Widgets must reference [AppColors] (or the [MaterialColorScheme] of the
/// active [ThemeData]) instead of hardcoding colors.
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFF14532D);
  static const Color primaryDark = Color(0xFF052E16);
  static const Color primaryLight = Color(0xFF4ADE80);
  static const Color accent = Color(0xFFF59E0B);
  static const Color accentDark = Color(0xFFB45309);

  // Semantic
  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFD97706);
  static const Color error = Color(0xFFDC2626);
  static const Color info = Color(0xFF2563EB);
  static const Color neutral = Color(0xFF64748B);
  static const Color danger = Color(0xFF991B1B);

  // Surfaces (light)
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color backgroundLight = Color(0xFFF1F5F9);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color borderLight = Color(0xFFE2E8F0);

  // Surfaces (dark)
  static const Color surfaceDark = Color(0xFF1E293B);
  static const Color backgroundDark = Color(0xFF0F172A);
  static const Color cardDark = Color(0xFF1E293B);
  static const Color borderDark = Color(0xFF334155);

  // Text (light)
  static const Color textPrimaryLight = Color(0xFF0F172A);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color textHintLight = Color(0xFF94A3B8);

  // Text (dark)
  static const Color textPrimaryDark = Color(0xFFF8FAFC);
  static const Color textSecondaryDark = Color(0xFFCBD5E1);
  static const Color textHintDark = Color(0xFF64748B);

  // Status colors used by [AppStatusChip].
  static const Color statusActive = Color(0xFF16A34A);
  static const Color statusPending = Color(0xFFD97706);
  static const Color statusCancelled = Color(0xFFDC2626);
  static const Color statusCompleted = Color(0xFF2563EB);
  static const Color statusOverdue = Color(0xFFB91C1C);
  static const Color statusDisabled = Color(0xFF64748B);
}

/// Centralized spacing scale (8pt grid).
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  static const double pagePadding = 16;
  static const double cardPadding = 16;
  static const double chipPadding = 8;
  static const double formRowGap = 12;
}

/// Centralized corner radius scale.
class AppRadius {
  AppRadius._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Centralized typography.
class AppTypography {
  AppTypography._();

  static const String fontFamily = 'Roboto';

  static const double displaySize = 34;
  static const double headlineSize = 26;
  static const double titleSize = 20;
  static const double subtitleSize = 16;
  static const double bodySize = 14;
  static const double captionSize = 12;
  static const double miniSize = 11;

  static const FontWeight titleWeight = FontWeight.w600;
  static const FontWeight labelWeight = FontWeight.w500;
  static const FontWeight regularWeight = FontWeight.w400;

  /// Default text theme used by [AppTheme].
  static TextTheme textTheme({required bool dark}) {
    final Color primary = dark
        ? AppColors.textPrimaryDark
        : AppColors.textPrimaryLight;
    final Color secondary = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return TextTheme(
      displayLarge: TextStyle(fontSize: displaySize, fontWeight: FontWeight.w700, color: primary),
      displaySmall: TextStyle(fontSize: headlineSize, fontWeight: FontWeight.w700, color: primary),
      headlineMedium: TextStyle(fontSize: titleSize, fontWeight: titleWeight, color: primary),
      titleLarge: TextStyle(fontSize: titleSize, fontWeight: titleWeight, color: primary),
      titleMedium: TextStyle(fontSize: subtitleSize, fontWeight: labelWeight, color: primary),
      titleSmall: TextStyle(fontSize: bodySize, fontWeight: labelWeight, color: primary),
      bodyLarge: TextStyle(fontSize: bodySize, fontWeight: regularWeight, color: primary),
      bodyMedium: TextStyle(fontSize: bodySize, fontWeight: regularWeight, color: primary),
      bodySmall: TextStyle(fontSize: captionSize, fontWeight: regularWeight, color: secondary),
      labelLarge: TextStyle(fontSize: bodySize, fontWeight: labelWeight, color: primary),
      labelMedium: TextStyle(fontSize: captionSize, fontWeight: labelWeight, color: secondary),
      labelSmall: TextStyle(fontSize: miniSize, fontWeight: labelWeight, color: secondary),
    );
  }
}

/// Centralized elevation shadows.
class AppShadows {
  AppShadows._();

  static const double elevationSm = 1;
  static const double elevationMd = 3;
  static const double elevationLg = 6;

  static List<BoxShadow> cardShadow({required bool dark}) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(dark ? 120 : 24),
        blurRadius: 10,
        offset: const Offset(0, 3),
      ),
    ];
  }

  static List<BoxShadow> dialogShadow({required bool dark}) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(dark ? 160 : 40),
        blurRadius: 24,
        offset: const Offset(0, 8),
      ),
    ];
  }
}

/// Centralized theme factory.
class AppTheme {
  AppTheme._();

  /// Light theme.
  static ThemeData light({MaterialColor? accent}) {
    return _build(brightness: Brightness.light, accent: accent);
  }

  /// Dark theme.
  static ThemeData dark({MaterialColor? accent}) {
    return _build(brightness: Brightness.dark, accent: accent);
  }

  static ThemeData _build({
    required Brightness brightness,
    MaterialColor? accent,
  }) {
    final bool dark = brightness == Brightness.dark;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: accent ?? AppColors.primary,
      brightness: brightness,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      canvasColor: dark ? AppColors.cardDark : AppColors.cardLight,
      cardColor: dark ? AppColors.cardDark : AppColors.cardLight,
      dividerColor: dark ? AppColors.borderDark : AppColors.borderLight,
      splashFactory: InkRipple.splashFactory,
      visualDensity: VisualDensity.adaptivePlatformDensity,
    );

    final OutlineInputBorder inputBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(
        color: dark ? AppColors.borderDark : AppColors.borderLight,
      ),
    );

    return base.copyWith(
      textTheme: AppTypography.textTheme(dark: dark),
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? AppColors.backgroundDark : Colors.white,
        foregroundColor: dark
            ? AppColors.textPrimaryDark
            : AppColors.textPrimaryLight,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: AppTypography.textTheme(dark: dark).titleMedium,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: dark ? AppColors.borderDark : AppColors.borderLight),
        ),
        color: dark ? AppColors.cardDark : AppColors.cardLight,
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark
            ? AppColors.surfaceDark.withAlpha(230)
            : AppColors.backgroundLight.withAlpha(200),
        border: inputBorder,
        enabledBorder: inputBorder,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: const BorderSide(color: AppColors.error, width: 1.6),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: AppShadows.elevationMd,
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        elevation: AppShadows.elevationLg,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: dark
            ? AppColors.textSecondaryDark
            : AppColors.textSecondaryLight,
        indicatorSize: TabBarIndicatorSize.label,
      ),
      tableTheme: base.tableTheme.copyWith(
        headerTextStyle: AppTypography.textTheme(dark: dark)
            .labelMedium
            ?.copyWith(color: scheme.primary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryLight,
      ),
    );
  }
}
