import 'package:flutter/material.dart';

/// Google's supplied artwork, bundled locally so it also works offline.
class GoogleLogoWidget extends StatelessWidget {
  const GoogleLogoWidget({super.key, this.size = 22});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/brands/google-g.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'Google',
      );
}
