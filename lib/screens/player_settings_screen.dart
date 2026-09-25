import 'package:flutter/material.dart';

import '../app.dart';
import '../core/app_theme.dart';

class PlayerSettingsScreen extends StatelessWidget {
  const PlayerSettingsScreen({
    super.key,
    required this.controller,
  });

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: SizedBox(
            width: 440,
            height: 390,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  _titleBar(context),
                  const Divider(height: 1),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionTitle(
                            controller.t('playback'),
                            Icons.play_circle_outline_rounded,
                          ),
                          const SizedBox(height: 7),
                          _card(
                            children: [
                              DropdownButtonFormField<int>(
                                initialValue: controller.skipSeconds,
                                style: const TextStyle(fontSize: 11.5),
                                decoration: _decoration(
                                  controller.t('skipInterval'),
                                ),
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
                                  if (value != null) {
                                    controller.setSkipSeconds(value);
                                  }
                                },
                              ),
                              const SizedBox(height: 6),
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
                          const SizedBox(height: 12),
                          _sectionTitle(
                            controller.t('subtitles'),
                            Icons.subtitles_rounded,
                          ),
                          const SizedBox(height: 7),
                          _card(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      controller.t('subtitleSize'),
                                      style: const TextStyle(fontSize: 11.5),
                                    ),
                                  ),
                                  Text(
                                    controller.subtitleFontSize
                                        .round()
                                        .toString(),
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ],
                              ),
                              SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 2,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 5,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 9,
                                  ),
                                ),
                                child: Slider(
                                  value: controller.subtitleFontSize,
                                  min: 18,
                                  max: 48,
                                  divisions: 30,
                                  onChanged: controller.setSubtitleFontSize,
                                ),
                              ),
                              const SizedBox(height: 3),
                              DropdownButtonFormField<String>(
                                initialValue: controller.subtitlePosition,
                                style: const TextStyle(fontSize: 11.5),
                                decoration: _decoration(
                                  controller.t('subtitlePosition'),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'top',
                                    child: Text(
                                      controller.t('subtitlePositionTop'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'higher',
                                    child: Text(
                                      controller.t('subtitlePositionHigher'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'normal',
                                    child: Text(
                                      controller.t('subtitlePositionNormal'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'lower',
                                    child: Text(
                                      controller.t('subtitlePositionLower'),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'bottom',
                                    child: Text(
                                      controller.t('subtitlePositionBottom'),
                                    ),
                                  ),
                                ],
                                onChanged: (value) {
                                  if (value != null) {
                                    controller.setSubtitlePosition(value);
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 7),
                    child: Row(
                      children: [
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            controller.t('save'),
                            style: const TextStyle(fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _titleBar(BuildContext context) {
    return Container(
      color: syncBackgroundDeep.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
      child: Row(
        children: [
          const Icon(
            Icons.tune_rounded,
            color: syncAccent,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            'SyncWatch · ${controller.t('playerSettings')}',
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
    );
  }

  Widget _sectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: syncAccentSoft),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _card({required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(9),
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

  InputDecoration _decoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
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
                        color: value ? syncAccent : Colors.white38,
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
                          color: value ? syncAccentSoft : Colors.white70,
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
}
