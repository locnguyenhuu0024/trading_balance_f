import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Centers form content at a readable width and adapts its outer padding.
class ResponsiveFormContent extends StatelessWidget {
  const ResponsiveFormContent({
    super.key,
    required this.child,
    this.maxWidth = 560,
    this.padding,
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final resolvedPadding =
        padding ??
        EdgeInsets.all(width < 600 ? AppTokens.space4 : AppTokens.space5);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: resolvedPadding, child: child),
      ),
    );
  }
}

/// Announces pending form work with a visible label and static progress mark.
class FormPendingStatus extends StatelessWidget {
  const FormPendingStatus({super.key, required this.label, this.linear = true});

  final String label;
  final bool linear;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: label,
      child: ExcludeSemantics(
        child: Row(
          children: [
            if (!linear) ...[
              FormProgressMark(size: 16),
              const SizedBox(width: AppTokens.space2),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label),
                  if (linear) ...[
                    const SizedBox(height: AppTokens.space2),
                    const FormPendingIndicator(),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class FormProgressMark extends StatelessWidget {
  const FormProgressMark({super.key, this.size = 18});

  final double size;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return Icon(
        Icons.more_horiz,
        size: size,
        color: Theme.of(context).colorScheme.primary,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: const CircularProgressIndicator(strokeWidth: 2),
    );
  }
}

class FormPendingIndicator extends StatelessWidget {
  const FormPendingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context)) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Icon(
          Icons.more_horiz,
          size: 16,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }
    return const LinearProgressIndicator(minHeight: 2);
  }
}

/// Keeps a submitting action disabled and gives its progress a spoken label.
class AsyncFormButton extends StatelessWidget {
  const AsyncFormButton({
    Key? key,
    required this.label,
    required this.busyLabel,
    required this.isBusy,
    required this.onPressed,
    this.icon,
    this.outlined = false,
  }) : buttonKey = key,
       super(key: null);

  final Key? buttonKey;
  final String label;
  final String busyLabel;
  final bool isBusy;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final currentLabel = isBusy ? busyLabel : label;
    final maxContentWidth = (MediaQuery.sizeOf(context).width - 64)
        .clamp(120.0, 420.0)
        .toDouble();
    Widget content(
      String text, {
      required bool showProgress,
      bool showIcon = false,
    }) => ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxContentWidth),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 18,
            child: showProgress
                ? FormProgressMark(size: 18)
                : showIcon && icon != null
                ? Icon(icon, size: 18)
                : null,
          ),
          const SizedBox(width: AppTokens.space2),
          Flexible(child: Text(text, softWrap: true)),
        ],
      ),
    );
    final child = Semantics(
      liveRegion: isBusy,
      label: currentLabel,
      child: ExcludeSemantics(
        child: IndexedStack(
          index: isBusy ? 1 : 0,
          alignment: Alignment.center,
          children: [
            content(label, showProgress: false, showIcon: true),
            content(busyLabel, showProgress: isBusy),
          ],
        ),
      ),
    );
    if (outlined) {
      return OutlinedButton(
        key: buttonKey,
        onPressed: isBusy ? null : onPressed,
        child: child,
      );
    }
    return FilledButton(
      key: buttonKey,
      onPressed: isBusy ? null : onPressed,
      child: child,
    );
  }
}
