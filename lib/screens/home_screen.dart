import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../models/session_summary.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';
import 'device_connection_screen.dart';
import 'session_detail_screen.dart';
import 'session_setup_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(sessionsListProvider);
    final polarAsync = ref.watch(polarStateProvider);
    final polar = polarAsync.asData?.value ?? ref.read(polarServiceProvider).state;

    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Vault rPPG Collector'),
            Text(
              'Primatio R&D #001',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ConnectionStatusChip(state: polar, compact: true),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.read(sessionsListProvider.notifier).refresh(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
          children: [
            _QuickActions(
              polarConnected: polar.isStreaming,
              onConnect: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DeviceConnectionScreen(),
                  ),
                );
              },
              onNewSession: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SessionSetupScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Sessions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            sessionsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => StatusBanner(
                message: 'Failed to load sessions: $e',
                tone: BannerTone.error,
              ),
              data: (sessions) {
                if (sessions.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: StatusBanner(
                      message:
                          'No sessions yet. Connect a Polar H10 and start a 30-second recording.',
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final session in sessions)
                      _SessionTile(
                        session: session,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  SessionDetailScreen(summary: session),
                            ),
                          );
                          ref.read(sessionsListProvider.notifier).refresh();
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const SessionSetupScreen(),
            ),
          );
        },
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.fiber_manual_record),
        label: const Text('New Session'),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.polarConnected,
    required this.onConnect,
    required this.onNewSession,
  });

  final bool polarConnected;
  final VoidCallback onConnect;
  final VoidCallback onNewSession;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onConnect,
            icon: Icon(
              polarConnected ? Icons.bluetooth_connected : Icons.bluetooth,
            ),
            label: Text(polarConnected ? 'Polar' : 'Connect Polar'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: onNewSession,
            icon: const Icon(Icons.videocam),
            label: const Text('Record'),
          ),
        ),
      ],
    );
  }
}

class _SessionTile extends StatelessWidget {
  const _SessionTile({required this.session, required this.onTap});

  final SessionSummary session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final meta = session.metadata;
    final date = DateFormat('yyyy-MM-dd HH:mm').format(meta.startUtc.toLocal());
    final statusColor = switch (session.displayStatus) {
      'complete' => AppColors.connected,
      'cancelled' => AppColors.disconnected,
      _ => AppColors.warning,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    session.hasVideo ? Icons.videocam : Icons.videocam_off,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        meta.subjectId,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        [
                          if (session.hasVideo) 'video',
                          if (session.hasPolarData) 'polar',
                          if (session.hasMetadata) 'meta',
                        ].join(' · '),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    session.displayStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
