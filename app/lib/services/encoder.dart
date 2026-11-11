import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:universal_ble/universal_ble.dart';

import '../core/frame_parser.dart';

/// UUIDs del encoder (ver adr/SPEC.md).
const String kEncoderService = 'ab0828b1-198e-4351-b779-901fa0e0371e';
const String kEncoderCharacteristic = '0972ef8c-7613-4075-ad52-756f33d4da91';
const String kEncoderNamePrefix = 'AdrEncoder';

enum EncoderStatus {
  disconnected,
  scanning,
  connecting,
  connected,

  /// Se perdió la conexión y se está reintentando solo.
  reconnecting,
}

class FoundDevice {
  final String id;
  final String name;
  final int? rssi;
  const FoundDevice(this.id, this.name, this.rssi);
}

/// Fuente de repeticiones. Hay una implementación real (BLE) y otra simulada
/// para probar la app sin el encoder.
abstract class EncoderSource {
  ValueListenable<EncoderStatus> get status;
  ValueListenable<String?> get deviceName;
  ValueListenable<String?> get error;
  Stream<EncoderFrame> get frames;
  Stream<List<FoundDevice>> get scanResults;

  Future<void> startScan();
  Future<void> stopScan();
  Future<void> connect(FoundDevice device);

  /// En web el navegador abre su propio selector de dispositivos.
  Future<void> connectViaPicker();
  Future<void> disconnect();
  void dispose();
}

/// Llamadas Bluetooth que usa [BleEncoderSource]. Separadas para poder
/// sustituirlas por un encoder falso en los tests.
abstract class BleBackend {
  Future<void> requestPermissions();
  Future<AvailabilityState> availability();
  Stream<BleDevice> get scanStream;
  Future<void> startScan();
  Future<void> stopScan();
  Future<BleDevice> requestDevice();
  Future<void> connect(String id);
  Future<void> discoverServices(String id);
  Stream<Uint8List> valueStream(String id);
  Future<void> subscribe(String id);
  Stream<bool> connectionStream(String id);
  Future<void> disconnect(String id);
}

class UniversalBleBackend implements BleBackend {
  const UniversalBleBackend();

  @override
  Future<void> requestPermissions() => UniversalBle.requestPermissions();
  @override
  Future<AvailabilityState> availability() =>
      UniversalBle.getBluetoothAvailabilityState();
  @override
  Stream<BleDevice> get scanStream => UniversalBle.scanStream;
  @override
  Future<void> startScan() => UniversalBle.startScan();
  @override
  Future<void> stopScan() => UniversalBle.stopScan();
  @override
  Future<BleDevice> requestDevice() => UniversalBle.requestDevice(
    scanFilter: ScanFilter(withNamePrefix: [kEncoderNamePrefix]),
    platformConfig: PickerPlatformConfig(
      web: WebOptions(optionalServices: [kEncoderService]),
    ),
  );
  @override
  Future<void> connect(String id) => UniversalBle.connect(
    id,
    timeout: const Duration(seconds: 15),
    platformConfig: ConnectionPlatformConfig(
      android: AndroidConnectionOptions(closeGattOnDetach: true),
    ),
  );
  @override
  Future<void> discoverServices(String id) async {
    await UniversalBle.discoverServices(id);
  }

  @override
  Stream<Uint8List> valueStream(String id) =>
      UniversalBle.characteristicValueStream(id, kEncoderCharacteristic);
  @override
  Future<void> subscribe(String id) => UniversalBle.subscribeNotifications(
    id,
    kEncoderService,
    kEncoderCharacteristic,
  );
  @override
  Stream<bool> connectionStream(String id) => UniversalBle.connectionStream(id);
  @override
  Future<void> disconnect(String id) => UniversalBle.disconnect(id);
}

/// Espera antes del intento [i] de reconexión (0, 1, 2…).
Duration defaultRetryDelay(int i) => Duration(seconds: 2 + i * 2);

class BleEncoderSource implements EncoderSource {
  final BleBackend ble;
  final int maxReconnectAttempts;
  final Duration Function(int attempt) retryDelay;

  BleEncoderSource({
    this.ble = const UniversalBleBackend(),
    this.maxReconnectAttempts = 5,
    this.retryDelay = defaultRetryDelay,
  });

  @override
  final ValueNotifier<EncoderStatus> status = ValueNotifier(
    EncoderStatus.disconnected,
  );
  @override
  final ValueNotifier<String?> deviceName = ValueNotifier(null);
  @override
  final ValueNotifier<String?> error = ValueNotifier(null);

  final _frames = StreamController<EncoderFrame>.broadcast();
  final _scan = StreamController<List<FoundDevice>>.broadcast();
  final Map<String, FoundDevice> _found = {};

  String? _deviceId;
  StreamSubscription<Uint8List>? _valueSub;
  StreamSubscription<bool>? _connSub;
  StreamSubscription<BleDevice>? _scanSub;

  /// Cambia cada vez que el usuario conecta o desconecta: invalida cualquier
  /// bucle de reconexión anterior.
  int _generation = 0;
  bool _reconnecting = false;

  /// Número de intentos de conexión realizados (para tests y diagnóstico).
  int connectAttempts = 0;

  @override
  Stream<EncoderFrame> get frames => _frames.stream;
  @override
  Stream<List<FoundDevice>> get scanResults => _scan.stream;

  @override
  Future<void> startScan() async {
    error.value = null;
    try {
      await ble.requestPermissions();
      final state = await ble.availability();
      if (state == AvailabilityState.poweredOff) {
        error.value = 'Activa el Bluetooth.';
        return;
      }
      _found.clear();
      _scan.add(const []);
      await _scanSub?.cancel();
      _scanSub = ble.scanStream.listen((d) {
        final name = d.name ?? '';
        if (!name.startsWith(kEncoderNamePrefix)) return;
        _found[d.deviceId] = FoundDevice(d.deviceId, name, d.rssi);
        _scan.add(_found.values.toList());
      });
      status.value = EncoderStatus.scanning;
      await ble.startScan();
      // Escaneo acotado para no gastar batería.
      Future.delayed(const Duration(seconds: 8), () {
        if (status.value == EncoderStatus.scanning) stopScan();
      });
    } catch (e) {
      error.value = 'No se pudo buscar: $e';
      status.value = EncoderStatus.disconnected;
    }
  }

  @override
  Future<void> stopScan() async {
    try {
      await ble.stopScan();
    } catch (_) {}
    await _scanSub?.cancel();
    _scanSub = null;
    if (status.value == EncoderStatus.scanning) {
      status.value = EncoderStatus.disconnected;
    }
  }

  @override
  Future<void> connectViaPicker() async {
    error.value = null;
    try {
      final d = await ble.requestDevice();
      await connect(
        FoundDevice(d.deviceId, d.name ?? kEncoderNamePrefix, d.rssi),
      );
    } catch (e) {
      error.value = 'No se seleccionó ningún encoder ($e)';
    }
  }

  /// Conexión iniciada por el usuario.
  @override
  Future<void> connect(FoundDevice device) async {
    await stopScan();
    final gen = ++_generation;
    _reconnecting = false;
    await _dropLink();
    error.value = null;
    status.value = EncoderStatus.connecting;
    try {
      await _connectOnce(device, gen);
      if (gen != _generation) return;
      status.value = EncoderStatus.connected;
    } catch (e) {
      if (gen != _generation) return;
      status.value = EncoderStatus.disconnected;
      error.value =
          'No se pudo conectar. ¿Está el encoder encendido y libre '
          '(sin otra app conectada)?';
    }
  }

  /// Un intento de conexión. No toca [status]: quien llama decide.
  Future<void> _connectOnce(FoundDevice device, int gen) async {
    connectAttempts++;
    await ble.connect(device.id);
    if (gen != _generation) return;
    await ble.discoverServices(device.id);
    await _valueSub?.cancel();
    _valueSub = ble.valueStream(device.id).listen(_onValue);
    await ble.subscribe(device.id);
    _deviceId = device.id;
    deviceName.value = device.name;
    await _connSub?.cancel();
    _connSub = ble.connectionStream(device.id).listen((connected) {
      if (!connected) _onLinkLost(device, gen);
    });
  }

  /// Deja de escuchar el enlace actual (sin cerrar nada en el dispositivo).
  Future<void> _dropLink() async {
    final v = _valueSub, c = _connSub;
    _valueSub = null;
    _connSub = null;
    await v?.cancel();
    await c?.cancel();
  }

  void _onValue(Uint8List bytes) {
    final f = parseFrameBytes(bytes);
    if (f != null) _frames.add(f);
  }

  /// Conexión perdida sin que el usuario lo pidiera: UN solo bucle de
  /// reintentos, con el estado fijo en "reconectando" mientras dura.
  Future<void> _onLinkLost(FoundDevice device, int gen) async {
    if (gen != _generation || _reconnecting) return;
    _reconnecting = true;
    await _dropLink();
    status.value = EncoderStatus.reconnecting;
    error.value = 'Conexión perdida. Reconectando…';
    try {
      for (var i = 0; i < maxReconnectAttempts; i++) {
        await Future.delayed(retryDelay(i));
        if (gen != _generation) return;
        try {
          await _connectOnce(device, gen);
          if (gen != _generation) return;
          status.value = EncoderStatus.connected;
          error.value = null;
          return;
        } catch (_) {
          await _dropLink();
        }
      }
      if (gen == _generation) {
        status.value = EncoderStatus.disconnected;
        error.value =
            'No se pudo recuperar la conexión. ¿Está el encoder encendido?';
      }
    } finally {
      if (gen == _generation) _reconnecting = false;
    }
  }

  @override
  Future<void> disconnect() async {
    _generation++;
    _reconnecting = false;
    final id = _deviceId;
    await _dropLink();
    if (id != null) {
      try {
        await ble.disconnect(id);
      } catch (_) {}
    }
    _deviceId = null;
    deviceName.value = null;
    error.value = null;
    status.value = EncoderStatus.disconnected;
  }

  @override
  void dispose() {
    disconnect();
    _frames.close();
    _scan.close();
  }
}

/// Encoder simulado: genera series realistas con pérdida de velocidad.
class SimulatedEncoderSource implements EncoderSource {
  @override
  final ValueNotifier<EncoderStatus> status = ValueNotifier(
    EncoderStatus.disconnected,
  );
  @override
  final ValueNotifier<String?> deviceName = ValueNotifier(null);
  @override
  final ValueNotifier<String?> error = ValueNotifier(null);

  final _frames = StreamController<EncoderFrame>.broadcast();
  final _scan = StreamController<List<FoundDevice>>.broadcast();
  final _rnd = math.Random();
  Timer? _timer;
  int _repInSet = 0;
  double _base = 1.0;

  @override
  Stream<EncoderFrame> get frames => _frames.stream;
  @override
  Stream<List<FoundDevice>> get scanResults => _scan.stream;

  @override
  Future<void> startScan() async {
    status.value = EncoderStatus.scanning;
    await Future.delayed(const Duration(milliseconds: 400));
    _scan.add(const [FoundDevice('sim', 'Encoder simulado', -40)]);
    status.value = EncoderStatus.disconnected;
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<void> connectViaPicker() =>
      connect(const FoundDevice('sim', 'Encoder simulado', -40));

  @override
  Future<void> connect(FoundDevice device) async {
    status.value = EncoderStatus.connected;
    deviceName.value = device.name;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    // Series de 4-8 reps cada ~3 s, con descansos de 25 s.
    final restNext = _repInSet >= 4 + _rnd.nextInt(5);
    final delay = restNext
        ? const Duration(seconds: 25)
        : Duration(milliseconds: 2500 + _rnd.nextInt(1500));
    if (restNext) {
      _repInSet = 0;
      _base = 0.6 + _rnd.nextDouble() * 0.7;
    }
    _timer = Timer(delay, () {
      emitRep();
      _schedule();
    });
  }

  /// Genera una repetición inmediatamente (también útil en pruebas).
  void emitRep() {
    final fatigue = 1 - _repInSet * 0.045;
    final mpv = (_base * fatigue + (_rnd.nextDouble() - 0.5) * 0.04).clamp(
      0.15,
      2.0,
    );
    final mv = mpv * (0.92 + _rnd.nextDouble() * 0.06);
    final vmax = mpv * (1.5 + _rnd.nextDouble() * 0.2);
    final rom = 45 + _rnd.nextDouble() * 15;
    _repInSet++;
    final text =
        '${rom.toStringAsFixed(2)} ${mv.toStringAsFixed(2)} '
        '${mpv.toStringAsFixed(2)} ${vmax.toStringAsFixed(2)}';
    final f = parseFrameText(text);
    if (f != null) _frames.add(f);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    status.value = EncoderStatus.disconnected;
    deviceName.value = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _frames.close();
    _scan.close();
  }
}
