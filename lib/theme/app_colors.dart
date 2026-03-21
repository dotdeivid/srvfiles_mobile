import 'package:flutter/material.dart';

/// Design tokens del sistema visual de SrvFiles.
/// Replicados 1:1 desde frontend/src/index.css :root
class AppColors {
  AppColors._();

  // ─── Fondos ──────────────────────────────────────────────────────
  static const Color bgPrimary = Color(0xFF0a0a0f);
  static const Color bgSecondary = Color(0xFF0f0f1a);
  static const Color bgCard = Color.fromRGBO(15, 15, 30, 0.6);
  static const Color bgCardHover = Color.fromRGBO(20, 20, 40, 0.8);
  static const Color bgGlass = Color.fromRGBO(15, 15, 30, 0.4);

  // ─── Bordes ──────────────────────────────────────────────────────
  static const Color borderSubtle = Color.fromRGBO(99, 102, 241, 0.1);
  static const Color borderMedium = Color.fromRGBO(99, 102, 241, 0.2);
  static const Color borderAccent = Color.fromRGBO(99, 102, 241, 0.4);

  // ─── Textos ──────────────────────────────────────────────────────
  static const Color textPrimary = Color(0xFFe2e8f0);
  static const Color textSecondary = Color(0xFF94a3b8);
  static const Color textMuted = Color(0xFF64748b);
  static const Color textAccent = Color(0xFFc4b5fd);

  // ─── Acentos ─────────────────────────────────────────────────────
  static const Color accentPrimary = Color(0xFF6366f1);
  static const Color accentSecondary = Color(0xFF8b5cf6);

  static const LinearGradient accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [accentPrimary, accentSecondary],
  );

  // ─── Semánticos ──────────────────────────────────────────────────
  static const Color success = Color(0xFF34d399);
  static const Color warning = Color(0xFFfbbf24);
  static const Color danger = Color(0xFFf87171);
  static const Color dangerBg = Color.fromRGBO(248, 113, 113, 0.1);

  // ─── Sombras ─────────────────────────────────────────────────────
  static const List<BoxShadow> shadowSm = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.3), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const List<BoxShadow> shadowMd = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.4), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> shadowLg = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 30, offset: Offset(0, 8)),
  ];
  static const List<BoxShadow> shadowGlow = [
    BoxShadow(color: Color.fromRGBO(99, 102, 241, 0.15), blurRadius: 20),
  ];
}

/// Espaciado (base 16px)
class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

/// Radios de borde
class AppRadius {
  AppRadius._();

  static const double sm = 6;
  static const double md = 10;
  static const double lg = 16;
  static const double xl = 20;

  static final BorderRadius borderSm = BorderRadius.circular(sm);
  static final BorderRadius borderMd = BorderRadius.circular(md);
  static final BorderRadius borderLg = BorderRadius.circular(lg);
  static final BorderRadius borderXl = BorderRadius.circular(xl);
}
