import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_colors.dart';

/// Small caption above a form field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

/// Date picker field. Lets the user go back in time, because warung owners
/// often record a purchase or an expense days after it happened.
class DateField extends StatelessWidget {
  const DateField({super.key, required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          final today = DateTime.now();
          final picked = await showDatePicker(
            context: context,
            initialDate: value,
            firstDate: DateTime(today.year - 1, today.month, today.day),
            lastDate: today,
          );
          if (picked != null) onChanged(picked);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('d MMM yyyy', 'id_ID').format(value),
                  style: theme.textTheme.bodyLarge,
                ),
              ),
              const Icon(LucideIcons.calendar, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// A field that looks like a dropdown and opens a picker when tapped.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.text,
    required this.onTap,
    this.placeholder = false,
  });

  final String text;
  final VoidCallback onTap;

  /// True when [text] is a hint rather than a chosen value.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: placeholder ? AppColors.inkMuted : AppColors.ink,
                  ),
                ),
              ),
              const Icon(LucideIcons.chevronDown, color: AppColors.inkMuted),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet with a searchable list. Returns the chosen item.
///
/// When [onAdd] is given, typing a name that is not in the list offers to
/// add it; [onAdd] creates the item and it is returned as the choice.
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T item) label,
  String Function(T item)? detail,
  String searchHint = 'Cari',
  T Function(String name)? onAdd,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: AppColors.cream,
    builder: (context) => _PickerSheet<T>(
      title: title,
      items: items,
      label: label,
      detail: detail,
      searchHint: searchHint,
      onAdd: onAdd,
    ),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.items,
    required this.label,
    required this.searchHint,
    this.detail,
    this.onAdd,
  });

  final String title;
  final List<T> items;
  final String Function(T item) label;
  final String Function(T item)? detail;
  final String searchHint;
  final T Function(String name)? onAdd;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final words = _query.toLowerCase().trim().split(RegExp(r'\s+'));
    final visible = widget.items.where((item) {
      final text = widget.label(item).toLowerCase();
      return words.every(text.contains);
    }).toList();

    final name = _query.trim();
    final canAdd =
        widget.onAdd != null &&
        name.isNotEmpty &&
        !widget.items.any(
          (item) => widget.label(item).toLowerCase() == name.toLowerCase(),
        );

    return Padding(
      // Keeps the list above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(widget.title, style: theme.textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                autofocus: widget.items.isEmpty,
                textCapitalization: TextCapitalization.words,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(LucideIcons.search),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  if (canAdd)
                    ListTile(
                      leading: const Icon(
                        LucideIcons.plus,
                        color: AppColors.green,
                      ),
                      title: Text(
                        'Tambah "$name"',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppColors.green,
                        ),
                      ),
                      onTap: () =>
                          Navigator.of(context).pop(widget.onAdd!(name)),
                    ),
                  for (final item in visible)
                    ListTile(
                      title: Text(
                        widget.label(item),
                        style: theme.textTheme.bodyLarge,
                      ),
                      subtitle: widget.detail == null
                          ? null
                          : Text(widget.detail!(item)),
                      onTap: () => Navigator.of(context).pop(item),
                    ),
                  if (visible.isEmpty && !canAdd)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.onAdd == null
                            ? 'Tidak ada yang cocok.'
                            : 'Ketik nama untuk menambah.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
