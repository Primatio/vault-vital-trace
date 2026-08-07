import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;

import '../models/session_summary.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class SessionDetailScreen extends ConsumerStatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.summary,
    this.justCompleted = false,
  });

  final SessionSummary summary;
  final bool justCompleted;

  @override
  ConsumerState<SessionDetailScreen> createState() =>
      _SessionDetailScreenState();
}

class _SessionDetailScreenState extends ConsumerState<SessionDetailScreen> {
  late SessionSummary _summary;
  Map<String, int> _files = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _summary = widget.summary;
    _load();
  }

  Future<void> _load() async {
    final storage = ref.read(sessionStorageProvider);
    final files = await storage.fileSizes(_summary.directoryPath);
    final refreshed =
        await storage.loadSessionSummary(Directory(_summary.directoryPath));
    if (!mounted) return;
    setState(() {
      _files = files;
      if (refreshed != null) _summary = refreshed;
      _loading = false;
    });
  }

  Future<void> _export() async {
    await ref
        .read(sessionStorageProvider)
        .shareSession(_summary.directoryPath);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete session?'),
        content: Text(
          'This permanently deletes ${_summary.metadata.folderName}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await ref
        .read(sessionsListProvider.notifier)
        .deleteSession(_summary.directoryPath);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String _fmtBytes(int? bytes) {
    if (bytes == null) return '—';
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final meta = _summary.metadata;
    final start =
        DateFormat('yyyy-MM-dd HH:mm:ss').format(meta.startUtc.toLocal());
    final end = meta.endUtc == null
        ? '—'
        : DateFormat('yyyy-MM-dd HH:mm:ss').format(meta.endUtc!.toLocal());
    final durationMs = meta.endMonotonicMs == null
        ? null
        : meta.endMonotonicMs! - meta.startMonotonicMs;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            tooltip: 'Export / Share',
            onPressed: _export,
            icon: const Icon(Icons.ios_share),
          ),
          IconButton(
            tooltip: 'Delete',
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.justCompleted) ...[
                  const StatusBanner(
                    message:
                        'Session saved on device. Export when ready — data stays local until you share it.',
                  ),
                  const SizedBox(height: 12),
                ],
                _HeaderCard(summary: _summary),
                const SizedBox(height: 16),
                const _SectionTitle('Metadata'),
                _InfoRow('Subject', meta.subjectId),
                _InfoRow('Session ID', meta.sessionId),
                _InfoRow('Status', _summary.displayStatus),
                _InfoRow('Start (local)', start),
                _InfoRow('End (local)', end),
                _InfoRow(
                  'Duration',
                  durationMs == null
                      ? '—'
                      : '${(durationMs / 1000).toStringAsFixed(1)} s',
                ),
                _InfoRow('Start monotonic (ms)', '${meta.startMonotonicMs}'),
                _InfoRow(
                  'End monotonic (ms)',
                  meta.endMonotonicMs?.toString() ?? '—',
                ),
                if (meta.notes != null && meta.notes!.isNotEmpty)
                  _InfoRow('Notes', meta.notes!),
                const SizedBox(height: 16),
                const _SectionTitle('Device'),
                _InfoRow('Phone', meta.deviceInfo.phoneModel),
                _InfoRow('OS', meta.deviceInfo.osVersion),
                _InfoRow(
                  'App',
                  '${meta.deviceInfo.appVersion} (${meta.deviceInfo.appBuild})',
                ),
                if (meta.polarDevice != null) ...[
                  _InfoRow('Polar ID', meta.polarDevice!.deviceId),
                  _InfoRow(
                    'Polar name',
                    meta.polarDevice!.name ?? '—',
                  ),
                  _InfoRow(
                    'Firmware',
                    meta.polarDevice!.firmware ?? '—',
                  ),
                  _InfoRow(
                    'Battery at session',
                    meta.polarDevice!.batteryLevel != null
                        ? '${meta.polarDevice!.batteryLevel}%'
                        : '—',
                  ),
                ],
                const SizedBox(height: 16),
                const _SectionTitle('Recording settings'),
                _InfoRow(
                  'Camera',
                  meta.recordingSettings.cameraLens,
                ),
                _InfoRow(
                  'Resolution',
                  meta.recordingSettings.width != null
                      ? '${meta.recordingSettings.width}×${meta.recordingSettings.height}'
                      : meta.recordingSettings.resolutionPreset,
                ),
                _InfoRow(
                  'Streams',
                  [
                    if (meta.recordingSettings.hrStream) 'HR',
                    if (meta.recordingSettings.rrStream) 'RR',
                    if (meta.recordingSettings.ecgStream) 'ECG',
                    if (meta.recordingSettings.accStream) 'ACC',
                  ].join(', '),
                ),
                _InfoRow(
                  'Face at start',
                  meta.faceDetectedAtStart ? 'yes' : 'no',
                ),
                const SizedBox(height: 16),
                const _SectionTitle('Files'),
                if (_files.isEmpty)
                  const Text(
                    'No files found',
                    style: TextStyle(color: AppColors.textSecondary),
                  )
                else
                  ..._files.entries.map(
                    (e) => _InfoRow(e.key, _fmtBytes(e.value)),
                  ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _export,
                  icon: const Icon(Icons.ios_share),
                  label: const Text('Export / Share session'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _delete,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete session'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: const BorderSide(color: AppColors.error),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  p.basename(_summary.directoryPath),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final ok = summary.isComplete;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ok ? AppColors.accent.withValues(alpha: 0.5) : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber_rounded,
            color: ok ? AppColors.connected : AppColors.warning,
            size: 32,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary.metadata.subjectId,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  ok
                      ? 'Complete — video + polar + metadata'
                      : 'Incomplete — missing files',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}
