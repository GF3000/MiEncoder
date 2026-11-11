import 'dart:convert';

/// Una repetición tal y como la manda el encoder.
///
/// Formato observado (ver adr/SPEC.md): texto ASCII `ROM VM VMP [VMAX]`,
/// ROM en cm y velocidades en m/s. El firmware corta la trama a 20 bytes, así
/// que con ROM >= 100 cm la VMAX llega con un decimal de menos.
class EncoderFrame {
  final double romCm;
  final double meanVelocity; // VM, m/s
  final double meanPropulsiveVelocity; // VMP, m/s
  final double? peakVelocity; // VMAX, m/s (puede faltar)

  /// true si la trama llegó con 20 bytes y la VMAX probablemente está truncada.
  final bool peakTruncated;

  const EncoderFrame({
    required this.romCm,
    required this.meanVelocity,
    required this.meanPropulsiveVelocity,
    this.peakVelocity,
    this.peakTruncated = false,
  });

  @override
  String toString() =>
      'EncoderFrame(rom: $romCm, vm: $meanVelocity, vmp: $meanPropulsiveVelocity, '
      'vmax: $peakVelocity${peakTruncated ? ' (truncada)' : ''})';
}

/// Tamaño máximo de trama que envía el firmware.
const int kFirmwareFrameLimit = 20;

/// Convierte los bytes de una notificación en una [EncoderFrame].
/// Devuelve null si la trama no es válida (se descarta, como hace cualquier
/// cliente prudente).
EncoderFrame? parseFrameBytes(List<int> bytes) {
  if (bytes.isEmpty) return null;
  final String text;
  try {
    text = ascii.decode(bytes);
  } on FormatException {
    return null;
  }
  return parseFrameText(text, byteLength: bytes.length);
}

final RegExp _number = RegExp(r'^\d+(\.\d+)?$');

EncoderFrame? parseFrameText(String raw, {int? byteLength}) {
  // Si alguna vez llegan varias repeticiones separadas por comas, solo la
  // primera es fiable (comportamiento compatible con el cliente original).
  final first = raw.split(',').first.trim();
  if (first.isEmpty) return null;
  final parts = first.split(RegExp(r'\s+'));
  if (parts.length != 3 && parts.length != 4) return null;
  if (!parts.every(_number.hasMatch)) return null;

  final values = parts.map(double.parse).toList();
  final rom = values[0];
  final vm = values[1];
  final vmp = values[2];
  final vmax = values.length == 4 ? values[3] : null;

  // Límites de cordura físicos: descartar basura.
  if (rom <= 0 || rom > 400) return null;
  if (vm <= 0 || vm > 10 || vmp <= 0 || vmp > 10) return null;
  if (vmax != null && (vmax <= 0 || vmax > 15)) return null;

  final len = byteLength ?? raw.length;
  final truncated =
      vmax != null &&
      len >= kFirmwareFrameLimit &&
      parts.length == 4 &&
      !RegExp(r'\.\d\d$').hasMatch(parts[3]);

  return EncoderFrame(
    romCm: rom,
    meanVelocity: vm,
    meanPropulsiveVelocity: vmp,
    peakVelocity: vmax,
    peakTruncated: truncated,
  );
}
