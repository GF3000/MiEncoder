import 'package:flutter/material.dart';

import '../core/models.dart';
import 'common.dart';

/// Deportistas que caben en el carrusel del perfil (como mucho [max]):
/// primero los de la sesión activa, luego los vistos hace poco y, si queda
/// sitio, el resto en su orden. El elegido siempre está.
List<Player> carouselPlayers({
  required List<Player> all,
  required List<String> session,
  required List<String> recent,
  required String selected,
  int max = 8,
}) {
  final byId = {for (final p in all) p.id: p};
  final ids = <String>[];
  void add(String id) {
    if (ids.length < max && byId.containsKey(id) && !ids.contains(id)) {
      ids.add(id);
    }
  }

  session.forEach(add);
  recent.forEach(add);
  for (final p in all) {
    add(p.id);
  }
  if (byId.containsKey(selected) && !ids.contains(selected)) {
    if (ids.length >= max) ids.removeLast();
    ids.insert(0, selected);
  }
  return [for (final id in ids) byId[id]!];
}

/// "Gonzalo Fernández" → "GF"; "Nica" → "NI".
String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  final t = parts.length >= 2
      ? '${parts[0].characters.first}${parts[1].characters.first}'
      : name.trim().characters.take(2).toString();
  return t.toUpperCase();
}

/// Pestañas subrayadas (ejercicios): distintas a propósito de las pastillas
/// de deportistas para no confundir los dos selectores.
class UnderlineTabs<T> extends StatelessWidget {
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelect;
  const UnderlineTabs({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final (value, label) in items)
            InkWell(
              onTap: () => onSelect(value),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: value == selected ? primary : Colors.transparent,
                      width: 3,
                    ),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 15,
                    color: value == selected ? Colors.white : Colors.white54,
                    fontWeight: value == selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pastilla seleccionable (deportista, ejercicio, periodo…).
class Pill extends StatelessWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool dashed;

  /// Iniciales en un círculo a la izquierda (deportistas).
  final String? avatar;

  const Pill({
    super.key,
    required this.label,
    this.selected = false,
    this.icon,
    this.onTap,
    this.dashed = false,
    this.avatar,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? scheme.onPrimaryContainer : Colors.white70;
    return Material(
      color: selected ? scheme.primaryContainer : Colors.white10,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? scheme.primary
              : (dashed ? Colors.white24 : Colors.transparent),
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(avatar != null ? 4 : 14, 4, 14, 4),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 28),
              if (avatar != null) ...[
                CircleAvatar(
                  radius: 14,
                  backgroundColor: selected ? scheme.primary : Colors.white24,
                  child: Text(
                    avatar!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              if (icon != null) ...[
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fila desplazable de pastillas con separación uniforme.
class PillRow extends StatelessWidget {
  final List<Widget> children;
  const PillRow({super.key, required this.children});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 40,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      itemCount: children.length,
      separatorBuilder: (_, _) => const SizedBox(width: 8),
      itemBuilder: (_, i) => Center(child: children[i]),
    ),
  );
}

/// Una fila de la hoja de búsqueda.
class PickerEntry {
  final Player player;

  /// Contexto: último día con datos, 1RM…
  final String? subtitle;

  /// false = atenuado (sin datos en el ejercicio elegido), pero se puede
  /// elegir igualmente.
  final bool highlighted;

  /// En la sesión activa.
  final bool inSession;

  const PickerEntry(
    this.player, {
    this.subtitle,
    this.highlighted = true,
    this.inSession = false,
  });
}

/// Hoja con buscador para elegir un deportista entre muchos. Devuelve su id.
Future<String?> showPlayerSearchSheet(
  BuildContext context, {
  required List<PickerEntry> entries,
  String? selectedId,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (ctx) => _PlayerSearch(entries: entries, selectedId: selectedId),
);

class _PlayerSearch extends StatefulWidget {
  final List<PickerEntry> entries;
  final String? selectedId;
  const _PlayerSearch({required this.entries, this.selectedId});

  @override
  State<_PlayerSearch> createState() => _PlayerSearchState();
}

class _PlayerSearchState extends State<_PlayerSearch> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final q = searchKey(query.trim());
    final shown =
        widget.entries
            .where((e) => q.isEmpty || searchKey(e.player.name).contains(q))
            .toList()
          ..sort((a, b) {
            if (a.highlighted != b.highlighted) return a.highlighted ? -1 : 1;
            return searchKey(a.player.name).compareTo(searchKey(b.player.name));
          });
    final insets = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: insets),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const Key('player-search'),
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Buscar entre ${widget.entries.length}',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => query = v),
                ),
              ),
              Expanded(
                child: shown.isEmpty
                    ? Center(child: Text('Nadie se llama «$query»'))
                    : ListView.builder(
                        itemCount: shown.length,
                        itemBuilder: (ctx, i) {
                          final e = shown[i];
                          final sel = e.player.id == widget.selectedId;
                          final dim = e.highlighted ? null : Colors.white38;
                          return ListTile(
                            selected: sel,
                            leading: _Initials(
                              e.player.name,
                              dim: !e.highlighted,
                            ),
                            title: Text(
                              e.player.name,
                              style: TextStyle(color: dim),
                            ),
                            subtitle: e.subtitle == null
                                ? null
                                : Text(
                                    e.subtitle!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: dim ?? Colors.white54,
                                    ),
                                  ),
                            trailing: e.inSession
                                ? const Tooltip(
                                    message: 'En la sesión',
                                    child: Icon(
                                      Icons.event_available,
                                      size: 18,
                                    ),
                                  )
                                : null,
                            onTap: () => Navigator.pop(ctx, e.player.id),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final bool dim;
  const _Initials(this.name, {this.dim = false});

  @override
  Widget build(BuildContext context) {
    final text = initialsOf(name);
    return CircleAvatar(
      radius: 18,
      backgroundColor: dim ? Colors.white10 : Colors.white24,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          color: dim ? Colors.white38 : Colors.white,
        ),
      ),
    );
  }
}

/// Pestañas de ejercicio y botón de periodo, compartidos por el perfil
/// individual y la comparación.
class ExercisePeriodBar extends StatelessWidget {
  final List<(String, String)> exercises;
  final String selected;
  final ValueChanged<String> onExercise;
  final String period;
  final List<String> periods;
  final ValueChanged<String> onPeriod;

  const ExercisePeriodBar({
    super.key,
    required this.exercises,
    required this.selected,
    required this.onExercise,
    required this.period,
    required this.periods,
    required this.onPeriod,
  });

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Colors.white12)),
    ),
    child: Row(
      children: [
        Expanded(
          child: UnderlineTabs<String>(
            key: const Key('exercise-tabs'),
            items: exercises,
            selected: selected,
            onSelect: onExercise,
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          key: const Key('period-menu'),
          tooltip: 'Periodo',
          initialValue: period,
          onSelected: onPeriod,
          itemBuilder: (_) => [
            for (final k in periods) PopupMenuItem(value: k, child: Text(k)),
          ],
          child: Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const ShapeDecoration(
              shape: StadiumBorder(side: BorderSide(color: Colors.white24)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.date_range, size: 16, color: Colors.white70),
                const SizedBox(width: 6),
                Text(period),
                const Icon(Icons.arrow_drop_down, size: 18),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
