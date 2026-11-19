import 'package:flutter/material.dart';

const brand = Color(0xFFFF8300);
const salud = Color(0xFF12A5E5);
const ink = Color(0xFF1B2A33);
const paper = Color(0xFFF3F3F0);
const border = Color(0xFFE3E3DE);
const muted = Color(0xFF5B6B74);
const blueTint = Color(0xFFE7F6FD);
const brandTint = Color(0xFFFFF1E3);

/// Brand orange darkened for text on [paper]: 4.8:1, above the 4.5:1 that
/// WCAG AA asks of normal text ([brand] itself reaches only 2.2:1).
const brandText = Color(0xFFA85400);

/// Widest layout the app uses; wider windows are treated as a phone.
const phoneMaxWidth = 440.0;

ThemeData executiveTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Mulish',
  scaffoldBackgroundColor: paper,
  colorScheme: ColorScheme.fromSeed(
    seedColor: brand,
    primary: brand,
    secondary: salud,
    surface: Colors.white,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 23,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w800,
      color: ink,
    ),
    titleMedium: TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: ink,
    ),
    bodyMedium: TextStyle(fontSize: 14, color: ink, height: 1.5),
    bodySmall: TextStyle(fontSize: 12, color: muted, height: 1.5),
  ),
  // Floating surfaces are white; the seed colour would tint them peach.
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    modalBackgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
  ),
  datePickerTheme: const DatePickerThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
  ),
  menuTheme: const MenuThemeData(style: _whiteMenu),
  dropdownMenuTheme: const DropdownMenuThemeData(menuStyle: _whiteMenu),
  popupMenuTheme: const PopupMenuThemeData(
    color: Colors.white,
    surfaceTintColor: Colors.transparent,
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: salud, width: 2),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: brand,
      foregroundColor: ink,
      minimumSize: const Size(double.infinity, 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      textStyle: const TextStyle(
        fontFamily: 'Mulish',
        fontWeight: FontWeight.w800,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(double.infinity, 48),
      side: const BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  ),
);

const _whiteMenu = MenuStyle(
  backgroundColor: WidgetStatePropertyAll(Colors.white),
  surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
);
