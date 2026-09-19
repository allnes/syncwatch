import 'package:flutter/material.dart';

import '../app.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: Text(controller.t('settings'))),
          body: ListView(
            padding: const EdgeInsets.all(28),
            children: [
              _section(
                context,
                controller.t('interface'),
                [
                  DropdownButtonFormField<String>(
                    value: controller.locale.languageCode,
                    decoration:
                        InputDecoration(labelText: controller.t('language')),
                    items: const [
                      DropdownMenuItem(value: 'en', child: Text('English')),
                      DropdownMenuItem(value: 'ru', child: Text('Русский')),
                    ],
                    onChanged: (value) {
                      if (value != null) controller.setLanguage(value);
                    },
                  ),
                ],
              ),
              _section(
                context,
                controller.t('movieLibrary'),
                [
                  TextFormField(
                    initialValue: controller.libraryPath,
                    decoration:
                        InputDecoration(labelText: controller.t('folder')),
                    onChanged: controller.setLibraryPath,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: true,
                    onChanged: (_) {},
                    title: Text(controller.t('scanSubfolders')),
                  ),
                ],
              ),
              _section(
                context,
                controller.t('playback'),
                [
                  DropdownButtonFormField<int>(
                    value: controller.skipSeconds,
                    decoration:
                        InputDecoration(labelText: controller.t('skipInterval')),
                    items: const [5, 10, 15, 30, 60]
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text('$value s'),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) controller.setSkipSeconds(value);
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.autoReady,
                    onChanged: controller.setAutoReady,
                    title: Text(controller.t('autoReady')),
                  ),
                ],
              ),
              _section(
                context,
                controller.t('call'),
                [
                  DropdownButtonFormField<String>(
                    value: '480p',
                    decoration: InputDecoration(
                      labelText: controller.t('cameraQuality'),
                    ),
                    items: const [
                      DropdownMenuItem(value: '480p', child: Text('480p')),
                    ],
                    onChanged: (_) {},
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: controller.ducking,
                    onChanged: controller.setDucking,
                    title: Text(controller.t('ducking')),
                  ),
                ],
              ),
              _section(
                context,
                controller.t('sync'),
                [
                  TextFormField(
                    initialValue: controller.syncServer,
                    decoration:
                        InputDecoration(labelText: controller.t('server')),
                    onChanged: controller.setSyncServer,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: controller.roomName,
                    decoration: InputDecoration(labelText: controller.t('room')),
                    onChanged: controller.setRoomName,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    initialValue: controller.username,
                    decoration:
                        InputDecoration(labelText: controller.t('username')),
                    onChanged: controller.setUsername,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 30),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
