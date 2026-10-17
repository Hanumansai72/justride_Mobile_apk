import 'package:flutter/material.dart';
import '../../features/profile/screens/help_support_screen.dart';

class ContextualHelpButton extends StatelessWidget {
  const ContextualHelpButton({super.key, required this.category});
  final String category;
  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: '$category help',
        icon: const Icon(Icons.help_outline),
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => HelpSupportScreen(initialCategory: category))),
      );
}
