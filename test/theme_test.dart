import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo/ui/theme.dart';

void main() {
  test('buildLightTheme uses the shared palette and 16px body floor', () {
    final theme = buildLightTheme();

    expect(theme.colorScheme.brightness, Brightness.light);
    expect(theme.colorScheme.primary, const Color(0xFFB8862E));
    expect(theme.colorScheme.onPrimary, const Color(0xFF211D1B));
    expect(theme.textTheme.bodyLarge!.fontSize, AppTextSize.body);
    expect(theme.textTheme.bodyMedium!.fontSize, AppTextSize.body);
  });

  test('buildDarkTheme uses the shared palette and 16px body floor', () {
    final theme = buildDarkTheme();

    expect(theme.colorScheme.brightness, Brightness.dark);
    expect(theme.colorScheme.primary, const Color(0xFFB8862E));
    expect(theme.colorScheme.onPrimary, const Color(0xFF211D1B));
    expect(theme.textTheme.bodyLarge!.fontSize, AppTextSize.body);
    expect(theme.textTheme.bodyMedium!.fontSize, AppTextSize.body);
  });
}
