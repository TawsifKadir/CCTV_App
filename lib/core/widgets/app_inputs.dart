import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/formatters.dart';
import '../utils/motion.dart';

/// Field label shown above inputs, with an optional "Optional" hint.
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label, {this.optional = false});
  final String label;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: Space.xs),
      child: Row(
        children: [
          Flexible(child: Text(label, style: t.labelMedium)),
          if (optional) ...[const SizedBox(width: 6), Text('Optional', style: t.labelSmall)],
        ],
      ),
    );
  }
}

/// Text field with label, rounded styling and an animated focus glow.
class AppTextField extends StatefulWidget {
  const AppTextField({
    super.key,
    required this.label,
    this.controller,
    this.hint,
    this.icon,
    this.validator,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.maxLines = 1,
    this.optional = false,
    this.obscure = false,
    this.suffix,
    this.onChanged,
    this.onSubmitted,
    this.inputFormatters,
    this.autofillHints,
    this.textCapitalization = TextCapitalization.none,
    this.readOnly = false,
    this.onTap,
    this.enabled = true,
    this.fieldKey,
  });

  final String label;
  final TextEditingController? controller;
  final String? hint;
  final IconData? icon;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final int maxLines;
  final bool optional;
  final bool obscure;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final List<TextInputFormatter>? inputFormatters;
  final Iterable<String>? autofillHints;
  final TextCapitalization textCapitalization;
  final bool readOnly;
  final VoidCallback? onTap;
  final bool enabled;
  final Key? fieldKey;

  @override
  State<AppTextField> createState() => _AppTextFieldState();
}

class _AppTextFieldState extends State<AppTextField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(widget.label, optional: widget.optional),
        AnimatedContainer(
          duration: context.motion(Motion.fast),
          decoration: BoxDecoration(
            borderRadius: Radii.mdAll,
            boxShadow: focused
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.16), blurRadius: 0, spreadRadius: 4)]
                : const [],
          ),
          child: TextFormField(
            key: widget.fieldKey,
            controller: widget.controller,
            focusNode: _focus,
            validator: widget.validator,
            keyboardType: widget.keyboardType,
            textInputAction: widget.maxLines > 1 ? TextInputAction.newline : widget.textInputAction,
            maxLines: widget.obscure ? 1 : widget.maxLines,
            minLines: widget.maxLines > 1 ? 2 : 1,
            obscureText: widget.obscure,
            onChanged: widget.onChanged,
            onFieldSubmitted: widget.onSubmitted,
            inputFormatters: widget.inputFormatters,
            autofillHints: widget.autofillHints,
            textCapitalization: widget.textCapitalization,
            readOnly: widget.readOnly,
            onTap: widget.onTap,
            enabled: widget.enabled,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: widget.hint,
              prefixIcon: widget.icon == null
                  ? null
                  : Icon(widget.icon, size: 20, color: focused ? AppColors.primary : null),
              suffixIcon: widget.suffix,
            ),
          ),
        ),
      ],
    );
  }
}

/// Password field with show/hide toggle.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    super.key,
    required this.label,
    required this.controller,
    this.validator,
    this.hint,
    this.textInputAction = TextInputAction.next,
    this.onSubmitted,
    this.autofillHints = const [AutofillHints.password],
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final String? Function(String?)? validator;
  final String? hint;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;
  final Key? fieldKey;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      fieldKey: widget.fieldKey,
      label: widget.label,
      controller: widget.controller,
      hint: widget.hint ?? 'Enter your password',
      icon: Icons.lock_outline_rounded,
      obscure: _hidden,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      onSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      suffix: IconButton(
        tooltip: _hidden ? 'Show password' : 'Hide password',
        icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    );
  }
}

/// Rounded dropdown with the same label treatment as [AppTextField].
class AppDropdownField<T> extends StatelessWidget {
  const AppDropdownField({
    super.key,
    required this.label,
    required this.items,
    required this.value,
    required this.onChanged,
    this.itemLabel,
    this.icon,
    this.validator,
    this.optional = false,
    this.hint,
  });

  final String label;
  final List<T> items;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String Function(T)? itemLabel;
  final IconData? icon;
  final String? Function(T?)? validator;
  final bool optional;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _FieldLabel(label, optional: optional),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          items: [
            for (final i in items)
              DropdownMenuItem<T>(
                value: i,
                child: Text(itemLabel?.call(i) ?? '$i', overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          borderRadius: Radii.mdAll,
          dropdownColor: context.palette.card,
          menuMaxHeight: 360,
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: hint ?? 'Select',
            prefixIcon: icon == null ? null : Icon(icon, size: 20),
          ),
        ),
      ],
    );
  }
}

/// Read-only field that opens a date picker.
class AppDateField extends StatelessWidget {
  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.validator,
    required this.firstDate,
    required this.lastDate,
    this.initialDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final String? Function(DateTime?)? validator;
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? initialDate;

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      validator: (_) => validator?.call(value),
      builder: (state) {
        Future<void> pick() async {
          final picked = await showDatePicker(
            context: context,
            initialDate: value ?? initialDate ?? DateTime(1990, 1, 1),
            firstDate: firstDate,
            lastDate: lastDate,
            initialEntryMode: DatePickerEntryMode.calendar,
            helpText: label.toUpperCase(),
          );
          if (picked != null) {
            onChanged(picked);
            state.didChange(picked);
          }
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FieldLabel(label),
            InkWell(
              borderRadius: Radii.mdAll,
              onTap: pick,
              child: InputDecorator(
                isEmpty: value == null,
                decoration: InputDecoration(
                  errorText: state.errorText,
                  hintText: 'Select a date',
                  prefixIcon: const Icon(Icons.calendar_today_outlined, size: 19),
                  suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded),
                ),
                child: Text(value == null ? '' : Fmt.date(value), style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Search input with a clear button.
class AppSearchBar extends StatefulWidget {
  const AppSearchBar({
    super.key,
    required this.onChanged,
    this.hint = 'Search',
    this.initialValue = '',
    this.controller,
    this.onSubmitted,
    this.fieldKey,
  });

  final ValueChanged<String> onChanged;
  final ValueChanged<String>? onSubmitted;
  final String hint;
  final String initialValue;

  /// Optional external controller (e.g. to clear the field programmatically).
  final TextEditingController? controller;
  final Key? fieldKey;

  @override
  State<AppSearchBar> createState() => _AppSearchBarState();
}

class _AppSearchBarState extends State<AppSearchBar> {
  TextEditingController? _own;
  TextEditingController get _controller =>
      widget.controller ?? (_own ??= TextEditingController(text: widget.initialValue));

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final pill = BorderRadius.circular(Radii.pill);
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        key: widget.fieldKey,
        controller: _controller,
        onChanged: widget.onChanged,
        onSubmitted: widget.onSubmitted,
        textInputAction: TextInputAction.search,
        style: Theme.of(context).textTheme.bodyLarge,
        decoration: InputDecoration(
          hintText: widget.hint,
          prefixIcon: const Icon(Icons.search_rounded, size: 22),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'Clear search',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () {
                    _controller.clear();
                    widget.onChanged('');
                    widget.onSubmitted?.call('');
                  },
                ),
          border: OutlineInputBorder(
            borderRadius: pill,
            borderSide: BorderSide(color: p.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: pill,
            borderSide: BorderSide(color: p.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: pill,
            borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 14),
        ),
      ),
    );
  }
}

/// Rounded checkbox row with tappable label.
class AppCheckboxTile extends StatelessWidget {
  const AppCheckboxTile({super.key, required this.value, required this.onChanged, required this.child, this.errorText});

  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: Radii.smAll,
          onTap: () => onChanged(!value),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 28,
                  height: 24,
                  child: Checkbox(
                    value: value,
                    onChanged: (v) => onChanged(v ?? false),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
                const SizedBox(width: Space.xs),
                Expanded(
                  child: Padding(padding: const EdgeInsets.only(top: 2), child: child),
                ),
              ],
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 2),
            child: Text(errorText!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.error)),
          ),
      ],
    );
  }
}
