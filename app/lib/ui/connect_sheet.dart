import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../services/encoder.dart';

Future<void> showConnectSheet(BuildContext context, AppController c) async {
  final enc = c.encoder;
  // Mientras conecta o reconecta, tocar el chip permite cancelarlo.
  if (enc.status.value == EncoderStatus.reconnecting ||
      enc.status.value == EncoderStatus.connecting) {
    final reconnecting = enc.status.value == EncoderStatus.reconnecting;
    final stop = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(reconnecting ? 'Reconectando…' : 'Conectando…'),
        content: Text(
          reconnecting
              ? 'Se perdió la conexión con el encoder y se está intentando '
                    'recuperar. ¿Dejar de intentarlo?'
              : '¿Cancelar la conexión?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Seguir intentando'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Dejar de intentar'),
          ),
        ],
      ),
    );
    if (stop == true) await enc.disconnect();
    return;
  }
  if (enc.status.value == EncoderStatus.connected) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Conectado a ${enc.deviceName.value ?? 'encoder'}'),
        content: const Text('¿Desconectar el encoder?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
    if (ok == true) await enc.disconnect();
    return;
  }

  // En web el navegador tiene su propio selector.
  if (kIsWeb && !c.simulated) {
    await enc.connectViaPicker();
    return;
  }

  if (!context.mounted) return;
  enc.startScan();
  await showModalBottomSheet(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _ScanSheet(encoder: enc),
  );
  if (enc.status.value == EncoderStatus.scanning) enc.stopScan();
}

class _ScanSheet extends StatelessWidget {
  final EncoderSource encoder;
  const _ScanSheet({required this.encoder});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Encoders cercanos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Spacer(),
                ValueListenableBuilder(
                  valueListenable: encoder.status,
                  builder: (_, s, _) => s == EncoderStatus.scanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton.icon(
                          onPressed: encoder.startScan,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Buscar'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Cierra cualquier otra app conectada al encoder: solo admite una conexión.',
              style: TextStyle(color: Colors.white60, fontSize: 12),
            ),
            ValueListenableBuilder(
              valueListenable: encoder.error,
              builder: (_, e, _) => e == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        e,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            StreamBuilder<List<FoundDevice>>(
              stream: encoder.scanResults,
              initialData: const [],
              builder: (_, snap) {
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text('Buscando… enciende el encoder.'),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (final d in list)
                      ListTile(
                        leading: const Icon(Icons.speed),
                        title: Text(d.name),
                        subtitle: Text(
                          d.rssi == null ? d.id : '${d.id} · ${d.rssi} dBm',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.pop(context);
                          encoder.connect(d);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
