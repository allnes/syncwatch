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
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 480,
          height: 360,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Column(
              children: [
                _titleBar(context),
                const Divider(height: 1),
                Expanded(
                  child: Row(
                    children: [
                      SizedBox(width: 150, child: _sidebar()),
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
      ),
    );
  }

  Widget _titleBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        setState(() => dialogOffset += details.delta);
      },
      child: Container(
        color: syncBackgroundDeep.withValues(alpha: 0.55),
        padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
        child: Row(
          children: [
            const Icon(Icons.settings_rounded, color: syncAccent, size: 18),
            const SizedBox(width: 6),
            Text(
              'SyncWatch · ${controller.t('settings')}',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 17),
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
      padding: const EdgeInsets.fromLTRB(5, 7, 5, 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  minLeadingWidth: 16,
                  horizontalTitleGap: 5,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 7),
                  selected: section == i,
                  selectedTileColor: syncAccent.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  leading: Icon(items[i].$1, size: 16),
                  title: Text(
                    items[i].$2,
                    style: const TextStyle(fontSize: 11.5),
                  ),
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
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: switch (section) {
          0 => _interface(),
          1 => _movies(),
          2 => _playback(),
          3 => _call(),
          _ => _sync(),
        },
      ),
    );
  }

  InputDecoration _compactDecoration(
    String label, {
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
    );
  }

  Widget _sectionHeader(String title, String subtitle, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: syncAccentSoft, size: 20),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: Colors.white60,
            fontSize: 11.5,
          ),
        ),
        const SizedBox(height: 5),
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
          style: const TextStyle(fontSize: 11.5),
          initialValue: controller.locale.languageCode,
          decoration: _compactDecoration(controller.t('language')),
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
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    style: const TextStyle(fontSize: 11.5),
                    key: ValueKey(controller.libraryPath),
                    initialValue: controller.libraryPath,
                    decoration: _compactDecoration(''),
                    onChanged: controller.setLibraryPath,
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 7,
                    ),
                  ),
                  onPressed: _browseMovieFolder,
                  child: const Icon(Icons.folder_open_rounded, size: 16),
                ),
              ],
            ),
            _compactSwitch(
              value: controller.scanSubfolders,
              onChanged: controller.setScanSubfolders,
              title: controller.t('scanSubfolders'),
            ),
            _compactSwitch(
              value: controller.automaticRefresh,
              onChanged: controller.setAutomaticRefresh,
              title: controller.t('automaticRefresh'),
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
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.skipSeconds,
              decoration: _compactDecoration(controller.t('skipInterval')),
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
            _compactSwitch(
              value: controller.autoReady,
              onChanged: controller.setAutoReady,
              title: controller.t('autoReady'),
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
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.callInputDevice,
              decoration: _compactDecoration(
                controller.t('inputDevice'),
                prefixIcon: const Icon(Icons.mic_rounded, size: 16),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.callOutputDevice,
              decoration: _compactDecoration(
                controller.t('outputDevice'),
                prefixIcon: const Icon(Icons.volume_up_rounded, size: 16),
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
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              style: const TextStyle(fontSize: 11.5),
              initialValue: '480p',
              decoration: _compactDecoration(controller.t('cameraQuality')),
              items: const [
                DropdownMenuItem(value: '480p', child: Text('480p')),
              ],
              onChanged: (_) {},
            ),
            _compactSwitch(
              value: controller.ducking,
              onChanged: controller.setDucking,
              title: controller.t('ducking'),
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
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.syncServer,
              decoration: _compactDecoration(controller.t('server')),
              onChanged: controller.setSyncServer,
            ),
            const SizedBox(height: 14),
            TextFormField(
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.roomName,
              decoration: _compactDecoration(controller.t('room')),
              onChanged: controller.setRoomName,
            ),
            const SizedBox(height: 14),
            TextFormField(
              style: const TextStyle(fontSize: 11.5),
              initialValue: controller.username,
              decoration: _compactDecoration(controller.t('username')),
              onChanged: controller.setUsername,
            ),
          ],
        ),
      ],
    );
  }

  Widget _compactSwitch({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
  }) {
    return SizedBox(
      height: 30,
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          Transform.scale(
            scaleX: 0.66,
            scaleY: 0.56,
            alignment: Alignment.centerRight,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  Widget _settingsCard({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: syncBackgroundDeep.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(10),
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
      padding: const EdgeInsets.fromLTRB(8, 5, 8, 6),
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
                  horizontal: 8,
                  vertical: 4,
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
                      size: 6,
                      color: syncSuccess,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      controller.t('changesSaved'),
                      style: const TextStyle(
                        fontSize: 11,
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              controller.t('cancel'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
          const SizedBox(width: 6),
          FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: _showSavedNotice,
            child: Text(
              controller.t('save'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }
}
