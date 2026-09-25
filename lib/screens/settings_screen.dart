import 'dart:async';

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
  Offset dialogOffset = Offset.zero;
  bool showSavedNotice = false;
  Timer? savedNoticeTimer;
  AppController get controller => widget.controller;

  @override
  void dispose() {
    savedNoticeTimer?.cancel();
    super.dispose();
  }

  void _showSavedNotice() {
    savedNoticeTimer?.cancel();
    setState(() => showSavedNotice = true);

    savedNoticeTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      setState(() => showSavedNotice = false);
    });
  }

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
    return Transform.translate(
      offset: dialogOffset,
      child: Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 680,
          height: 430,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Column(
            children: [
              _titleBar(context),
              const Divider(height: 1),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(width: 205, child: _sidebar()),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() {
          dialogOffset += details.delta;
        });
      },
      child: Container(
        color: syncBackgroundDeep.withValues(alpha: 0.55),
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
        child: Row(
          children: [
            const Icon(Icons.settings_rounded, color: syncAccent, size: 20),
            const SizedBox(width: 8),
            Text(
              'SyncWatch · ${controller.t('settings')}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 19),
            ),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -3),
                  minLeadingWidth: 20,
                  horizontalTitleGap: 7,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  selected: section == i,
                  selectedTileColor: syncAccent.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  leading: Icon(items[i].$1, size: 19),
                  title: Text(items[i].$2, style: const TextStyle(fontSize: 13)),
                  onTap: () => setState(() => section = i),
                ),
              ),
            ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _content() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
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
            Icon(icon, color: syncAccentSoft, size: 24),
            const SizedBox(width: 8),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(color: Colors.white60, fontSize: 12.5),
        ),
        const SizedBox(height: 7),
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
          initialValue: controller.locale.languageCode,
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
            const SizedBox(height: 7),
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
            const SizedBox(height: 7),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.scanSubfolders,
              onChanged: controller.setScanSubfolders,
              title: Text(controller.t('scanSubfolders')),
            ),
          ],
        ),
        const SizedBox(height: 7),
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
              initialValue: controller.skipSeconds,
              decoration: InputDecoration(
                labelText: controller.t('skipInterval'),
              ),
              items: const [5, 10, 15, 30, 60]
                  .map(
                    (value) => DropdownMenuItem(
                      value: value,
                      child: Text('$value ${controller.t('secondsShort')}'),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) controller.setSkipSeconds(value);
              },
            ),
            const SizedBox(height: 8),
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
              initialValue: controller.callInputDevice,
              decoration: InputDecoration(
                labelText: controller.t('inputDevice'),
                prefixIcon: const Icon(Icons.mic_rounded),
              ),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(controller.t('systemDefault')),
                ),
                DropdownMenuItem(
                  value: 'laptop',
                  child: Text(controller.t('laptopMicrophone')),
                ),
                DropdownMenuItem(
                  value: 'usb',
                  child: Text(controller.t('usbMicrophone')),
                ),
              ],
              onChanged: (value) {
                if (value != null) controller.setCallInputDevice(value);
              },
            ),
            const SizedBox(height: 7),
            DropdownButtonFormField<String>(
              initialValue: controller.callOutputDevice,
              decoration: InputDecoration(
                labelText: controller.t('outputDevice'),
                prefixIcon: const Icon(Icons.volume_up_rounded),
              ),
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(controller.t('systemDefault')),
                ),
                DropdownMenuItem(
                  value: 'speakers',
                  child: Text(controller.t('speakers')),
                ),
                DropdownMenuItem(
                  value: 'headphones',
                  child: Text(controller.t('headphones')),
                ),
              ],
              onChanged: (value) {
                if (value != null) controller.setCallOutputDevice(value);
              },
            ),
            const SizedBox(height: 7),
            DropdownButtonFormField<String>(
              initialValue: '480p',
              decoration:
                  InputDecoration(labelText: controller.t('cameraQuality')),
              items: const [
                DropdownMenuItem(value: '480p', child: Text('480p')),
              ],
              onChanged: (_) {},
            ),
            const SizedBox(height: 7),
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
            const SizedBox(height: 8),
            TextFormField(
              initialValue: controller.roomName,
              decoration: InputDecoration(labelText: controller.t('room')),
              onChanged: controller.setRoomName,
            ),
            const SizedBox(height: 8),
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
      padding: const EdgeInsets.all(10),
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
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
      child: Row(
        children: [
          AnimatedOpacity(
            opacity: showSavedNotice ? 1 : 0,
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeOut,
            child: IgnorePointer(
              ignoring: !showSavedNotice,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: syncSuccess.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: syncSuccess.withValues(alpha: 0.34),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.circle,
                      size: 7,
                      color: syncSuccess,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      controller.t('changesSaved'),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              controller.t('cancel'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onPressed: _showSavedNotice,
            child: Text(
              controller.t('save'),
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
