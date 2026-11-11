import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_ble/universal_ble.dart';
import 'package:miencoder/core/frame_parser.dart';
import 'package:miencoder/services/encoder.dart';

/// Encoder falso: se puede "apagar" y simular que el sistema avisa varias
/// veces seguidas de la desconexión (lo que provocaba el parpadeo).
class FakeBle implements BleBackend {
  bool poweredOn = true;
  int connectCalls = 0;
  final links = <StreamController<bool>>[];
  final values = <StreamController<Uint8List>>[];

  @override
  Future<void> connect(String id) async {
    connectCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    if (!poweredOn) {
      // Como en Android: un intento fallido también se anuncia como
      // "desconectado" a todos los que escuchan el enlace.
      for (final l in links) {
        if (l.hasListener) l.add(false);
      }
      throw Exception('GATT 133');
    }
  }

  @override
  Stream<bool> connectionStream(String id) {
    final c = StreamController<bool>.broadcast();
    links.add(c);
    return c.stream;
  }

  @override
  Stream<Uint8List> valueStream(String id) {
    final c = StreamController<Uint8List>.broadcast();
    values.add(c);
    return c.stream;
  }

  /// El sistema avisa [times] veces de que se cayó el enlace.
  void dropLink({int times = 1}) {
    poweredOn = false;
    for (var i = 0; i < times; i++) {
      links.last.add(false);
    }
  }

  void send(String frame) =>
      values.last.add(Uint8List.fromList(ascii.encode(frame)));

  @override
  Future<void> discoverServices(String id) async {}
  @override
  Future<void> subscribe(String id) async {}
  @override
  Future<void> disconnect(String id) async {}
  @override
  Future<void> requestPermissions() async {}
  @override
  Future<AvailabilityState> availability() async => AvailabilityState.poweredOn;
  @override
  Stream<BleDevice> get scanStream => const Stream.empty();
  @override
  Future<void> startScan() async {}
  @override
  Future<void> stopScan() async {}
  @override
  Future<BleDevice> requestDevice() => throw UnimplementedError();
}

const dev = FoundDevice('AA:BB', 'AdrEncoder5.3C', -50);

void main() {
  late FakeBle ble;
  late BleEncoderSource src;
  late List<EncoderStatus> history;

  setUp(() async {
    ble = FakeBle();
    src = BleEncoderSource(
      ble: ble,
      maxReconnectAttempts: 3,
      retryDelay: (_) => const Duration(milliseconds: 20),
    );
    await src.connect(dev);
    history = [src.status.value];
    src.status.addListener(() => history.add(src.status.value));
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 300));

  test('conecta normalmente', () {
    expect(src.status.value, EncoderStatus.connected);
    expect(ble.connectCalls, 1);
  });

  test(
    'encoder apagado + varios avisos seguidos: sin parpadeo y un solo bucle',
    () async {
      ble.dropLink(times: 6); // el sistema avisa muchas veces
      await settle();
      // Antes: connected → connecting → disconnected → connecting → … (parpadeo)
      expect(history, [
        EncoderStatus.connected,
        EncoderStatus.reconnecting,
        EncoderStatus.disconnected,
      ]);
      // 1 conexión inicial + 3 reintentos de UN solo bucle.
      expect(ble.connectCalls, 1 + 3);
      expect(src.error.value, contains('No se pudo recuperar'));
    },
  );

  test('si el encoder vuelve, se recupera y siguen llegando datos', () async {
    final frames = <EncoderFrame>[];
    src.frames.listen(frames.add);
    ble.dropLink(times: 3);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    ble.poweredOn = true; // se vuelve a encender antes del primer reintento
    await settle();
    expect(history, [
      EncoderStatus.connected,
      EncoderStatus.reconnecting,
      EncoderStatus.connected,
    ]);
    expect(ble.connectCalls, 2);
    ble.send('45.10 0.80 0.85 1.20');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(frames.single.meanPropulsiveVelocity, 0.85);
  });

  test('"Dejar de intentar" corta el bucle de inmediato', () async {
    ble.dropLink(times: 2);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await src.disconnect();
    final calls = ble.connectCalls;
    await settle();
    expect(ble.connectCalls, calls); // ningún reintento más
    expect(src.status.value, EncoderStatus.disconnected);
    expect(history.last, EncoderStatus.disconnected);
    expect(history.where((s) => s == EncoderStatus.reconnecting).length, 1);
  });

  test('una desconexión pedida por el usuario no intenta reconectar', () async {
    await src.disconnect();
    ble.poweredOn = false;
    await settle();
    expect(ble.connectCalls, 1);
    expect(history, [EncoderStatus.connected, EncoderStatus.disconnected]);
  });

  test(
    'tras una reconexión, una nueva caída vuelve a reintentar (una vez)',
    () async {
      ble.dropLink();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      ble.poweredOn = true;
      await settle();
      expect(src.status.value, EncoderStatus.connected);
      ble.dropLink(times: 4);
      await settle();
      expect(history, [
        EncoderStatus.connected,
        EncoderStatus.reconnecting,
        EncoderStatus.connected,
        EncoderStatus.reconnecting,
        EncoderStatus.disconnected,
      ]);
      expect(ble.connectCalls, 1 + 1 + 3);
    },
  );
}
