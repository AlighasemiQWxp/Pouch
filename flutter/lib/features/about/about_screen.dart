import 'package:flutter/material.dart';

import '../../core/app_strings.dart';
import '../../core/pouch_bridge.dart';
import '../../core/pouch_theme.dart';
import '../../widgets/pouch_widgets.dart';
import '../../widgets/pouch_coin.dart';

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
        color: context.pouchPalette.ink,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset('assets/pouch-icon.png', width: 44, height: 44),
            const SizedBox(height: 16),
            const Row(
              children: [
                PouchCoin(size: 32),
                SizedBox(width: 10),
                Flexible(
                  child: Text(
                    'Pouch',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              strings.text('offlinePrivacyHint'),
              style: TextStyle(color: context.pouchPalette.goldPale),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                Chip(label: Text('${strings.text('versionLabel')} 2.0.0')),
                const Chip(label: Text('Android')),
                const Chip(label: Text('Linux')),
                const Chip(label: Text('Windows')),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      PouchCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _detail(context, strings.text('developedBy'), 'AlighasemiQWxp'),
            const SizedBox(height: 16),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: OutlinedButton.icon(
                onPressed: () =>
                    bridge.openExternalUrl('https://github.com/AlighasemiQWxp'),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(strings.text('githubProfile')),
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.only(top: 11),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 8,
      children: [
        Text(label, style: TextStyle(color: context.pouchPalette.muted)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    ),
  );
}
