import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ====== Brand tokens (solid, minimalis) ======
class Brand {
  static const blue = Color(0xFF2563EB); // aksen utama
  static const blueLight = Color(0xFF3B82F6);
}

/// Token warna kustom yang tidak ada di ColorScheme bawaan.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color chatBackground;
  final Color incomingBubble;
  final Color incomingText;
  final Color outgoingBubble;
  final Color outgoingText;
  final Color muted;
  final Color cardBorder;

  const AppPalette({
    required this.chatBackground,
    required this.incomingBubble,
    required this.incomingText,
    required this.outgoingBubble,
    required this.outgoingText,
    required this.muted,
    required this.cardBorder,
  });

  @override
  AppPalette copyWith({
    Color? chatBackground,
    Color? incomingBubble,
    Color? incomingText,
    Color? outgoingBubble,
    Color? outgoingText,
    Color? muted,
    Color? cardBorder,
  }) {
    return AppPalette(
      chatBackground: chatBackground ?? this.chatBackground,
      incomingBubble: incomingBubble ?? this.incomingBubble,
      incomingText: incomingText ?? this.incomingText,
      outgoingBubble: outgoingBubble ?? this.outgoingBubble,
      outgoingText: outgoingText ?? this.outgoingText,
      muted: muted ?? this.muted,
      cardBorder: cardBorder ?? this.cardBorder,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      chatBackground: Color.lerp(chatBackground, other.chatBackground, t)!,
      incomingBubble: Color.lerp(incomingBubble, other.incomingBubble, t)!,
      incomingText: Color.lerp(incomingText, other.incomingText, t)!,
      outgoingBubble: Color.lerp(outgoingBubble, other.outgoingBubble, t)!,
      outgoingText: Color.lerp(outgoingText, other.outgoingText, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
    );
  }

  static AppPalette of(BuildContext context) =>
      Theme.of(context).extension<AppPalette>()!;
}

/// ====== LIGHT ======
ThemeData buildLightTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: Brand.blue,
    onPrimary: Colors.white,
    secondary: Brand.blue,
    onSecondary: Colors.white,
    error: Color(0xFFDC2626),
    onError: Colors.white,
    surface: Colors.white,
    onSurface: Color(0xFF111827),
    surfaceContainerHighest: Color(0xFFF1F4F9),
    outline: Color(0xFFE3E8EF),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Colors.white,
  );

  return _common(base, scheme).copyWith(
    extensions: const [
      AppPalette(
        chatBackground: Color(0xFFF7F9FC),
        incomingBubble: Colors.white,
        incomingText: Color(0xFF111827),
        // Bubble keluar: biru muda lembut (bukan biru aksen) agar centang
        // biru terlihat jelas.
        outgoingBubble: Color(0xFFDCEBFF),
        outgoingText: Color(0xFF0F2A4D),
        muted: Color(0xFF6B7280),
        cardBorder: Color(0xFFEDF1F6),
      ),
    ],
  );
}

/// ====== DARK ======
ThemeData buildDarkTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Brand.blueLight,
    onPrimary: Colors.white,
    secondary: Brand.blueLight,
    onSecondary: Colors.white,
    error: Color(0xFFF87171),
    onError: Color(0xFF1A0B0B),
    surface: Color(0xFF15171C),
    onSurface: Color(0xFFE7E9EE),
    surfaceContainerHighest: Color(0xFF1E2127),
    outline: Color(0xFF2A2E37),
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0D0E12),
  );

  return _common(base, scheme).copyWith(
    extensions: const [
      AppPalette(
        chatBackground: Color(0xFF0D0E12),
        incomingBubble: Color(0xFF1C1F26),
        incomingText: Color(0xFFE7E9EE),
        // Bubble keluar: abu kebiruan gelap (bukan biru aksen).
        outgoingBubble: Color(0xFF26344A),
        outgoingText: Color(0xFFEAF1FB),
        muted: Color(0xFF8A90A0),
        cardBorder: Color(0xFF23272F),
      ),
    ],
  );
}

/// Pengaturan komponen yang sama untuk light & dark — gaya minimalis:
/// tanpa bayangan tebal, andalkan garis tipis & ruang kosong.
ThemeData _common(ThemeData base, ColorScheme scheme) {
  final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 20,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      highlightElevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
      hintStyle: TextStyle(color: scheme.onSurface.withValues(alpha: 0.4)),
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outline,
      thickness: 0.6,
      space: 0,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
