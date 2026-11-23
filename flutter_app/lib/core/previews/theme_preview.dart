import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

/// A custom MultiPreview annotation that automatically generates
/// both Light and Dark mode previews for a widget.
final class ThemePreview extends MultiPreview {
  const ThemePreview({required this.name});

  final String name;

  @override
  List<Preview> get previews => const [
    Preview(brightness: Brightness.light),
    Preview(brightness: Brightness.dark),
  ];

  @override
  List<Preview> transform() {
    final previews = super.transform();
    return previews.map((preview) {
      final builder = preview.toBuilder()
        ..group = 'UI Components'
        ..name = '$name - ${preview.brightness!.name}';

      // Use .build() instead of .toPreview() here!
      return builder.build();
    }).toList();
  }
}