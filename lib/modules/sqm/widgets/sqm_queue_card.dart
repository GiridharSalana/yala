// Copyright (C) 2026 @nightcodex7
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yala/design/luci_design_system.dart';
import 'package:yala/l10n/app_localizations.dart';
import 'package:yala/main.dart';
import 'package:yala/widgets/luci_toast.dart';
import '../models/sqm_overview.dart';
import '../models/sqm_preset.dart';
import '../models/sqm_queue.dart';
import 'sqm_flow_offloading_dialog.dart';

/// Card for editing and managing a specific SQM queue instance.
class SqmQueueCard extends ConsumerStatefulWidget {
  final SqmQueue queue;
  final SqmOverview? overview;
  final List<String> availableInterfaces;
  final List<String> availableQdiscs;
  final List<String> availableScripts;
  final bool hasFlowOffloading;
  final VoidCallback onSaved;
  final VoidCallback onDeleted;

  const SqmQueueCard({
    super.key,
    required this.queue,
    this.overview,
    required this.availableInterfaces,
    required this.availableQdiscs,
    required this.availableScripts,
    this.hasFlowOffloading = false,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  ConsumerState<SqmQueueCard> createState() => _SqmQueueCardState();
}

class _SqmQueueCardState extends ConsumerState<SqmQueueCard> {
  late bool _enabled;
  late String _selectedInterface;
  late String _selectedQdisc;
  late String _selectedScript;
  late String _selectedLinklayer;
  late TextEditingController _downloadController;
  late TextEditingController _uploadController;
  late TextEditingController _overheadController;

  bool _qdiscAdvanced = false;
  bool _squashDscp = true;
  bool _squashIngress = true;
  String _ingressEcn = 'ECN';
  String _egressEcn = 'NOECN';
  bool _debugLogging = false;
  int _verbosity = 5;

  bool _isSaving = false;
  bool _isDeleting = false;
  bool _showAdvanced = false;

  @override
  void initState() {
    super.initState();
    _initFromQueue(widget.queue);
  }

  @override
  void didUpdateWidget(covariant SqmQueueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue != widget.queue) {
      _initFromQueue(widget.queue);
    }
  }

  void _initFromQueue(SqmQueue q) {
    _enabled = q.enabled;
    _selectedInterface = q.interface;
    _selectedQdisc = q.qdisc;
    _selectedScript = q.script;
    _selectedLinklayer = q.linklayer;

    // Convert kbit/s to Mbps
    _downloadController = TextEditingController(
      text: q.download > 0 ? (q.download / 1000.0).toString() : '0',
    );
    _uploadController = TextEditingController(
      text: q.upload > 0 ? (q.upload / 1000.0).toString() : '0',
    );
    _overheadController = TextEditingController(text: q.overhead.toString());

    _qdiscAdvanced = q.qdiscAdvanced;
    _squashDscp = q.squashDscp;
    _squashIngress = q.squashIngress;
    _ingressEcn = q.ingressEcn;
    _egressEcn = q.egressEcn;
    _debugLogging = q.debugLogging;
    _verbosity = q.verbosity;
  }

  @override
  void dispose() {
    _downloadController.dispose();
    _uploadController.dispose();
    _overheadController.dispose();
    super.dispose();
  }

  Future<void> _saveQueue() async {
    if (_isSaving) return;

    if (_enabled && widget.hasFlowOffloading && !widget.queue.enabled) {
      final proceed = await showFlowOffloadingWarningDialog(context, ref: ref);
      if (proceed != true || !mounted) {
        return;
      }
    }

    if (!mounted) return;

    final double dlMbps =
        double.tryParse(_downloadController.text.trim()) ?? 0.0;
    final double ulMbps = double.tryParse(_uploadController.text.trim()) ?? 0.0;
    final int overhead = int.tryParse(_overheadController.text.trim()) ?? 0;

    if (_enabled && dlMbps <= 0 && ulMbps <= 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          actionsOverflowButtonSpacing: 8,
          actionsOverflowDirection: VerticalDirection.down,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: LuciStatusColors.warning,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Zero Bandwidth Configured',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
          content: const Text(
            'Both download and upload speeds are set to 0 Mbps. With zero bandwidth, SQM will not perform any traffic shaping or bufferbloat mitigation.\n\nDo you want to save anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save Anyway'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) {
        return;
      }
    }

    setState(() => _isSaving = true);

    final l10n = AppLocalizations.of(context);
    final appState = ref.read(appStateProvider);
    final actionKey = 'save_sqm_${widget.queue.name}';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmSavingQueueToast(widget.queue.name) ??
            'Saving SQM queue ${widget.queue.name}...',
        actionKey: actionKey,
      );
    }

    final updatedQueue = SqmQueue(
      name: widget.queue.name,
      enabled: _enabled,
      interface: _selectedInterface,
      download: (dlMbps * 1000).round(),
      upload: (ulMbps * 1000).round(),
      qdisc: _selectedQdisc,
      script: _selectedScript,
      linklayer: _selectedLinklayer,
      overhead: overhead,
      qdiscAdvanced: _qdiscAdvanced,
      squashDscp: _squashDscp,
      squashIngress: _squashIngress,
      ingressEcn: _ingressEcn,
      egressEcn: _egressEcn,
      debugLogging: _debugLogging,
      verbosity: _verbosity,
    );

    final success = await appState.saveSqmQueue(updatedQueue);

    if (mounted) {
      setState(() => _isSaving = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmQueueSavedToast ?? 'SQM configuration saved and applied.',
          actionKey: actionKey,
        );
        widget.onSaved();
      } else {
        context.showToastError(
          l10n?.modSqmQueueSaveFailedToast ??
              'Failed to save SQM configuration.',
          actionKey: actionKey,
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final l10n = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        actionsOverflowButtonSpacing: 8,
        actionsOverflowDirection: VerticalDirection.down,
        title: Text(
          l10n?.modSqmDeleteDialogTitle(widget.queue.name) ??
              'Delete Queue ${widget.queue.name}?',
        ),
        content: Text(
          l10n?.modSqmDeleteDialogContent ??
              'This will permanently delete this SQM queue instance configuration.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n?.actionCancel ?? 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n?.actionDelete ?? 'Delete'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    setState(() => _isDeleting = true);
    final appState = ref.read(appStateProvider);
    final actionKey = 'delete_sqm_${widget.queue.name}';

    if (mounted) {
      context.showToastLoading(
        l10n?.modSqmDeletingQueueToast ?? 'Deleting SQM queue...',
        actionKey: actionKey,
      );
    }

    final success = await appState.deleteSqmQueue(widget.queue.name);

    if (mounted) {
      setState(() => _isDeleting = false);
      if (success) {
        context.showToastSuccess(
          l10n?.modSqmQueueDeletedToast ?? 'SQM queue deleted.',
          actionKey: actionKey,
        );
        widget.onDeleted();
      } else {
        context.showToastError(
          l10n?.modSqmQueueDeleteFailedToast ?? 'Failed to delete SQM queue.',
          actionKey: actionKey,
        );
      }
    }
  }

  void _applyOverheadPreset(int overhead, String linklayer) {
    setState(() {
      _overheadController.text = overhead.toString();
      _selectedLinklayer = linklayer;
    });
  }

  void _applyPreset(SqmPreset preset) {
    setState(() {
      _selectedQdisc = preset.qdisc;
      _selectedScript = preset.script;
      _selectedLinklayer = preset.linklayer;
      _overheadController.text = preset.overhead.toString();
      _qdiscAdvanced = preset.qdiscAdvanced;
    });
  }

  void _scaleBandwidth(double factor) {
    final dl = double.tryParse(_downloadController.text.trim()) ?? 0.0;
    final ul = double.tryParse(_uploadController.text.trim()) ?? 0.0;
    if (dl > 0) {
      final newDl = dl * factor;
      _downloadController.text = newDl % 1 == 0
          ? newDl.toInt().toString()
          : newDl.toStringAsFixed(1);
    }
    if (ul > 0) {
      final newUl = ul * factor;
      _uploadController.text = newUl % 1 == 0
          ? newUl.toInt().toString()
          : newUl.toStringAsFixed(1);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    // Interface options ensuring selected interface is in the list
    final interfaces = Set<String>.from(widget.availableInterfaces);
    if (_selectedInterface.isNotEmpty) {
      interfaces.add(_selectedInterface);
    }
    final sortedInterfaces = interfaces.toList()..sort();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Queue header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _enabled
                        ? LuciColors.primary.withValues(alpha: 0.12)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.tune_rounded,
                    color: _enabled
                        ? LuciColors.primary
                        : LuciStatusColors.inactive,
                    size: 22,
                  ),
                ),
                const SizedBox(width: LuciSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.queue.displayName(
                                primaryWanInterface:
                                    widget.overview?.primaryWanInterface,
                              ),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (widget.queue.isDefaultTemplate) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Router Template',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        _enabled
                            ? (l10n?.modSqmQueueEnabled ??
                                  'Active & Shaping Traffic')
                            : (l10n?.modSqmQueueDisabled ?? 'Disabled'),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _enabled
                              ? LuciStatusColors.connected
                              : LuciStatusColors.inactive,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _enabled,
                  onChanged: (val) async {
                    if (val && widget.hasFlowOffloading) {
                      final proceed = await showFlowOffloadingWarningDialog(
                        context,
                        ref: ref,
                      );
                      if (proceed != true) {
                        return;
                      }
                    }
                    setState(() => _enabled = val);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  color: theme.colorScheme.error,
                  tooltip: l10n?.actionDelete ?? 'Delete Queue',
                  onPressed: _isDeleting ? null : _confirmDelete,
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),
            const Divider(height: 1),
            const SizedBox(height: LuciSpacing.md),

            // Connection Profile & Default Templates Selector
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'Connection Profile & Template',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Select an OpenWrt template optimized for your internet connection type:',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),

            // Presets Horizontal Selector Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: SqmPreset.presets.map((preset) {
                  final isSelected =
                      _selectedQdisc == preset.qdisc &&
                      _selectedScript == preset.script &&
                      _selectedLinklayer == preset.linklayer &&
                      (int.tryParse(_overheadController.text.trim()) ?? 0) ==
                          preset.overhead;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      selected: isSelected,
                      onSelected: (_) => _applyPreset(preset),
                      avatar: Icon(
                        preset.icon,
                        size: 15,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.primary,
                      ),
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            preset.title,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                            ),
                          ),
                          if (preset.badge != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.25)
                                    : theme.colorScheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                preset.badge!,
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? theme.colorScheme.onPrimary
                                      : theme.colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),

            // Active Preset Description Banner
            Builder(
              builder: (ctx) {
                final matched = SqmPreset.match(
                  SqmQueue(
                    name: widget.queue.name,
                    interface: _selectedInterface,
                    qdisc: _selectedQdisc,
                    script: _selectedScript,
                    linklayer: _selectedLinklayer,
                    overhead:
                        int.tryParse(_overheadController.text.trim()) ?? 0,
                  ),
                );

                if (matched != null) {
                  return Container(
                    margin: const EdgeInsets.only(top: 8, bottom: 4),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.5,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 15,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            matched.description,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),

            const SizedBox(height: LuciSpacing.md),

            // Interface dropdown
            Text(
              l10n?.modSqmInterfaceLabel ?? 'Network Interface',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: LuciSpacing.xs),
            DropdownButtonFormField<String>(
              initialValue: sortedInterfaces.contains(_selectedInterface)
                  ? _selectedInterface
                  : (sortedInterfaces.isNotEmpty
                        ? sortedInterfaces.first
                        : null),
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                isDense: true,
              ),
              items: sortedInterfaces.map((iface) {
                final label = widget.overview?.interfaceLabel(iface) ?? iface;
                return DropdownMenuItem<String>(
                  value: iface,
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                  ),
                );
              }).toList(),
              onChanged: (val) {
                if (val != null) setState(() => _selectedInterface = val);
              },
            ),

            const SizedBox(height: LuciSpacing.md),

            // Download & Upload Bandwidth Fields
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_downward_rounded,
                            size: 16,
                            color: LuciColors.rx,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.modSqmDownloadLabel ?? 'Download (Mbps)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _downloadController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: 'e.g. 100',
                          suffixText: 'Mbps',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.arrow_upward_rounded,
                            size: 16,
                            color: LuciColors.tx,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n?.modSqmUploadLabel ?? 'Upload (Mbps)',
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: _uploadController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d*'),
                          ),
                        ],
                        decoration: InputDecoration(
                          hintText: 'e.g. 20',
                          suffixText: 'Mbps',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          isDense: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'Quick Sweet-Spot:',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text(
                    '90% (Sweet Spot)',
                    style: TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _scaleBandwidth(0.90),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('85%', style: TextStyle(fontSize: 11)),
                  onPressed: () => _scaleBandwidth(0.85),
                ),
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  label: const Text('95%', style: TextStyle(fontSize: 11)),
                  onPressed: () => _scaleBandwidth(0.95),
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),

            // Queueing Discipline (qdisc) and Setup Script
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.modSqmQdiscLabel ?? 'Queue Discipline',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.availableQdiscs.contains(_selectedQdisc)
                            ? _selectedQdisc
                            : 'cake',
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        items: widget.availableQdiscs.map((qd) {
                          return DropdownMenuItem<String>(
                            value: qd,
                            child: Text(
                              qd,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() {
                              _selectedQdisc = val;
                              if (val == 'cake') {
                                _selectedScript = 'piece_of_cake.qos';
                              } else {
                                _selectedScript = 'simple.qos';
                              }
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: LuciSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n?.modSqmScriptLabel ?? 'Setup Script',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue:
                            widget.availableScripts.contains(_selectedScript)
                            ? _selectedScript
                            : (widget.availableScripts.isNotEmpty
                                  ? widget.availableScripts.first
                                  : 'piece_of_cake.qos'),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                          isDense: true,
                        ),
                        items: widget.availableScripts.map((sc) {
                          return DropdownMenuItem<String>(
                            value: sc,
                            child: Text(
                              sc.replaceAll('.qos', ''),
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedScript = val);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: LuciSpacing.md),

            // Link Layer Framing and Overhead Presets
            Text(
              l10n?.modSqmLinklayerLabel ?? 'Link Layer Framing & Overhead',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        ['none', 'ethernet', 'atm'].contains(_selectedLinklayer)
                        ? _selectedLinklayer
                        : 'none',
                    decoration: InputDecoration(
                      labelText: l10n?.modSqmFramingLabel ?? 'Framing',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'none',
                        child: Text('None (Fiber/LAN)'),
                      ),
                      DropdownMenuItem(
                        value: 'ethernet',
                        child: Text('Ethernet'),
                      ),
                      DropdownMenuItem(value: 'atm', child: Text('ATM (ADSL)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedLinklayer = val);
                    },
                  ),
                ),
                const SizedBox(width: LuciSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _overheadController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                    decoration: InputDecoration(
                      labelText: l10n?.modSqmOverheadLabel ?? 'Overhead',
                      suffixText: 'B',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Overhead Presets Quick Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    label: const Text(
                      'VDSL PPPoE (44B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(44, 'ethernet'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'Cable DOCSIS (34B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(34, 'ethernet'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'ADSL ATM (40B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(40, 'atm'),
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text(
                      'None (0B)',
                      style: TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _applyOverheadPreset(0, 'none'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: LuciSpacing.md),

            // Collapsible Advanced Settings
            InkWell(
              onTap: () => setState(() => _showAdvanced = !_showAdvanced),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      _showAdvanced
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_right_rounded,
                      size: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n?.modSqmAdvancedOptionsTitle ??
                          'Advanced Queue Options',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_showAdvanced) ...[
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  l10n?.modSqmQdiscAdvanced ?? 'Enable Advanced Qdisc Options',
                ),
                value: _qdiscAdvanced,
                onChanged: (val) => setState(() => _qdiscAdvanced = val),
              ),
              if (_qdiscAdvanced) ...[
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n?.modSqmSquashDscp ?? 'Squash DSCP Ingress/Egress',
                  ),
                  value: _squashDscp,
                  onChanged: (val) => setState(() => _squashDscp = val),
                ),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    l10n?.modSqmSquashIngress ?? 'Squash Ingress DSCP',
                  ),
                  value: _squashIngress,
                  onChanged: (val) => setState(() => _squashIngress = val),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _ingressEcn,
                        decoration: InputDecoration(
                          labelText: l10n?.modSqmIngressEcn ?? 'Ingress ECN',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 'ECN', child: Text('ECN')),
                          DropdownMenuItem(
                            value: 'NOECN',
                            child: Text('NOECN'),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _ingressEcn = val);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _egressEcn,
                        decoration: InputDecoration(
                          labelText: l10n?.modSqmEgressEcn ?? 'Egress ECN',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.all(8),
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'NOECN',
                            child: Text('NOECN'),
                          ),
                          DropdownMenuItem(value: 'ECN', child: Text('ECN')),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _egressEcn = val);
                        },
                      ),
                    ),
                  ],
                ),
              ],
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(l10n?.modSqmDebugLogging ?? 'Enable Debug Logging'),
                value: _debugLogging,
                onChanged: (val) => setState(() => _debugLogging = val),
              ),
              if (_debugLogging) ...[
                const SizedBox(height: 6),
                DropdownButtonFormField<int>(
                  initialValue: (_verbosity >= 0 && _verbosity <= 10)
                      ? _verbosity
                      : 5,
                  decoration: InputDecoration(
                    labelText: 'Verbosity Level (0-10)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    isDense: true,
                  ),
                  items: List.generate(11, (i) {
                    final label = i == 0
                        ? '0 (Silent)'
                        : i == 5
                        ? '5 (Default)'
                        : i == 8
                        ? '8 (Verbose)'
                        : i == 10
                        ? '10 (Trace)'
                        : '$i';
                    return DropdownMenuItem<int>(value: i, child: Text(label));
                  }),
                  onChanged: (val) {
                    if (val != null) setState(() => _verbosity = val);
                  },
                ),
              ],
            ],

            const SizedBox(height: LuciSpacing.lg),

            // Save and Apply Button
            SizedBox(
              width: double.infinity,
              height: 46,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveQueue,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_outline_rounded, size: 20),
                label: Text(
                  _isSaving
                      ? 'Saving...'
                      : (l10n?.actionSave ?? 'Save & Apply'),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
