import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // LIGHT MODE — Organic Atelier (existing green brand)
  static const Color _lightCanvas  = Color(0xFFF4F6F4);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightCard    = Color(0xFFFFFFFF);
  static const Color _lightPrimary = Color(0xFF1B5E20);
  static const Color _lightText    = Color(0xFF0D1B0F);
  static const Color _lightSubtext = Color(0xFF4A6741);
  static const Color _lightHint    = Color(0xFF8FAE8B);

  // DARK MODE — Ethereal Night Atelier
  static const Color _darkCanvas    = Color(0xFF0A0B0A);
  static const Color _darkSurface   = Color(0xFF141614);
  static const Color _darkCard      = Color(0xFF1C1F1C);
  static const Color _darkPrimary   = Color(0xFF3FFF8B);
  static const Color _darkContainer = Color(0xFF004734);
  static const Color _darkText      = Color(0xFFE1E3DE);
  static const Color _darkSubtext   = Color(0xFF91938D);

  // SHARED — Semantic colors same in both modes
  static const Color rain      = Color(0xFF1976D2);
  static const Color rainSurf  = Color(0xFFE3F2FD);
  static const Color heat      = Color(0xFFE65100);
  static const Color heatSurf  = Color(0xFFFFF3E0);
  static const Color platform  = Color(0xFF00695C);
  static const Color platSurf  = Color(0xFFE0F2F1);
  static const Color fraud     = Color(0xFF4A148C);
  static const Color fraudSurf = Color(0xFFF3E5F5);
  static const Color pending   = Color(0xFFE65100);
  static const Color pendSurf  = Color(0xFFFFF8E1);
  static const Color approved  = Color(0xFF1B5E20);
  static const Color appSurf   = Color(0xFFE8F5E9);
  static const Color danger    = Color(0xFFB71C1C);
  static const Color dangerSurf= Color(0xFFFFEBEE);

  // GRADIENT helpers
  static const LinearGradient primaryGradientLight = LinearGradient(
    colors: [Color(0xFF1B5E20), Color(0xFF2E7D32)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient primaryGradientDark = LinearGradient(
    colors: [Color(0xFF3FFF8B), Color(0xFF00E676)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static LinearGradient primaryGradient(bool isDark) =>
    isDark ? primaryGradientDark : primaryGradientLight;

  // SHADOW helpers
  // Light mode: standard subtle shadow
  // Dark mode: Electric Mint tinted ambient glow
  static List<BoxShadow> cardShadow(bool isDark) => isDark
    ? [BoxShadow(
        color: const Color(0xFF3FFF8B).withValues(alpha: 0.04),
        blurRadius: 20,
        offset: const Offset(0, 8),
      )]
    : [BoxShadow(
        color: const Color(0xFF0D1B0F).withValues(alpha: 0.06),
        blurRadius: 12,
        offset: const Offset(0, 4),
      )];

  static List<BoxShadow> floatingButtonShadow(bool isDark) => isDark
    ? [BoxShadow(
        color: const Color(0xFF3FFF8B).withValues(alpha: 0.25),
        blurRadius: 20,
        offset: const Offset(0, 8),
      )]
    : [BoxShadow(
        color: const Color(0xFF1B5E20).withValues(alpha: 0.40),
        blurRadius: 16,
        offset: const Offset(0, 4),
      )];

  static TextTheme _buildTextTheme(
    Color primary, Color secondary, Color accent) {
    return GoogleFonts.manropeTextTheme().copyWith(
      displayLarge: GoogleFonts.manrope(
        fontSize: 52, fontWeight: FontWeight.w800, color: primary),
      displayMedium: GoogleFonts.manrope(
        fontSize: 36, fontWeight: FontWeight.w700, color: primary),
      displaySmall: GoogleFonts.manrope(
        fontSize: 28, fontWeight: FontWeight.w700, color: primary),
      headlineLarge: GoogleFonts.manrope(
        fontSize: 24, fontWeight: FontWeight.w700, color: primary),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 20, fontWeight: FontWeight.w700, color: primary),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 18, fontWeight: FontWeight.w600, color: primary),
      titleLarge: GoogleFonts.manrope(
        fontSize: 16, fontWeight: FontWeight.w600, color: primary),
      titleMedium: GoogleFonts.manrope(
        fontSize: 15, fontWeight: FontWeight.w600, color: primary),
      titleSmall: GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      bodyLarge: GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w400, 
        color: primary, height: 1.6),
      bodyMedium: GoogleFonts.manrope(
        fontSize: 13, fontWeight: FontWeight.w400, 
        color: secondary, height: 1.5),
      bodySmall: GoogleFonts.manrope(
        fontSize: 12, fontWeight: FontWeight.w400, color: secondary),
      labelLarge: GoogleFonts.manrope(
        fontSize: 14, fontWeight: FontWeight.w600, color: primary),
      labelMedium: GoogleFonts.manrope(
        fontSize: 12, fontWeight: FontWeight.w600, color: secondary),
      labelSmall: GoogleFonts.manrope(
        fontSize: 11, fontWeight: FontWeight.w600,
        color: accent, letterSpacing: 0.8),
    );
  }

  // ============================================================
  // LIGHT THEME — default, shown on all phones with light mode
  // ============================================================
  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary:          _lightPrimary,
        onPrimary:        Colors.white,
        primaryContainer: Color(0xFFE8F5E9),
        onPrimaryContainer: _lightPrimary,
        secondary:        Color(0xFF4A6741),
        onSecondary:      Colors.white,
        surface:          _lightSurface,
        onSurface:        _lightText,
        surfaceContainerHighest: Color(0xFFF4F6F4),
        error:            Color(0xFFB71C1C),
        onError:          Colors.white,
      ),
      scaffoldBackgroundColor: _lightCanvas,
      canvasColor:             _lightCanvas,
      cardColor:               _lightCard,

      // NO dividers anywhere — tonal shifts only
      dividerTheme: const DividerThemeData(
        color: Colors.transparent, thickness: 0, space: 0),

      appBarTheme: const AppBarTheme(
        backgroundColor:       Colors.transparent,
        foregroundColor:       _lightText,
        elevation:             0,
        scrolledUnderElevation: 0,
        centerTitle:           false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:              Colors.transparent,
          statusBarIconBrightness:     Brightness.dark,
          systemNavigationBarColor:    Colors.white,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
      ),

      textTheme: _buildTextTheme(
        _lightText, _lightSubtext, _lightPrimary),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _lightPrimary,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
          elevation: 0,
          textStyle: GoogleFonts.manrope(
            fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _lightPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
          side: const BorderSide(color: _lightPrimary, width: 1.5),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:         true,
        fillColor:      const Color(0xFFF4F6F4),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: _lightPrimary, width: 1.5)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Color(0xFFB71C1C), width: 1.5)),
        hintStyle: GoogleFonts.manrope(
          fontSize: 14, color: _lightHint),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor:      Colors.white,
        selectedItemColor:    _lightPrimary,
        unselectedItemColor:  Color(0xFF8FAE8B),
        elevation:            0,
        type: BottomNavigationBarType.fixed,
      ),

      chipTheme: ChipThemeData(
        backgroundColor:   const Color(0xFFF4F6F4),
        labelStyle:        GoogleFonts.manrope(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: _lightSubtext),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4),
      ),
    );
  }

  // ============================================================
  // DARK THEME — Ethereal Night Atelier
  // Only shown when device is in dark mode
  // ============================================================
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: const ColorScheme.dark(
        primary:          _darkPrimary,
        onPrimary:        _darkSurface,
        primaryContainer: _darkContainer,
        onPrimaryContainer: _darkPrimary,
        secondary:        _darkContainer,
        onSecondary:      _darkPrimary,
        surface:          _darkSurface,
        onSurface:        _darkText,
        surfaceContainerHighest: _darkCard,
        error:            Color(0xFFFF6B6B),
        onError:          _darkCanvas,
      ),
      scaffoldBackgroundColor: _darkCanvas,
      canvasColor:             _darkCanvas,
      cardColor:               _darkCard,

      dividerTheme: const DividerThemeData(
        color: Colors.transparent, thickness: 0, space: 0),

      appBarTheme: const AppBarTheme(
        backgroundColor:       Colors.transparent,
        foregroundColor:       _darkText,
        elevation:             0,
        scrolledUnderElevation: 0,
        centerTitle:           false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:              Colors.transparent,
          statusBarIconBrightness:     Brightness.light,
          systemNavigationBarColor:    Color(0xFF0A0B0A),
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),

      textTheme: _buildTextTheme(
        _darkText, _darkSubtext, _darkPrimary),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          // Dark mode: gradient handled per-widget
          // Base color here for fallback
          backgroundColor: _darkPrimary,
          foregroundColor: _darkCanvas,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
          elevation: 0,
          textStyle: GoogleFonts.manrope(
            fontSize: 15, fontWeight: FontWeight.w700),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _darkPrimary,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28)),
          side: const BorderSide(
            color: Color(0xFF3FFF8B), width: 1.0),
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled:         true,
        fillColor:      _darkCard,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 24, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(
            color: _darkContainer, width: 0.5)),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: const BorderSide(
            color: Color(0xFFFF6B6B), width: 1.0)),
        hintStyle: GoogleFonts.manrope(
          fontSize: 14, color: _darkSubtext),
      ),

      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor:     _darkSurface,
        selectedItemColor:   _darkPrimary,
        unselectedItemColor: Color(0xFF91938D),
        elevation:           0,
        type: BottomNavigationBarType.fixed,
      ),

      chipTheme: ChipThemeData(
        backgroundColor:  _darkCard,
        labelStyle:       GoogleFonts.manrope(
          fontSize: 12, fontWeight: FontWeight.w500,
          color: _darkSubtext),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(
          horizontal: 12, vertical: 4),
      ),
    );
  }
}
