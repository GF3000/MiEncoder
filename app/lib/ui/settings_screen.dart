import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../app_controller.dart';
import '../core/models.dart';
import '../services/auth.dart';
import '../services/sync.dart';
import 'account_screen.dart';
import 'common.dart';
import 'value_sheets.dart';

class SettingsScreen extends StatelessWidget {
  final AppController c;
  final AuthService auth;
  final SyncService? sync;
  const SettingsScreen({
    super.key,
    required this.c,
    required this.auth,
    this.sync,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.settings;
        return Scaffold(
          appBar: AppBar(title: const Text('Ajustes')),
          body: ListView(
            children: [
              const _Header('Cuenta'),
              AccountTile(auth: auth, sync: sync),
              const _Header('Feedback'),
              ListTile(
                title: const Text('Velocidad de referencia'),
                subtitle: const Text(
                  'La que se muestra en grande y se usa para fatiga y perfil',
                ),
                trailing: SegmentedButton<VelocityMetric>(
                  segments: const [
                    ButtonSegment(
                      value: VelocityMetric.mpv,
                      label: Text('VMP'),
                    ),
                    ButtonSegment(value: VelocityMetric.mv, label: Text('VM')),
                  ],
                  selected: {s.metric},
                  onSelectionChanged: (v) =>
                      c.updateSettings(s.copyWith(metric: v.first)),
                ),
              ),
              SwitchListTile(
                title: const Text('Avisos de fatiga'),
                subtitle: Text(
                  s.fatigueEnabled
                      ? 'Colores, aviso y bocinazo según la pérdida de velocidad'
                      : 'Desactivados: sin colores, sin aviso y sin bocinazo',
                ),
                value: s.fatigueEnabled,
                onChanged: (v) =>
                    c.updateSettings(s.copyWith(fatigueEnabled: v)),
              ),
              ListTile(
                enabled: s.fatigueEnabled,
                title: Text(
                  'Bocinazo con pérdida ≥ ${s.velocityLossThreshold.round()} %',
                ),
                subtitle: Slider(
                  value: s.velocityLossThreshold,
                  min: 5,
                  max: 50,
                  divisions: 45,
                  label: '${s.velocityLossThreshold.round()} %',
                  onChanged: s.fatigueEnabled
                      ? (v) => c.updateSettings(
                          s.copyWith(velocityLossThreshold: v.roundToDouble()),
                        )
                      : null,
                ),
              ),
              SwitchListTile(
                title: const Text('Pitido en cada repetición'),
                subtitle: Text(
                  s.fatigueEnabled
                      ? 'El bocinazo de fatiga suena siempre'
                      : 'Único sonido mientras los avisos de fatiga están apagados',
                ),
                value: s.beepEachRep,
                onChanged: (v) => c.updateSettings(s.copyWith(beepEachRep: v)),
              ),
              SwitchListTile(
                title: const Text('Decir la velocidad en voz alta'),
                subtitle: const Text('Ej.: "85" para 0.85 m/s'),
                value: s.speakVelocity,
                onChanged: (v) =>
                    c.updateSettings(s.copyWith(speakVelocity: v)),
              ),
              SwitchListTile(
                title: const Text('Avisar si el ROM es corto'),
                subtitle: const Text(
                  'Dice "corta" (o pita) cuando una repetición baja menos de lo '
                  'habitual del deportista',
                ),
                value: s.romAlerts,
                onChanged: (v) => c.updateSettings(s.copyWith(romAlerts: v)),
              ),
              const _Header('Series'),
              const ListTile(
                dense: true,
                title: Text(
                  'Una serie termina al cambiar de deportista, carga o ejercicio, o con "Nueva serie". '
                  'Nunca por tiempo, así que los clusters cuentan como una sola serie.',
                ),
              ),
              ListTile(
                title: const Text('Salto de carga en los botones'),
                trailing: SegmentedButton<double>(
                  segments: const [
                    ButtonSegment(value: 1, label: Text('1')),
                    ButtonSegment(value: 2.5, label: Text('2.5')),
                    ButtonSegment(value: 5, label: Text('5')),
                  ],
                  selected: {s.loadStep},
                  onSelectionChanged: (v) =>
                      c.updateSettings(s.copyWith(loadStep: v.first)),
                ),
              ),
              const _Header('Ejercicios'),
              for (final e in c.exercises)
                ListTile(
                  title: Text(e.name),
                  subtitle: Text('Velocidad a 1RM (VMT): ${v2(e.mvt)} m/s'),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'mvt') {
                        final r = await showExerciseSheet(
                          context,
                          title: 'VMT de ${e.name}',
                          name: e.name,
                          mvt: e.mvt,
                          askName: false,
                        );
                        if (r != null) c.updateExercise(e.copyWith(mvt: r.mvt));
                      } else if (v == 'rename') {
                        final n = await askText(
                          context,
                          title: 'Renombrar ejercicio',
                          initial: e.name,
                        );
                        if (n != null && n.trim().isNotEmpty) {
                          c.updateExercise(e.copyWith(name: n.trim()));
                        }
                      } else if (v == 'delete') {
                        await _confirmDeleteExercise(context, c, e);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'mvt',
                        child: Text('Cambiar VMT'),
                      ),
                      const PopupMenuItem(
                        value: 'rename',
                        child: Text('Renombrar'),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        enabled: c.exercises.length > 1,
                        child: const Text(
                          'Borrar',
                          style: TextStyle(color: Colors.redAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Añadir ejercicio'),
                onTap: () async {
                  final r = await showExerciseSheet(
                    context,
                    title: 'Nuevo ejercicio',
                  );
                  if (r != null) c.addExercise(r.name, r.mvt);
                },
              ),
              const _Header('Datos'),
              ListTile(
                leading: const Icon(Icons.ios_share),
                title: const Text('Exportar todo a CSV'),
                subtitle: Text(
                  '${c.reps.length} repeticiones en ${c.sets.length} series',
                ),
                onTap: () {
                  final csv = c.exportCsv();
                  SharePlus.instance.share(
                    ShareParams(
                      files: [
                        XFile.fromData(
                          utf8.encode(csv),
                          mimeType: 'text/csv',
                          name: 'miencoder.csv',
                        ),
                      ],
                      fileNameOverrides: ['miencoder.csv'],
                    ),
                  );
                },
              ),
              const _Header('Pruebas'),
              SwitchListTile(
                title: const Text('Encoder simulado'),
                subtitle: const Text(
                  'Genera repeticiones falsas para probar la app sin el encoder',
                ),
                value: c.simulated,
                onChanged: c.useSimulator,
              ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Nota: con recorridos de 100 cm o más, el encoder envía la VMAX con un decimal menos '
                  '(limitación del firmware). Se marca con *.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
    child: Text(
      text,
      style: TextStyle(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

Future<void> _confirmDeleteExercise(
  BuildContext context,
  AppController c,
  Exercise e,
) async {
  final n = c.setsOfExercise(e.id);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('¿Borrar ${e.name}?'),
      content: Text(
        n == 0
            ? 'No tiene series registradas.'
            : 'Se borrarán también sus $n series y sus repeticiones. '
                  'No se puede deshacer.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Borrar'),
        ),
      ],
    ),
  );
  if (ok == true) await c.deleteExercise(e.id);
}
