import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int section = 1;
  AppController get controller => widget.controller;

  Future<void> _browseMovieFolder() async {
    final path = await getDirectoryPath(
      confirmButtonText: controller.t('open'),
    );
    if (path != null && path.isNotEmpty) {
      controller.setLibraryPath(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 780,
          maxWidth: 980,
          minHeight: 560,
          maxHeight: 720,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              _titleBar(context),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: 230, child: _sidebar()),
                    const VerticalDivider(width: 1),
                    Expanded(child: _content()),
                  ],
                ),
              ),
              const Divider(height: 1),
              _actions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    return Container(
      color: syncBackgroundDeep.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(20, 14, 10, 14),
      child: Row(
        children: [
          const Icon(Icons.settings_rounded, color: syncAccent),
          const SizedBox(width: 10),
          Text(
            'SyncWatch · ${controller.t('settings')}',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  Widget _sidebar() {
    final items = [
      (Icons.palette_outlined, controller.t('interface')),
      (Icons.movie_outlined, controller.t('movies')),
      (Icons.play_circle_outline_rounded, controller.t('playback')),
      (Icons.groups_2_outlined, controller.t('call')),
      (Icons.sync_rounded, controller.t('sync')),
    ];

    return Container(
      color: syncBackgroundDeep.withValues(alpha: 0.35),
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                selected: section == i,
                selectedTileColor: syncAccent.withValues(alpha: 0.15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(items[i].$1),
                title: Text(items[i].$2),
                onTap: () => setState(() => section = i),
              ),
            ),
          const Spacer(),
          const Divider(),
          DropdownButtonFormField<String>(
            value: controller.locale.languageCode,
            decoration: InputDecoration(labelText: controller.t('language')),
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
    );
  }

  Widget _content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(26),
      child: switch (section) {
        0 => _interface(),
        1 => _movies(),
        2 => _playback(),
        3 => _call(),
        _ => _sync(),
      },
    );
  }

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: syncAccentSoft, size: 30),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: Colors.white60)),
        const SizedBox(height: 22),
      ],
    );
  }

  Widget _interface() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          controller.t('interface'),
          controller.t('appearanceHint'),
          Icons.palette_outlined,
        ),
        DropdownButtonFormField<String>(
          value: controller.locale.languageCode,
          decoration: InputDecoration(labelText: controller.t('language')),
          items: const [
            DropdownMenuItem(value: 'en', child: Text('English')),
            DropdownMenuItem(value: 'ru', child: Text('Русский')),
          ],
          onChanged: (value) {
            if (value != null) controller.setLanguage(value);
          },
        ),
      ],
    );
  }

  Widget _movies() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          controller.t('movies'),
          controller.t('moviesHint'),
          Icons.movie_outlined,
        ),
        _settingsCard(
          children: [
            Text(
              controller.t('folder'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey(controller.libraryPath),
                    initialValue: controller.libraryPath,
                    onChanged: controller.setLibraryPath,
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: _browseMovieFolder,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: Text(controller.t('browse')),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.scanSubfolders,
              onChanged: controller.setScanSubfolders,
              title: Text(controller.t('scanSubfolders')),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _settingsCard(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.automaticRefresh,
              onChanged: controller.setAutomaticRefresh,
              title: Text(controller.t('automaticRefresh')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _playback() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          controller.t('playback'),
          controller.t('playbackHint'),
          Icons.play_circle_outline_rounded,
        ),
        _settingsCard(
          children: [
            DropdownButtonFormField<int>(
              value: controller.skipSeconds,
              decoration: InputDecoration(
                labelText: controller.t('skipInterval'),
              ),
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
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.autoReady,
              onChanged: controller.setAutoReady,
              title: Text(controller.t('autoReady')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _call() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          controller.t('call'),
          controller.t('callHint'),
          Icons.groups_2_outlined,
        ),
        _settingsCard(
          children: [
            DropdownButtonFormField<String>(
              value: '480p',
              decoration:
                  InputDecoration(labelText: controller.t('cameraQuality')),
              items: const [
                DropdownMenuItem(value: '480p', child: Text('480p')),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.ducking,
              onChanged: controller.setDucking,
              title: Text(controller.t('ducking')),
            ),
          ],
        ),
      ],
    );
  }

  Widget _sync() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          controller.t('sync'),
          controller.t('syncHint'),
          Icons.sync_rounded,
        ),
        _settingsCard(
          children: [
            TextFormField(
              initialValue: controller.syncServer,
              decoration: InputDecoration(labelText: controller.t('server')),
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
              decoration: InputDecoration(labelText: controller.t('username')),
              onChanged: controller.setUsername,
            ),
          ],
        ),
      ],
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: syncBackgroundDeep.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: syncBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(controller.t('cancel')),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(controller.t('save')),
          ),
        ],
      ),
    );
  }
}
