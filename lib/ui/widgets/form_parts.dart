import 'package:flutter/material.dart';

import '../theme.dart';
import 'pressable.dart';

/// `.button` — square, inked, 12px.
class TextlogButton extends StatelessWidget {
  const TextlogButton(this.label, {super.key, this.onPressed, this.tone = ButtonTone.primary});

  final String label;
  final VoidCallback? onPressed;
  final ButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final enabled = onPressed != null;
    final background = switch (tone) {
      ButtonTone.primary => palette.buttonBg,
      ButtonTone.unfollow => palette.unfollowBg,
      ButtonTone.danger => palette.errorInk,
    };

    return Pressable(
      onTap: onPressed,
      builder: (context, pressed) => Container(
        padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space3),
        color: enabled
            ? (pressed ? Color.alphaBlend(palette.ink.withValues(alpha: 0.2), background) : background)
            : palette.disabledBg,
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: enabled ? palette.buttonInk : palette.disabledInk,
          ),
        ),
      ),
    );
  }
}

enum ButtonTone { primary, unfollow, danger }

/// `textarea` — panel background, hairline border, 13px/1.7.
class TextlogField extends StatelessWidget {
  const TextlogField({
    super.key,
    required this.controller,
    this.hint,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.autofocus = false,
    this.keyboardType,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String? hint;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final bool autofocus;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return TextField(
      controller: controller,
      autofocus: autofocus,
      autocorrect: false,
      keyboardType: keyboardType,
      minLines: minLines,
      maxLines: maxLines,
      maxLength: maxLength,
      onSubmitted: onSubmitted,
      style: theme.bodyMedium!.copyWith(height: 1.7),
      cursorColor: palette.accent,
      buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: palette.panel,
        hintText: hint,
        hintStyle: theme.bodyMedium!.copyWith(color: palette.muted),
        contentPadding: const EdgeInsets.all(13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: palette.soft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: palette.soft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.zero,
          borderSide: BorderSide(color: palette.accent, width: 2),
        ),
      ),
    );
  }
}

/// `.auth label` — an 11px muted caption above a field.
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: space2),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(color: context.palette.muted),
    ),
  );
}

/// `.formmessage` — the error strip the site puts above a form.
class FormMessage extends StatelessWidget {
  const FormMessage(this.message, {super.key});

  final String? message;

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: space3),
      child: Text(
        message!,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: palette.errorInk),
      ),
    );
  }
}
