import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_theme.dart';

class PlayerSettingsScreen extends StatefulWidget {
  const PlayerSettingsScreen({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  State<PlayerSettingsScreen> createState() => _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends State<PlayerSettingsScreen> {
  bool get _isLight => Theme.of(context).brightness == Brightness.light;
  Color get _deep =>
      _isLight ? syncLightBackgroundDeep : syncBackgroundDeep;
  Color get _border =>
      _isLight ? syncLightBorder : syncBorder;
  Color get _primary =>
      _isLight ? syncLightText : Colors.white;
  Color get _secondary =>
      _isLight ? syncLightTextSecondary : Colors.white70;
  Color get _iconColor =>
      _isLight ? syncLightTextSecondary : Colors.white70;
  int section = 0;
  bool showSavedNotice = false;
  Timer? savedNoticeTimer;
  Offset _dialogOffset = Offset.zero;

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

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Transform.translate(
          offset: _dialogOffset,
          child: Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 720,
            height: 500,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  _titleBar(context),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      children: [
                        SizedBox(width: 170, child: _sidebar()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _content()),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  _footer(context),
                ],
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  Widget _titleBar(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanUpdate: (details) {
        final size = MediaQuery.sizeOf(context);
        final maxX = ((size.width - 720) / 2).clamp(0.0, double.infinity);
        final maxY = ((size.height - 500) / 2).clamp(0.0, double.infinity);
        setState(() {
          _dialogOffset = Offset(
            (_dialogOffset.dx + details.delta.dx).clamp(-maxX, maxX).toDouble(),
            (_dialogOffset.dy + details.delta.dy).clamp(-maxY, maxY).toDouble(),
          );
        });
      },
      child: Container(
      color: _deep.withValues(alpha: _isLight ? 0.58 : 0.55),
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      child: Row(
        children: [
          const Icon(Icons.tune_rounded, color: syncAccent, size: 18),
          const SizedBox(width: 6),
          Text(
            controller.t('playerSettings'),
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close_rounded, size: 17),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sidebar() {
    final items = [
      (Icons.play_circle_outline_rounded, controller.t('playback')),
      (Icons.subtitles_rounded, controller.t('subtitles')),
      (Icons.video_settings_outlined, controller.t('videoImage')),
      (Icons.graphic_eq_rounded, controller.t('audio')),
      (Icons.tune_rounded, controller.t('advancedPlayer')),
    ];

    return Container(
      color: _deep.withValues(alpha: _isLight ? 0.48 : 0.35),
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(vertical: -4),
                  minLeadingWidth: 18,
                  horizontalTitleGap: 6,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  selected: section == i,
                  selectedTileColor: syncAccent.withValues(alpha: 0.15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                  leading: Icon(items[i].$1, size: 17),
                  title: Text(
                    items[i].$2,
                    style: TextStyle(fontSize: 11.5, color: _primary),
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
    final child = switch (section) {
      0 => _playback(),
      1 => _subtitles(),
      2 => _video(),
      3 => _audio(),
      _ => _advanced(),
    };

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: child,
      ),
    );
  }

  Widget _playback() {
    return _sectionShell(
      title: controller.t('playback'),
      icon: Icons.play_circle_outline_rounded,
      onReset: controller.resetPlaybackSettings,
      child: _card(
        children: [
          DropdownButtonFormField<int>(
            initialValue: controller.skipSeconds,
            style: TextStyle(fontSize: 11.5, color: _primary),
            decoration: _decoration(controller.t('skipInterval')),
            items: const [5, 10, 15, 30, 60]
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(
                      '$value ${controller.t('secondsShort')}',
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) controller.setSkipSeconds(value);
            },
          ),
          const SizedBox(height: 7),
          _compactSwitch(
            value: controller.autoReady,
            onChanged: controller.setAutoReady,
            title: controller.t('autoReady'),
          ),
          _compactSwitch(
            value: controller.timelinePreview,
            onChanged: controller.setTimelinePreview,
            title: controller.t('timelinePreview'),
          ),
        ],
      ),
    );
  }

  Widget _subtitles() {
    return _sectionShell(
      title: controller.t('subtitles'),
      icon: Icons.subtitles_rounded,
      onReset: controller.resetSubtitleSettings,
      child: _card(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: controller.subtitleFontFamily,
                  style: TextStyle(fontSize: 11.5, color: _primary),
                  decoration: _decoration(controller.t('subtitleFont')),
                  items: const [
                    DropdownMenuItem(
                      value: 'Segoe UI',
                      child: Text('Segoe UI'),
                    ),
                    DropdownMenuItem(
                      value: 'Arial',
                      child: Text('Arial'),
                    ),
                    DropdownMenuItem(
                      value: 'Verdana',
                      child: Text('Verdana'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setSubtitleFontFamily(value);
                  },
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 150,
                child: _numberSlider(
                  label: controller.t('subtitleSize'),
                  value: controller.subtitleFontSize,
                  min: 18,
                  max: 48,
                  divisions: 30,
                  suffix: '',
                  onChanged: controller.setSubtitleFontSize,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _colorChoice(
                  label: controller.t('subtitleTextColor'),
                  value: controller.subtitleTextColorValue,
                  choices: const [
                    0xFFFFFFFF,
                    0xFFFFF3A6,
                    0xFF9FE7FF,
                  ],
                  onChanged: controller.setSubtitleTextColorValue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _colorChoice(
                  label: controller.t('subtitleOutlineColor'),
                  value: controller.subtitleOutlineColorValue,
                  choices: const [
                    0xFF000000,
                    0xFF202020,
                    0xFF4A4A4A,
                  ],
                  onChanged: controller.setSubtitleOutlineColorValue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _numberSlider(
            label: controller.t('subtitleOutlineWidth'),
            value: controller.subtitleOutlineWidth,
            min: 0,
            max: 4,
            divisions: 8,
            suffix: ' px',
            onChanged: controller.setSubtitleOutlineWidth,
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: controller.subtitlePosition,
                  isDense: true,
                  menuMaxHeight: 120,
                  style: TextStyle(fontSize: 11, color: _primary),
                  decoration: _decoration(
                    controller.t('subtitlePosition'),
                  ).copyWith(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: 'top',
                      child: Text(controller.t('subtitlePositionTop')),
                    ),
                    DropdownMenuItem(
                      value: 'bottom',
                      child: Text(controller.t('subtitlePositionBottom')),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) controller.setSubtitlePosition(value);
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _numberSlider(
                  label: controller.t('subtitleVerticalOffset'),
                  value: controller.subtitleVerticalOffset,
                  min: -120,
                  max: 120,
                  divisions: 48,
                  suffix: ' px',
                  onChanged: controller.setSubtitleVerticalOffset,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 130,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _border),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isTop = controller.subtitlePosition == 'top';
                final baseAlignment =
                    isTop ? Alignment.topCenter : Alignment.bottomCenter;
                final maxShift = constraints.maxHeight * 0.34;
                final shift = (controller.subtitleVerticalOffset / 120.0) *
                    maxShift *
                    (isTop ? 1 : -1);

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Align(
                      alignment: baseAlignment,
                      child: Transform.translate(
                        offset: Offset(0, shift),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          child: Text(
                            controller.locale.languageCode == 'ru'
                                ? 'Пример субтитров'
                                : 'Subtitle preview',
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            style: TextStyle(
                              fontFamily: controller.subtitleFontFamily,
                              fontSize: controller.subtitleFontSize,
                              fontWeight: FontWeight.w700,
                              color: Color(
                                controller.subtitleTextColorValue,
                              ),
                              shadows: _outlineShadows(
                                Color(
                                  controller.subtitleOutlineColorValue,
                                ),
                                controller.subtitleOutlineWidth,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _video() {
    return _sectionShell(
      title: controller.t('videoImage'),
      icon: Icons.video_settings_outlined,
      onReset: controller.resetVideoSettings,
      child: _card(
        children: [
          _signedSlider(
            label: controller.t('brightness'),
            value: controller.videoBrightness,
            min: -1,
            max: 1,
            onChanged: controller.setVideoBrightness,
          ),
          _signedSlider(
            label: controller.t('contrast'),
            value: controller.videoContrast,
            min: -1,
            max: 1,
            onChanged: controller.setVideoContrast,
          ),
          _signedSlider(
            label: controller.t('saturation'),
            value: controller.videoSaturation,
            min: -1,
            max: 1,
            onChanged: controller.setVideoSaturation,
          ),
          _signedSlider(
            label: controller.t('hue'),
            value: controller.videoHue,
            min: -180,
            max: 180,
            divisions: 72,
            onChanged: controller.setVideoHue,
          ),
        ],
      ),
    );
  }

  Widget _audio() {
    return _sectionShell(
      title: controller.t('audio'),
      icon: Icons.graphic_eq_rounded,
      onReset: controller.resetAudioSettings,
      child: _card(
        children: [
          _numberSlider(
            label: controller.t('defaultVolume'),
            value: controller.defaultMovieVolume * 100,
            min: 0,
            max: 100,
            divisions: 20,
            suffix: '%',
            onChanged: (value) =>
                controller.setDefaultMovieVolume(value / 100),
          ),
          const SizedBox(height: 7),
          _compactSwitch(
            value: controller.rememberMovieVolume,
            onChanged: controller.setRememberMovieVolume,
            title: controller.t('rememberVolume'),
          ),
          _compactSwitch(
            value: controller.normalizeAudio,
            onChanged: controller.setNormalizeAudio,
            title: controller.t('normalizeAudio'),
          ),
        ],
      ),
    );
  }

  Widget _advanced() {
    return _sectionShell(
      title: controller.t('advancedPlayer'),
      icon: Icons.tune_rounded,
      onReset: controller.resetAdvancedPlayerSettings,
      child: _card(
        children: [
          _compactSwitch(
            value: controller.smoothScaling,
            onChanged: controller.setSmoothScaling,
            title: controller.t('smoothScaling'),
          ),
          _compactSwitch(
            value: controller.hideCursorFullscreen,
            onChanged: controller.setHideCursorFullscreen,
            title: controller.t('hideCursorFullscreen'),
          ),
          const SizedBox(height: 7),
          _numberSlider(
            label: controller.t('previewCache'),
            value: controller.previewCacheMb,
            min: 50,
            max: 500,
            divisions: 18,
            suffix: ' MB',
            onChanged: controller.setPreviewCacheMb,
          ),
        ],
      ),
    );
  }

  Widget _sectionShell({
    required String title,
    required IconData icon,
    required VoidCallback onReset,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: syncAccentSoft),
            const SizedBox(width: 7),
            Text(
              title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 6,
                ),
              ),
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt_rounded, size: 15),
              label: Text(
                controller.t('resetSection'),
                style: TextStyle(fontSize: 11, color: _primary),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _deep.withValues(alpha: _isLight ? 0.44 : 0.34),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _secondary),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
    );
  }

  Widget _numberSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 11.5)),
            ),
            Text(
              '${value.round()}$suffix',
              style: TextStyle(fontSize: 11, color: _secondary),
            ),
          ],
        ),
        _slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _signedSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    final shown = value.abs() < 0.005
        ? '0'
        : (value > 0 ? '+${value.toStringAsFixed(2)}' : value.toStringAsFixed(2));
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(fontSize: 11.5)),
          ),
          Expanded(
            child: _slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 58,
            child: Text(
              shown,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 11, color: _secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _slider({
    required double value,
    required double min,
    required double max,
    int? divisions,
    required ValueChanged<double> onChanged,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 9),
      ),
      child: Slider(
        value: value.clamp(min, max).toDouble(),
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }

  Widget _colorChoice({
    required String label,
    required int value,
    required List<int> choices,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11.5)),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final choice in choices)
              Padding(
                padding: const EdgeInsets.only(right: 7),
                child: InkWell(
                  borderRadius: BorderRadius.circular(7),
                  onTap: () => onChanged(choice),
                  child: Container(
                    width: 34,
                    height: 25,
                    decoration: BoxDecoration(
                      color: Color(choice),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: choice == value
                            ? syncAccent
                            : (_isLight ? syncLightBorder : Colors.white24),
                        width: choice == value ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  List<Shadow> _outlineShadows(Color color, double width) {
    if (width <= 0) return const [];
    final d = width.clamp(0.5, 4.0).toDouble();
    return [
      Shadow(offset: Offset(-d, -d), blurRadius: 0.5, color: color),
      Shadow(offset: Offset(d, -d), blurRadius: 0.5, color: color),
      Shadow(offset: Offset(-d, d), blurRadius: 0.5, color: color),
      Shadow(offset: Offset(d, d), blurRadius: 0.5, color: color),
    ];
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
            child: Text(title, style: const TextStyle(fontSize: 11.5)),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(!value),
              child: SizedBox(
                width: 36,
                height: 22,
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    width: 32,
                    height: 16,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: value
                          ? syncAccent.withValues(alpha: 0.10)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: value ? syncAccent : (_isLight ? syncLightTextSecondary : Colors.white38),
                        width: 1.2,
                      ),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 140),
                      curve: Curves.easeOut,
                      alignment:
                          value ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: value ? syncAccentSoft : (_isLight ? syncLightTextSecondary : Colors.white70),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
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
                      style: TextStyle(
                        fontSize: 11,
                        color: _secondary,
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
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 7,
              ),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              controller.t('cancel'),
              style: TextStyle(fontSize: 11.5, color: _primary),
            ),
          ),
          const SizedBox(width: 7),
          FilledButton(
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 7,
              ),
            ),
            onPressed: _showSavedNotice,
            child: Text(
              controller.t('save'),
              style: TextStyle(fontSize: 11.5, color: _primary),
            ),
          ),
        ],
      ),
    );
  }
}
