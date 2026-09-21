import 'package:flutter/material.dart';

/// Colori di brand (dal prototipo Forge + logo Tigert).
class TC {
  static const accent = Color(0xFFC6F24E);
  static const accentHi = Color(0xFFDDFF85);
  static const onAccent = Color(0xFF10130A);
  static const prot = Color(0xFF6EA8FF);
  static const carb = Color(0xFFFFB23D);
  static const fat = Color(0xFFFF7A66);
  static const danger = Color(0xFFFF5C4D);
  static const warn = Color(0xFFFFB23D);
}

/// Token di tema (scuro / chiaro) come nel prototipo.
@immutable
class TT extends ThemeExtension<TT> {
  final bool dark;
  final Color bg, surf, surf2, line, ink, dim, soft, accentInk;

  const TT({
    required this.dark,
    required this.bg,
    required this.surf,
    required this.surf2,
    required this.line,
    required this.ink,
    required this.dim,
    required this.soft,
    required this.accentInk,
  });

  static const darkT = TT(
    dark: true,
    bg: Color(0xFF0F110E),
    surf: Color(0xFF171A15),
    surf2: Color(0xFF1E2219),
    line: Color(0x17FFFFFF),
    ink: Color(0xFFF2F4EF),
    dim: Color(0xFF8C938A),
    soft: Color(0xFFA8AFA4),
    accentInk: TC.accent,
  );

  static const lightT = TT(
    dark: false,
    bg: Color(0xFFF4F5F0),
    surf: Color(0xFFFFFFFF),
    surf2: Color(0xFFEDEFE7),
    line: Color(0x1A000000),
    ink: Color(0xFF14170F),
    dim: Color(0xFF6B7268),
    soft: Color(0xFF4A5046),
    accentInk: Color(0xFF4A6400),
  );

  /// Tinta leggera dell'accento per card "suggerimento".
  Color get accentTint => TC.accent.withValues(alpha: dark ? 0.07 : 0.16);
  Color get accentLine => TC.accent.withValues(alpha: dark ? 0.30 : 0.60);

  @override
  TT copyWith({bool? dark}) => this;

  @override
  TT lerp(ThemeExtension<TT>? other, double t) {
    if (other is! TT) return this;
    return t < 0.5 ? this : other;
  }
}

extension TTx on BuildContext {
  TT get tt => Theme.of(this).extension<TT>()!;
}

const tabular = [FontFeature.tabularFigures()];

/// Stili tipografici ricorrenti.
class TS {
  static TextStyle h1(TT t) => TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: t.ink, height: 1.1);
  static TextStyle h2(TT t) => TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: t.ink);
  static TextStyle title(TT t) => TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: t.ink);
  static TextStyle body(TT t) => TextStyle(fontSize: 14, color: t.ink, height: 1.35);
  static TextStyle muted(TT t, [double size = 13]) => TextStyle(fontSize: size, color: t.dim, height: 1.4);
  static TextStyle soft(TT t, [double size = 13]) => TextStyle(fontSize: size, color: t.soft, height: 1.45);
  static TextStyle label(TT t, [Color? c]) =>
      TextStyle(fontSize: 11.5, letterSpacing: 1.6, fontWeight: FontWeight.w600, color: c ?? t.dim);
  static TextStyle num(TT t, double size, {Color? color, FontWeight w = FontWeight.w800}) => TextStyle(
        fontSize: size,
        fontWeight: w,
        letterSpacing: size > 24 ? -size * 0.04 : -0.2,
        color: color ?? t.ink,
        height: 1.05,
        fontFeatures: tabular,
      );
}

ThemeData buildTheme(TT t) {
  final brightness = t.dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: TC.accent, brightness: brightness).copyWith(
    primary: t.dark ? TC.accent : t.accentInk,
    onPrimary: t.dark ? TC.onAccent : Colors.white,
    secondary: TC.accent,
    onSecondary: TC.onAccent,
    surface: t.surf,
    onSurface: t.ink,
    surfaceContainerHighest: t.surf2,
    outline: t.line,
    error: TC.danger,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: 'Archivo',
    colorScheme: scheme,
  );
  final border = OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: t.line));
  return base.copyWith(
    scaffoldBackgroundColor: t.bg,
    canvasColor: t.bg,
    dividerColor: t.line,
    extensions: [t],
    textTheme: base.textTheme.apply(bodyColor: t.ink, displayColor: t.ink, fontFamily: 'Archivo'),
    appBarTheme: AppBarTheme(
      backgroundColor: t.bg,
      foregroundColor: t.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontFamily: 'Archivo', fontSize: 18, fontWeight: FontWeight.w700, color: t.ink),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surf,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: t.dim,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surf,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: TextStyle(fontFamily: 'Archivo', fontSize: 19, fontWeight: FontWeight.w800, color: t.ink),
      contentTextStyle: TextStyle(fontFamily: 'Archivo', fontSize: 14, color: t.soft, height: 1.45),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surf2,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: border,
      enabledBorder: border,
      focusedBorder: border.copyWith(borderSide: BorderSide(color: t.dark ? TC.accent : t.accentInk, width: 1.5)),
      labelStyle: TextStyle(color: t.dim),
      hintStyle: TextStyle(color: t.dim),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: t.dark ? const Color(0xFF2A2F24) : const Color(0xFF14170F),
      contentTextStyle: const TextStyle(fontFamily: 'Archivo', color: Color(0xFFF2F4EF), fontSize: 14),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TC.onAccent : t.dim),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? TC.accent : t.surf2),
      trackOutlineColor: WidgetStateProperty.all(t.line),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: TC.accent,
      inactiveTrackColor: t.surf2,
      thumbColor: t.dark ? TC.accent : t.accentInk,
      overlayColor: TC.accent.withValues(alpha: 0.15),
      trackHeight: 6,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: TC.accent),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.dark ? TC.accent : t.accentInk,
      selectionColor: TC.accent.withValues(alpha: 0.35),
      selectionHandleColor: t.dark ? TC.accent : t.accentInk,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: t.surf,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: t.line)),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: t.surf2, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: t.ink, fontSize: 12),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}
