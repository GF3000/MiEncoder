# Protocolo BLE ADR ↔ App — SPEC

Fuente: APK `com.adr_encoder.adrencoder` v6.0.5 (versionCode 60005), extraído por adb del móvil del usuario.
Análisis estático, sin ejecutar la app. Cada afirmación está etiquetada:
**[O]** observado en el código · **[I]** inferencia · **[?]** desconocido.

## 1. Arquitectura de la app

- [O] App híbrida **Cordova**. La lógica es JavaScript plano (jQuery) en `assets/www/assets/js/`; no hay nada nativo propio.
- [O] BLE mediante el plugin `cordova-plugin-ble-central`.
- [O] Backend: Firebase (Auth + Firestore). Gráficas con Highcharts y tablas con DataTables.
- [O] Ficheros clave:
  - `app.js`: escaneo, conexión y parseo BLE (líneas ~351–518).
  - `entrenar.js` → `recibodato()`: consume los datos del encoder (~886).
  - `entrenarjumping.js` → `recibodato()`: consume los datos de la plataforma de saltos (~280).
  - `test.js`: test de carga-velocidad (~826).

## 2. Descubrimiento

- [O] `ble.scan([], 5 s)` sin filtro de servicio. La app filtra después por el **nombre anunciado**:

| Prefijo del nombre | Tipo |
|---|---|
| `AdrEncoder…` | encoder |
| `ADRJumping…`, `ADR_Jumping…` | jumping |
| `ADR…` (otros) | se listan como jumping, pero `onConnect` los rechaza |

## 3. GATT

| Dispositivo | Servicio | Característica | Modo |
|---|---|---|---|
| AdrEncoder | `ab0828b1-198e-4351-b779-901fa0e0371e` | `0972ef8c-7613-4075-ad52-756f33d4da91` | Notify |
| ADRJumping | `0000ffe0-0000-1000-8000-00805f9b34fb` | `0000ffe1-0000-1000-8000-00805f9b34fb` | Notify |
| ADR_Jumping | `FFE0` (forma corta del mismo) | `FFE1` | Notify |

- [O] **El canal es de un solo sentido: dispositivo → app.** No hay ninguna llamada `ble.write` ni `ble.read`, y la app nunca envía comandos (ni inicio, ni calibración, ni configuración).
- [I] FFE0/FFE1 es el perfil típico de los módulos UART serie (HM-10 y clones). La plataforma de saltos probablemente usa uno de ellos. El encoder usa UUIDs propios de 128 bits.

## 4. Formato de las tramas

- [O] Cada notificación se decodifica como **texto UTF-8**. No hay protocolo binario.
- [O] Los campos van separados por un espacio. La app valida el número de campos y descarta cualquier otra cosa.
- [O] `recibodato` hace `split(",")` y usa solo el primer bloque. [I] Es posible que una trama lleve varias repeticiones separadas por comas, pero las siguientes se ignoran.

### Encoder: 3 o 4 campos

```
<ROM> <VM> <VMP> [<VMAX>]
```

| Índice | Nombre interno | Significado | Unidad |
|---|---|---|---|
| 0 | `rom` | recorrido (range of motion) | [?] cm o mm |
| 1 | `vm` | velocidad media | [I] m/s |
| 2 | `vmp` | velocidad media propulsiva | [I] m/s |
| 3 | `vmax` | velocidad máxima (opcional) | [I] m/s |

- [O] Valores que calcula la app a partir de la trama:
  - potencia = carga(kg) × VM × 9.8
  - 1RM estimado: `calcularRM(carga, VM o VMP según ajuste, ejercicio)`
  - fatiga: velocidad / velocidad de referencia
- [O] Si una trama trae solo 3 campos, VMAX se muestra como "-".

### Plataforma de saltos: 2 campos

```
<ALTURA> <CONTACTO>
```

| Índice | Significado | Unidad |
|---|---|---|
| 0 | altura del salto | [O] cm (la interfaz muestra "cm") |
| 1 | tiempo de contacto | [I] ms (cuadra con RSI = altura·10/contacto) |

- [O] Valores que calcula la app:
  - tiempo de vuelo `tv = 100·sqrt((altura−1)·8/9.8)` [?] las unidades y el "−1" no están claros
  - RSI = altura·10/contacto

## 5. Validación con el dispositivo real (oráculo)

Capturado con nRF Connect el 2026-11-11 en un **AdrEncoder5.3C** (`94:54:C5:E6:E9:B2`).

- [O] El encoder anuncia el servicio `ab0828b1-…` en el advertising y se identifica como "LE only".
- [O] GATT: el servicio propio solo tiene **una característica**, `0972ef8c-…`, con la propiedad **NOTIFY** y un descriptor CCCD `0x2902`. **No hay ninguna característica escribible**: el canal es solo de salida.
- [O] Tramas reales:

| Movimiento | Hex | Texto |
|---|---|---|
| ~30 cm, normal | `32 37 2E 31 32 20 30 2E 33 37 20 30 2E 33 37 20 30 2E 36 32` | `27.12 0.37 0.37 0.62` |
| ~60 cm, rápido | `35 39 2E 32 37 20 31 2E 32 30 20 31 2E 32 37 20 31 2E 39 31` | `59.27 1.20 1.27 1.91` |
| >1 m | `31 34 32 2E 38 38 20 31 2E 31 32 20 31 2E 32 38 20 32 2E 30` | `142.88 1.12 1.28 2.0` ⚠️ **truncada** |

- [O] **Truncado a 20 bytes**: con ROM ≥ 100 cm la trama ocuparía 21 bytes. Llega cortada (VMAX `2.0` con un decimal en vez de dos) y no se envía ningún segundo fragmento. 20 = MTU por defecto (23) − 3.
- [I] La app oficial no llama a `ble.requestMtu` (no aparece en `app.js`), así que probablemente también recibe el VMAX truncado en repeticiones de más de 1 m.
- [O] El log de nRF Connect ([captura-nrf-2026-11-11.txt](captura-nrf-2026-11-11.txt)) no registra **ninguna negociación de MTU**, así que la sesión usó 23. Tras la trama truncada no llega ninguna notificación de continuación: el resto se pierde.
- [O] Las 5 tramas capturadas son coherentes. En las dos repeticiones rápidas VMP > VM (1.46 > 1.28 y 1.27 > 1.20); en las lentas, VM = VMP.
- [I] El prefijo MAC `94:54:C5` corresponde a **Espressif**, así que el encoder lleva probablemente un **ESP32**. Su pila BLE corta en silencio a MTU−3 cualquier notificación más larga, lo que encaja con lo observado.
- [O] **Prueba con MTU grande (14:59)**: se pide 247 y el encoder negocia **255** ("MTU changed to: 255"). La repetición siguiente llega igualmente con **20 bytes**: `31 35 37 2E 32 31 20 31 2E 31 39 20 31 2E 38 31 20 32 2E 38` → `"157.21 1.19 1.81 2.8"`. No llega ningún fragmento después.
- [O] **Conclusión: el truncado ocurre en el firmware, no en el enlace BLE.** El encoder limita la trama a 20 bytes sea cual sea el MTU.
- [O] Consecuencia: con ROM ≥ 100 cm, **VMAX pierde su segundo decimal** (se trunca, error de 0 a 0.09 m/s siempre hacia abajo). ROM, VM y VMP llegan completos. Ningún cliente puede recuperar el dato.
- [I] Causa probable: un búfer de 20 caracteres o un `setValue(buf, 20)` fijo en el firmware del ESP32. Solo lo puede corregir el fabricante.

- [O] Formato: ASCII, separador espacio, punto decimal, **2 decimales**, **sin terminador** (ni `\n` ni `\r`).
- [O] Una repetición por notificación (20 bytes en estos casos). No hay fragmentación con estos valores.
- [O] **ROM en cm**: los ~30 cm medidos dan 27.12.
- [O] Velocidades en m/s. En la repetición rápida VMP (1.27) > VM (1.20), como corresponde: la VMP excluye la fase de frenado. Confirma el orden `ROM VM VMP VMAX`.

## 6. Incógnitas restantes

- [?] Si alguna vez llegan varias repeticiones separadas por comas (la app lo contempla). No se ha observado.
- [?] Cuándo se envían tramas de 3 campos (sin VMAX). No se ha observado.
- [?] El emparejamiento (BONDED): no consta que el firmware exija cifrado para suscribirse.

## 7. Siguientes comprobaciones

1. ~~Repetición de más de 100 cm~~ → hecha: truncado en el firmware (ver §5).
2. Comparar con lo que muestra la app oficial en las mismas repeticiones (VM, VMP, ROM).
3. Fallos plantados: un parser propio debe **rechazar** una trama de 2 campos, una de 5 campos y una con texto no numérico.
