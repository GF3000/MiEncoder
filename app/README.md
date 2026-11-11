# MiEncoder - Compatible con ADR

App Flutter (Android, `gf3000.miencoder.app`) para medir velocidad de ejecución
con el encoder ADR por Bluetooth: modo rápido con feedback y fatiga, asignación
de repeticiones a deportistas, sesiones con convocatoria e historial, y perfil
carga-velocidad con 1RM estimado.

El protocolo del encoder está documentado en `../adr/SPEC.md`.

## Comandos

```bash
flutter test
```

```bash
flutter build apk --release
```

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Estructura

- `lib/core/`: parser de tramas, modelos y análisis (fatiga, perfil L-V).
- `lib/services/`: encoder BLE (con reconexión), base de datos sembast, sonidos.
- `lib/app_controller.dart`: lógica de series, deportistas y sesiones.
- `lib/ui/`: pantallas.

Nota: el archivo de datos se llama `velocoach.db` por razones históricas; no
cambiarlo o se pierden los datos guardados en los dispositivos.
