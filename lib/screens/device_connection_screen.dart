import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/polar_service.dart';
import '../theme/app_theme.dart';
import '../widgets/status_widgets.dart';

class DeviceConnectionScreen extends ConsumerStatefulWidget {
  const DeviceConnectionScreen({super.key});

  @override
  ConsumerState<DeviceConnectionScreen> createState() =>
      _DeviceConnectionScreenState();
}

class _DeviceConnectionScreenState
    extends ConsumerState<DeviceConnectionScreen> {
  bool _scanning = false;

  @override
  void dispose() {
    // Don't stop scan if connected — only cancel scan subscription.
    ref.read(polarServiceProvider).stopScan();
    super.dispose();
  }

  Future<void> _toggleScan() async {
    final polar = ref.read(polarServiceProvider);
    if (_scanning) {
      await polar.stopScan();
      setState(() => _scanning = false);
      return;
    }
    setState(() => _scanning = true);
    await polar.startScan();
  }

  Future<void> _connect(PolarDeviceView device) async {
    final polar = ref.read(polarServiceProvider);
    await polar.stopScan();
    setState(() => _scanning = false);
    await polar.connect(device.deviceId);
  }

  @override
  Widget build(BuildContext context) {
    final polarAsync = ref.watch(polarStateProvider);
    final live = polarAsync.asData?.value ??
        ref.read(polarServiceProvider).state;

    // Keep local scan flag in sync when state changes.
    if (live.connectionState == PolarConnectionState.scanning && !_scanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _scanning = true);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Polar H10'),
        actions: [
          if (live.isConnected)
            TextButton(
              onPressed: () async {
                await ref.read(polarServiceProvider).disconnect();
              },
              child: const Text('Disconnect'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConnectionStatusChip(state: live),
          const SizedBox(height: 12),
          if (live.isConnected) ...[
            _ConnectedCard(state: live),
            const SizedBox(height: 16),
            const StatusBanner(
              message:
                  'HR (and ECG if available) stream while connected. Keep the strap moist and snug.',
            ),
          ] else ...[
            const StatusBanner(
              message:
                  'Put the Polar H10 on, wet the electrodes, and tap Scan. Select your device ID (printed on the strap).',
            ),
          ],
          if (live.errorMessage != null) ...[
            const SizedBox(height: 12),
            StatusBanner(
              message: live.errorMessage!,
              tone: BannerTone.error,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _toggleScan,
            icon: Icon(_scanning ? Icons.stop : Icons.bluetooth_searching),
            label: Text(_scanning ? 'Stop scan' : 'Scan for devices'),
          ),
          const SizedBox(height: 20),
          const Text(
            'Nearby devices',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 8),
          if (live.discoveredDevices.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No devices found yet.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            )
          else
            ...live.discoveredDevices.map((d) {
              final isH10 = d.name.toUpperCase().contains('H10');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isH10 ? AppColors.accent : AppColors.border,
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      d.name.isEmpty ? 'Polar device' : d.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      'ID ${d.deviceId} · RSSI ${d.rssi}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    trailing: live.deviceId == d.deviceId && live.isConnected
                        ? const Icon(Icons.check_circle,
                            color: AppColors.connected)
                        : TextButton(
                            onPressed: () => _connect(d),
                            child: const Text('Connect'),
                          ),
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _ConnectedCard extends StatelessWidget {
  const _ConnectedCard({required this.state});

  final PolarLiveState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            state.deviceName ?? 'Polar H10',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'ID ${state.deviceId}',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _Metric(
                label: 'HR',
                value: state.heartRate != null ? '${state.heartRate}' : '—',
                unit: 'bpm',
              ),
              _Metric(
                label: 'Battery',
                value: state.batteryLevel != null
                    ? '${state.batteryLevel}'
                    : '—',
                unit: '%',
              ),
              _Metric(
                label: 'Contact',
                value: state.contactStatus ? 'OK' : '—',
                unit: '',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _StreamTag('HR', state.hrStreaming),
              _StreamTag('RR', state.hrStreaming),
              _StreamTag('ECG', state.ecgStreaming),
              _StreamTag('ACC', state.accStreaming),
            ],
          ),
          if (state.firmware != null) ...[
            const SizedBox(height: 10),
            Text(
              'Firmware: ${state.firmware}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.unit,
  });

  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
            ),
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (unit.isNotEmpty)
                  TextSpan(
                    text: ' $unit',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
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

class _StreamTag extends StatelessWidget {
  const _StreamTag(this.label, this.active);

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.connected : AppColors.disconnected;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
