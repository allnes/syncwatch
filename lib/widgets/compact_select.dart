import 'package:flutter/material.dart';

import '../core/app_theme.dart';

class CompactSelect<T> extends StatefulWidget {
  const CompactSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.label,
    this.width,
    this.prefixIcon,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final double? width;
  final Widget? prefixIcon;

  @override
  State<CompactSelect<T>> createState() => _CompactSelectState<T>();
}

class _CompactSelectState<T> extends State<CompactSelect<T>> {
  final LayerLink _link = LayerLink();
  OverlayEntry? _entry;
  final GlobalKey _fieldKey = GlobalKey();

  @override
  void dispose() {
    _close();
    super.dispose();
  }

  void _close() {
    _entry?.remove();
    _entry = null;
  }

  void _toggle() {
    if (_entry != null) {
      _close();
      setState(() {});
      return;
    }
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final fieldSize = box.size;
    final overlay = Overlay.of(context);
    final isLight = Theme.of(context).brightness == Brightness.light;
    final surface = isLight ? syncLightSurfaceRaised : syncSurfaceRaised;
    final border = isLight ? syncLightBorder : syncBorder;
    final text = isLight ? syncLightText : Colors.white;

    _entry = OverlayEntry(
      builder: (overlayContext) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                _close();
                if (mounted) setState(() {});
              },
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: const Offset(0, 2),
            child: Material(
              elevation: 10,
              color: surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
                side: BorderSide(color: border),
              ),
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                width: fieldSize.width,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 190),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final item in widget.items)
                          InkWell(
                            onTap: () {
                              widget.onChanged(item.$1);
                              _close();
                              if (mounted) setState(() {});
                            },
                            child: SizedBox(
                              height: 30,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 12,
                                      child: item.$1 == widget.value
                                          ? const Icon(Icons.circle, size: 6, color: syncAccent)
                                          : null,
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        item.$2,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontSize: 13, color: text),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final selected = widget.items.firstWhere((item) => item.$1 == widget.value).$2;
    final field = CompositedTransformTarget(
      link: _link,
      child: InkWell(
        key: _fieldKey,
        borderRadius: BorderRadius.circular(12),
        onTap: _toggle,
        child: InputDecorator(
          isEmpty: false,
          isFocused: _entry != null,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: widget.prefixIcon,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selected,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 6),
              Icon(_entry != null ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded),
            ],
          ),
        ),
      ),
    );
    return widget.width == null
        ? field
        : SizedBox(width: widget.width, child: field);
  }
}
