// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'dart:async';
import 'package:flutter/material.dart';

import 'package:yala/design/luci_design_system.dart';
import 'package:yala/l10n/app_localizations.dart';

/// A reusable, feature-agnostic loading view with rotating captions,
/// progress indicator, and optional skeleton placeholders.
class LuciLoadingView extends StatefulWidget {
  /// Optional caption overrides. If null or empty, uses global localized default captions.
  final List<String>? captions;

  /// Duration before rotating to the next caption. Defaults to 2 seconds.
  final Duration rotationInterval;

  /// Optional skeleton content rendered beneath the loading indicator and caption.
  final Widget? skeleton;

  /// Custom loading indicator widget. If null, a standard circular indicator is shown.
  final Widget? indicator;

  /// Optional title displayed above the loading indicator.
  final String? title;

  /// Outer padding for the loading view.
  final EdgeInsetsGeometry padding;

  const LuciLoadingView({
    super.key,
    this.captions,
    this.rotationInterval = const Duration(seconds: 2),
    this.skeleton,
    this.indicator,
    this.title,
    this.padding = const EdgeInsets.all(LuciSpacing.md),
  });

  /// Centralized source of default humorous loading captions.
  static List<String> defaultCaptions(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return [
      l10n?.loadingCaption1 ?? 'Checking if Earth is flat or round…',
      l10n?.loadingCaption2 ?? 'Asking the router nicely…',
      l10n?.loadingCaption3 ?? 'Negotiating with packets…',
      l10n?.loadingCaption4 ?? 'Counting queues. No, not the supermarket kind…',
      l10n?.loadingCaption5 ?? 'Convincing latency to calm down…',
      l10n?.loadingCaption6 ??
          'Checking whether everything is where it should be…',
      l10n?.loadingCaption7 ?? 'Waiting for the router to finish thinking…',
      l10n?.loadingCaption8 ?? 'Consulting the packet gods…',
    ];
  }

  @override
  State<LuciLoadingView> createState() => _LuciLoadingViewState();
}

class _LuciLoadingViewState extends State<LuciLoadingView> {
  Timer? _timer;
  int _currentIndex = 0;
  List<String> _effectiveCaptions = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCaptions();
  }

  @override
  void didUpdateWidget(covariant LuciLoadingView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.captions != oldWidget.captions ||
        widget.rotationInterval != oldWidget.rotationInterval) {
      _updateCaptions();
    }
  }

  void _updateCaptions() {
    final newCaptions = (widget.captions != null && widget.captions!.isNotEmpty)
        ? widget.captions!
        : LuciLoadingView.defaultCaptions(context);

    _effectiveCaptions = newCaptions;
    if (_effectiveCaptions.isEmpty) {
      _currentIndex = 0;
      _stopTimer();
      return;
    }

    if (_currentIndex >= _effectiveCaptions.length) {
      _currentIndex = 0;
    }

    if (_effectiveCaptions.length > 1) {
      _startTimer();
    } else {
      _stopTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(widget.rotationInterval, (_) {
      if (!mounted) return;
      if (_effectiveCaptions.isEmpty) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _effectiveCaptions.length;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopTimer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentCaption = _effectiveCaptions.isNotEmpty
        ? _effectiveCaptions[_currentIndex]
        : '';

    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.title != null) ...[
            Text(
              widget.title!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.sm),
          ],
          Center(
            child:
                widget.indicator ??
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
          ),
          const SizedBox(height: LuciSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  currentCaption,
                  key: ValueKey<int>(_currentIndex),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          if (widget.skeleton != null) ...[
            const SizedBox(height: LuciSpacing.md),
            widget.skeleton!,
          ],
        ],
      ),
    );
  }
}
