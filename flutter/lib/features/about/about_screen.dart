import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({required this.bridge, required this.strings, super.key});

  final PouchBridge bridge;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) => PouchPage(
    children: [
      PouchIntro(
        eyebrow: strings.text('aboutLabel'),
        title: strings.text('aboutPageTitle'),
        description: strings.text('aboutDescription'),
      ),
      PouchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/pouch-icon.png',
                    width: 68,
                    height: 68,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    'Pouch',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: context.pouchPalette.ink,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _detail(context, strings.text('versionLabel'), '1.0'),
            _detail(context, strings.text('developedBy'), 'AlighasemiQWxp'),
            const SizedBox(height: 13),
            OutlinedButton.icon(
              onPressed: () =>
                  bridge.openExternalUrl('https://github.com/AlighasemiQWxp'),
              icon: const Icon(Icons.open_in_new_rounded),
              label: Text(strings.text('githubProfile')),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 11),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: context.pouchPalette.muted),
          ),
        ),
        Text(value, style: TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
