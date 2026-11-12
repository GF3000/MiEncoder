<p align="center">
  <img src="app/assets/icon/icon-square.png" width="96" alt="Logo de MiEncoder">
</p>

# MiEncoder

App Android para medir la velocidad de ejecución en el entrenamiento de fuerza
con el encoder lineal **ADR** por Bluetooth. Pensada para entrenadores que
trabajan con varios deportistas a la vez, en móvil o tablet.

[Descargar la última versión (APK)](https://github.com/GF3000/MiEncoder/releases/latest)

## Funciones

- **Modo rápido**: cada repetición muestra recorrido, velocidad media (VM),
  velocidad media propulsiva (VMP) y velocidad máxima, con avisos sonoros y por
  voz.
- **Pérdida de velocidad**: corta la serie al superar el límite de fatiga
  elegido para la sesión, o sin límite.
- **Deportistas**: asigna cada repetición a un deportista y guarda su historial.
- **Sesiones** con convocatoria, objetivos de %1RM por ejercicio y consejo de
  carga.
- **Perfil carga-velocidad** con 1RM estimado por deportista y ejercicio.
- **Funciona sin conexión**: los datos se guardan en el dispositivo y, si inicias
  sesión (email o Google), se sincronizan con la nube cuando hay red.
- **Reconexión automática** del encoder si se pierde la señal.

## Instalación

1. Descarga `MiEncoder-x.y.z.apk` de la página de
   [releases](https://github.com/GF3000/MiEncoder/releases).
2. Ábrelo en el dispositivo Android y permite instalar apps de origen
   desconocido si te lo pide.
3. Enciende el encoder, abre la app y conéctalo desde el botón de Bluetooth.

> Si tenías instalada una versión anterior a la 1.1.0, desinstálala antes:
> cambió la clave de firma. Al desinstalar se borran los datos locales que no
> estén sincronizados.

## Compilar desde el código

Requiere [Flutter](https://flutter.dev) (Dart ≥ 3.12) y el SDK de Android.

```bash
cd app
flutter pub get
flutter test
flutter build apk --release
```

La firma de release se lee de `app/android/key.properties`, que no está en el
repositorio. Sin ese archivo el APK se firma con la clave de debug, y el inicio
de sesión con Google solo funcionará si su huella SHA-1 está registrada en el
proyecto de Firebase. Más detalles en [app/README.md](app/README.md).

## Estructura

| Carpeta | Contenido |
|---|---|
| [`app/`](app/) | App Flutter: parser de tramas, modelos, análisis, BLE, base de datos local, sincronización y pantallas. |
| [`adr/`](adr/) | [Especificación del protocolo BLE](adr/SPEC.md) del encoder y capturas de validación. |
## Protocolo del encoder

El encoder envía cada repetición como una notificación BLE de texto con el
formato `<ROM> <VM> <VMP> [<VMAX>]`; el canal es solo de salida. Todo el detalle
(UUIDs, formato, limitaciones del firmware) está en [adr/SPEC.md](adr/SPEC.md).

## Aviso

MiEncoder es un proyecto independiente. No está afiliado, patrocinado ni
respaldado por los fabricantes del encoder ADR. "ADR" y los nombres relacionados
pertenecen a sus respectivos titulares y se usan solo para indicar
compatibilidad.

## Licencia

[MIT](LICENSE)
