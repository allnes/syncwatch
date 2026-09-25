import 'package:flutter/material.dart';

class CompactSelect<T> extends StatelessWidget {
  const CompactSelect({super.key, required this.value, required this.items, required this.onChanged, this.label, this.width, this.prefixIcon});
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? label;
  final double? width;
  final Widget? prefixIcon;

  @override
  Widget build(BuildContext context) {
    final menuWidth = width ?? 240;
    final child = MenuAnchor(
      alignmentOffset: const Offset(0, 2),
      style: MenuStyle(
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(vertical: 2)),
        visualDensity: VisualDensity.compact,
        maximumSize: WidgetStatePropertyAll(Size(menuWidth, 220)),
        minimumSize: WidgetStatePropertyAll(Size(menuWidth, 0)),
        fixedSize: WidgetStatePropertyAll(Size.fromWidth(menuWidth)),
      ),
      menuChildren: [
        for (final item in items)
          MenuItemButton(
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 30)),
              maximumSize: WidgetStatePropertyAll(Size(double.infinity, 30)),
              padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () => onChanged(item.$1),
            child: Row(children: [
              SizedBox(width: 12, child: item.$1 == value ? const Icon(Icons.circle, size: 6) : null),
              const SizedBox(width: 4),
              Expanded(child: Text(item.$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            ]),
          ),
      ],
      builder: (context, controller, child) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => controller.isOpen ? controller.close() : controller.open(),
        child: InputDecorator(
          isEmpty: false,
          isFocused: controller.isOpen,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: prefixIcon,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          child: Row(children: [
            Expanded(child: Text(items.firstWhere((item) => item.$1 == value).$2, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
            const SizedBox(width: 6),
            Icon(controller.isOpen ? Icons.arrow_drop_up_rounded : Icons.arrow_drop_down_rounded),
          ]),
        ),
      ),
    );
    return width == null ? child : SizedBox(width: width, child: child);
  }
}
