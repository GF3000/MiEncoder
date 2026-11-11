import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'common.dart';

/// Decimales disponibles (discos fraccionales).
const kLoadDecimals = [0.0, 0.25, 0.5, 0.75];

/// Descompone una carga en (centenas, decenas, unidades, índice de decimal).
/// La parte decimal se redondea al cuarto de kilo más cercano.
(int, int, int, int) splitLoad(double kg) {
  final quarters = (kg.clamp(0, 499.75) * 4).round();
  final whole = quarters ~/ 4;
  return (whole ~/ 100, (whole ~/ 10) % 10, whole % 10, quarters % 4);
}

double joinLoad(int hundreds, int tens, int units, int decimalIndex) =>
    hundreds * 100 + tens * 10 + units + kLoadDecimals[decimalIndex];

String _decLabel(double d) => d == 0 ? ',00' : ',${(d * 100).round()}';

/// Hoja inferior con ruedas tipo reloj de alarma. Devuelve la carga elegida
/// o null si se cancela.
Future<double?> showLoadPicker(
  BuildContext context, {
  required double initial,
  String title = 'Carga',
}) {
  return showModalBottomSheet<double>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _LoadPicker(initial: initial, title: title),
  );
}

class _LoadPicker extends StatefulWidget {
  final double initial;
  final String title;
  const _LoadPicker({required this.initial, required this.title});

  @override
  State<_LoadPicker> createState() => _LoadPickerState();
}

class _LoadPickerState extends State<_LoadPicker> {
  late int h, t, u, d;
  late final FixedExtentScrollController ch, ct, cu, cd;

  @override
  void initState() {
    super.initState();
    final (h0, t0, u0, d0) = splitLoad(widget.initial);
    h = h0;
    t = t0;
    u = u0;
    d = d0;
    ch = FixedExtentScrollController(initialItem: h);
    // Ruedas circulares: arrancar en una vuelta intermedia para poder girar
    // en ambos sentidos desde el principio.
    ct = FixedExtentScrollController(initialItem: 1000 + t);
    cu = FixedExtentScrollController(initialItem: 1000 + u);
    cd = FixedExtentScrollController(initialItem: d);
  }

  @override
  void dispose() {
    for (final c in [ch, ct, cu, cd]) {
      c.dispose();
    }
    super.dispose();
  }

  double get value => joinLoad(h, t, u, d);

  Widget _wheel({
    required FixedExtentScrollController controller,
    required List<String> labels,
    required bool looping,
    required ValueChanged<int> onChanged,
    required String semantics,
    double width = 64,
  }) {
    return SizedBox(
      width: width,
      child: Semantics(
        label: semantics,
        child: CupertinoPicker(
          scrollController: controller,
          itemExtent: 52,
          looping: looping,
          squeeze: 1.1,
          diameterRatio: 1.3,
          selectionOverlay: const SizedBox.shrink(),
          onSelectedItemChanged: (i) =>
              setState(() => onChanged(i % labels.length)),
          children: [
            for (final l in labels)
              Center(
                child: Text(
                  l,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final digits = [for (var i = 0; i < 10; i++) '$i'];
    final screen = MediaQuery.sizeOf(context);
    // En horizontal la altura manda: ruedas a la izquierda, peso y botones a
    // la derecha, para que Aceptar/Cancelar siempre estén en pantalla.
    final landscape = screen.width > screen.height * 1.2;
    final wheelsH = landscape
        ? (screen.height - 110).clamp(156.0, 220.0)
        : 220.0;

    final title = Text(
      widget.title,
      style: Theme.of(context).textTheme.titleMedium,
    );
    final valueText = Text(
      '${kg(value)} kg',
      key: const Key('load-picker-value'),
      style: TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
    );
    final wheels = SizedBox(
      height: wheelsH,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Banda de selección común, como en el reloj.
          Container(
            height: 52,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _wheel(
                controller: ch,
                labels: const ['0', '1', '2', '3', '4'],
                looping: false,
                onChanged: (i) => h = i,
                semantics: 'centenas',
              ),
              _wheel(
                controller: ct,
                labels: digits,
                looping: true,
                onChanged: (i) => t = i,
                semantics: 'decenas',
              ),
              _wheel(
                controller: cu,
                labels: digits,
                looping: true,
                onChanged: (i) => u = i,
                semantics: 'unidades',
              ),
              _wheel(
                controller: cd,
                labels: [for (final x in kLoadDecimals) _decLabel(x)],
                looping: false,
                onChanged: (i) => d = i,
                semantics: 'decimales',
                width: 80,
              ),
              const Padding(
                padding: EdgeInsets.only(left: 6),
                child: Text(
                  'kg',
                  style: TextStyle(fontSize: 22, color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    final cancel = OutlinedButton(
      onPressed: () => Navigator.pop(context),
      child: const Text('Cancelar'),
    );
    final accept = FilledButton(
      onPressed: () => Navigator.pop(context, value),
      child: const Text('Aceptar'),
    );

    if (landscape) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              Expanded(child: Center(child: wheels)),
              const SizedBox(width: 16),
              SizedBox(
                width: 220,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(child: title),
                    const SizedBox(height: 4),
                    Center(child: valueText),
                    const SizedBox(height: 16),
                    accept,
                    const SizedBox(height: 8),
                    cancel,
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            title,
            const SizedBox(height: 4),
            valueText,
            const SizedBox(height: 8),
            wheels,
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: cancel),
                const SizedBox(width: 12),
                Expanded(child: accept),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
