import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../theme/app_theme.dart';

class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('CHANGELOG', style: TextStyle(letterSpacing: 2, fontWeight: FontWeight.bold, fontSize: 16)),
      ),
      body: FutureBuilder<String>(
        future: rootBundle.loadString('CHANGELOG.md'),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading changelog: ${snapshot.error}',
                style: const TextStyle(color: AppTheme.errorColor),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Colors.white));
          }

          return Markdown(
            data: snapshot.data!,
            styleSheet: MarkdownStyleSheet(
              h1: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
              h2: const TextStyle(color: AppTheme.accentColor, fontSize: 20, fontWeight: FontWeight.bold),
              h3: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              p: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14, height: 1.5),
              listBullet: const TextStyle(color: AppTheme.accentColor),
              blockquote: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontStyle: FontStyle.italic),
              code: const TextStyle(
                color: AppTheme.accentColor,
                backgroundColor: Colors.transparent,
                fontFamily: 'monospace',
              ),
              codeblockDecoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        },
      ),
    );
  }
}
