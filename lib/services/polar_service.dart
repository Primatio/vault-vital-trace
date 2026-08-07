import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:polar/polar.dart';

import '../models/polar_sample.dart';
import '../utils/monotonic_clock.dart';

enum PolarConnectionState {
  disconnected,
  scanning,
  connecting,
  connected,
  streaming,
  error,
}

class PolarDeviceView {
  final String deviceId;
  final String name;
  final int rssi;
  final bool isConnectable;

  const PolarDeviceView({
    required this.deviceId,
    required this.name,
    required this.rssi,
    required this.isConnectable,
  });
}

class PolarLiveState {
  final PolarConnectionState connectionState;
  final String? deviceId;
  final String? deviceName;
  final int? batteryLevel;
  final String? firmware;
  final int? heartRate;
  final bool contactStatus;
  final bool hrStreaming;
  final bool ecgStreaming;
  final bool accStreaming;
  final String? errorMessage;
  final List<PolarDeviceView> discoveredDevices;

  const PolarLiveState({
    this.connectionState = PolarConnectionState.disconnected,
    this.deviceId,
    this.deviceName,
    this.batteryLevel,
    this.firmware,
    this.heartRate,
    this.contactStatus = false,
    this.hrStreaming = false,
    this.ecgStreaming = false,
    this.accStreaming = false,
    this.errorMessage,
    this.discoveredDevices = const [],
  });

  bool get isConnected =>
      connectionState == PolarConnectionState.connected ||
      connectionState == PolarConnectionState.streaming;

  bool get isStreaming =>
      connectionState == PolarConnectionState.streaming && hrStreaming;

  PolarLiveState copyWith({
    PolarConnectionState? connectionState,
    String? deviceId,
    String? deviceName,
    int? batteryLevel,
    String? firmware,
    int? heartRate,
    bool? contactStatus,
    bool? hrStreaming,
    bool? ecgStreaming,
    bool? accStreaming,
    String? errorMessage,
    List<PolarDeviceView>? discoveredDevices,
    bool clearError = false,
    bool clearDevice = false,
  }) {
    return PolarLiveState(
      connectionState: connectionState ?? this.connectionState,
      deviceId: clearDevice ? null : (deviceId ?? this.deviceId),
      deviceName: clearDevice ? null : (deviceName ?? this.deviceName),
      batteryLevel: clearDevice ? null : (batteryLevel ?? this.batteryLevel),
      firmware: clearDevice ? null : (firmware ?? this.firmware),
      heartRate: clearDevice ? null : (heartRate ?? this.heartRate),
      contactStatus: contactStatus ?? this.contactStatus,
      hrStreaming: hrStreaming ?? this.hrStreaming,
      ecgStreaming: ecgStreaming ?? this.ecgStreaming,
      accStreaming: accStreaming ?? this.accStreaming,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      discoveredDevices: discoveredDevices ?? this.discoveredDevices,
    );
  }
}

/// Manages Polar H10 BLE connection and sensor streams.
class PolarService {
  PolarService() {
    _polar = Polar();
    _bindLifecycleListeners();
  }

  late final Polar _polar;

  final _stateController = StreamController<PolarLiveState>.broadcast();
  PolarLiveState _state = const PolarLiveState();

  StreamSubscription<PolarDeviceInfo>? _scanSub;
  StreamSubscription<PolarHrData>? _hrSub;
  StreamSubscription<PolarEcgData>? _ecgSub;
  StreamSubscription<PolarAccData>? _accSub;
  final List<StreamSubscription<dynamic>> _lifecycleSubs = [];

  /// Buffer of samples collected while [isRecording] is true.
  final List<PolarSample> _recordingBuffer = [];
  bool _isRecording = false;
  int? _recordingStartMonotonicMs;

  PolarLiveState get state => _state;
  Stream<PolarLiveState> get stateStream async* {
    yield _state;
    yield* _stateController.stream;
  }
  List<PolarSample> get recordingBuffer =>
      List<PolarSample>.unmodifiable(_recordingBuffer);
  bool get isRecording => _isRecording;

  void _emit(PolarLiveState next) {
    _state = next;
    if (!_stateController.isClosed) {
      _stateController.add(next);
    }
  }

  void _bindLifecycleListeners() {
    _lifecycleSubs.addAll([
      _polar.deviceConnecting.listen((info) {
        _emit(
          _state.copyWith(
            connectionState: PolarConnectionState.connecting,
            deviceId: info.deviceId,
            deviceName: info.name,
            clearError: true,
          ),
        );
      }),
      _polar.deviceConnected.listen((info) async {
        _emit(
          _state.copyWith(
            connectionState: PolarConnectionState.connected,
            deviceId: info.deviceId,
            deviceName: info.name,
            clearError: true,
          ),
        );
        await _startStreams(info.deviceId);
      }),
      _polar.deviceDisconnected.listen((event) {
        _stopStreamSubs();
        _emit(
          _state.copyWith(
            connectionState: PolarConnectionState.disconnected,
            hrStreaming: false,
            ecgStreaming: false,
            accStreaming: false,
            heartRate: null,
            clearDevice: false,
            errorMessage: event.pairingError
                ? 'Pairing error — try reconnecting'
                : 'Device disconnected',
          ),
        );
      }),
      _polar.batteryLevel.listen((event) {
        if (event.identifier == _state.deviceId) {
          _emit(_state.copyWith(batteryLevel: event.level));
        }
      }),
      _polar.disInformation.listen((event) {
        if (event.identifier == _state.deviceId) {
          // Firmware typically arrives via DIS; keep last non-empty info.
          if (event.info.isNotEmpty) {
            _emit(_state.copyWith(firmware: event.info));
          }
        }
      }),
    ]);
  }

  Future<void> startScan() async {
    await stopScan();
    final found = <String, PolarDeviceView>{};

    _emit(
      _state.copyWith(
        connectionState: _state.isConnected
            ? _state.connectionState
            : PolarConnectionState.scanning,
        discoveredDevices: const [],
        clearError: true,
      ),
    );

    try {
      await _polar.requestPermissions();
      _scanSub = _polar.searchForDevice().listen(
        (info) {
          // Prefer Polar H10 but show all Polar devices.
          found[info.deviceId] = PolarDeviceView(
            deviceId: info.deviceId,
            name: info.name,
            rssi: info.rssi,
            isConnectable: info.isConnectable,
          );
          final devices = found.values.toList()
            ..sort((a, b) => b.rssi.compareTo(a.rssi));
          _emit(_state.copyWith(discoveredDevices: devices));
        },
        onError: (Object e) {
          _emit(
            _state.copyWith(
              connectionState: PolarConnectionState.error,
              errorMessage: 'Scan failed: $e',
            ),
          );
        },
      );
    } catch (e) {
      _emit(
        _state.copyWith(
          connectionState: PolarConnectionState.error,
          errorMessage: 'Unable to start scan: $e',
        ),
      );
    }
  }

  Future<void> stopScan() async {
    await _scanSub?.cancel();
    _scanSub = null;
    if (_state.connectionState == PolarConnectionState.scanning &&
        !_state.isConnected) {
      _emit(_state.copyWith(connectionState: PolarConnectionState.disconnected));
    }
  }

  Future<void> connect(String deviceId) async {
    await stopScan();
    _emit(
      _state.copyWith(
        connectionState: PolarConnectionState.connecting,
        deviceId: deviceId,
        clearError: true,
      ),
    );
    try {
      await _polar.connectToDevice(deviceId);
    } catch (e) {
      _emit(
        _state.copyWith(
          connectionState: PolarConnectionState.error,
          errorMessage: 'Connect failed: $e',
        ),
      );
    }
  }

  Future<void> disconnect() async {
    final id = _state.deviceId;
    _stopStreamSubs();
    if (id != null) {
      try {
        await _polar.disconnectFromDevice(id);
      } catch (e) {
        debugPrint('Disconnect error: $e');
      }
    }
    _emit(
      const PolarLiveState(connectionState: PolarConnectionState.disconnected),
    );
  }

  Future<void> _startStreams(String identifier) async {
    _stopStreamSubs();

    // Wait briefly for streaming feature readiness.
    try {
      await _polar.sdkFeatureReady
          .firstWhere(
            (e) =>
                e.identifier == identifier &&
                (e.feature == PolarSdkFeature.onlineStreaming ||
                    e.feature == PolarSdkFeature.hr),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      // Continue — some devices still stream HR without the feature event.
    }

    var hrOk = false;
    var ecgOk = false;
    var accOk = false;

    try {
      final hrTypes = await _polar.getAvailableHrServiceDataTypes(identifier);
      if (hrTypes.contains(PolarDataType.hr)) {
        _hrSub = _polar.startHrStreaming(identifier).listen(
          _onHrData,
          onError: (Object e) => debugPrint('HR stream error: $e'),
        );
        hrOk = true;
      }
    } catch (e) {
      debugPrint('HR service types error: $e');
    }

    try {
      await _polar.sdkFeatureReady
          .firstWhere(
            (e) =>
                e.identifier == identifier &&
                e.feature == PolarSdkFeature.onlineStreaming,
          )
          .timeout(const Duration(seconds: 8));
    } catch (_) {}

    try {
      final types =
          await _polar.getAvailableOnlineStreamDataTypes(identifier);

      if (!hrOk && types.contains(PolarDataType.hr)) {
        _hrSub = _polar.startHrStreaming(identifier).listen(
          _onHrData,
          onError: (Object e) => debugPrint('HR stream error: $e'),
        );
        hrOk = true;
      }

      if (types.contains(PolarDataType.ecg)) {
        _ecgSub = _polar.startEcgStreaming(identifier).listen(
          _onEcgData,
          onError: (Object e) => debugPrint('ECG stream error: $e'),
        );
        ecgOk = true;
      }

      if (types.contains(PolarDataType.acc)) {
        _accSub = _polar.startAccStreaming(identifier).listen(
          _onAccData,
          onError: (Object e) => debugPrint('ACC stream error: $e'),
        );
        accOk = true;
      }
    } catch (e) {
      debugPrint('Online stream types error: $e');
    }

    _emit(
      _state.copyWith(
        connectionState: hrOk
            ? PolarConnectionState.streaming
            : PolarConnectionState.connected,
        hrStreaming: hrOk,
        ecgStreaming: ecgOk,
        accStreaming: accOk,
        errorMessage: hrOk ? null : 'Connected but HR stream unavailable',
      ),
    );
  }

  void _onHrData(PolarHrData data) {
    for (final sample in data.samples) {
      _emit(
        _state.copyWith(
          heartRate: sample.hr,
          contactStatus: sample.contactStatus,
          connectionState: PolarConnectionState.streaming,
          hrStreaming: true,
        ),
      );

      if (!_isRecording || _recordingStartMonotonicMs == null) continue;

      final now = MonotonicClock.nowMs();
      final ts = now - _recordingStartMonotonicMs!;
      final utc = DateTime.now().toUtc();

      // One HR row per sample.
      _recordingBuffer.add(
        PolarSample(
          timestampMs: ts,
          utc: utc,
          hrBpm: sample.hr,
        ),
      );

      // RR intervals may include multiple values per HR packet.
      for (final rr in sample.rrsMs) {
        _recordingBuffer.add(
          PolarSample(
            timestampMs: ts,
            utc: utc,
            rrMs: rr,
            hrBpm: sample.hr,
          ),
        );
      }
    }
  }

  void _onEcgData(PolarEcgData data) {
    if (!_isRecording || _recordingStartMonotonicMs == null) return;
    final start = _recordingStartMonotonicMs!;
    for (final sample in data.samples) {
      final now = MonotonicClock.nowMs();
      _recordingBuffer.add(
        PolarSample(
          timestampMs: now - start,
          utc: DateTime.now().toUtc(),
          ecgUv: sample.voltage,
        ),
      );
    }
  }

  void _onAccData(PolarAccData data) {
    if (!_isRecording || _recordingStartMonotonicMs == null) return;
    final start = _recordingStartMonotonicMs!;
    for (final sample in data.samples) {
      final now = MonotonicClock.nowMs();
      _recordingBuffer.add(
        PolarSample(
          timestampMs: now - start,
          utc: DateTime.now().toUtc(),
          accX: sample.x,
          accY: sample.y,
          accZ: sample.z,
        ),
      );
    }
  }

  /// Begin buffering Polar samples with timestamps relative to [startMonotonicMs].
  void beginRecordingBuffer({required int startMonotonicMs}) {
    _recordingBuffer.clear();
    _recordingStartMonotonicMs = startMonotonicMs;
    _isRecording = true;
  }

  /// Stop buffering and return a copy of collected samples.
  List<PolarSample> endRecordingBuffer() {
    _isRecording = false;
    final copy = List<PolarSample>.from(_recordingBuffer);
    _recordingBuffer.clear();
    _recordingStartMonotonicMs = null;
    return copy;
  }

  void discardRecordingBuffer() {
    _isRecording = false;
    _recordingBuffer.clear();
    _recordingStartMonotonicMs = null;
  }

  void _stopStreamSubs() {
    _hrSub?.cancel();
    _ecgSub?.cancel();
    _accSub?.cancel();
    _hrSub = null;
    _ecgSub = null;
    _accSub = null;
  }

  Future<void> dispose() async {
    await stopScan();
    _stopStreamSubs();
    for (final sub in _lifecycleSubs) {
      await sub.cancel();
    }
    _lifecycleSubs.clear();
    await _stateController.close();
  }
}
