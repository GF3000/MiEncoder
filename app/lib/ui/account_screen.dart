import 'package:flutter/material.dart';

import '../services/auth.dart';
import '../services/sync.dart';
import 'common.dart';

/// Texto corto con el estado de la sincronización.
String syncSummary(SyncService? sync) {
  if (sync == null) return 'Sesión iniciada';
  final pending = sync.pending > 0 ? ' · ${sync.pending} pendientes' : '';
  final last = sync.lastSync == null
      ? 'Aún no sincronizado'
      : 'Sincronizado ${_ago(sync.lastSync!)}';
  return switch (sync.phase) {
    SyncPhase.syncing => 'Sincronizando…',
    SyncPhase.offline => 'Sin conexión · se subirá al conectar$pending',
    SyncPhase.error => 'Error al sincronizar$pending',
    _ => '$last$pending',
  };
}

String _ago(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'ahora mismo';
  if (d.inHours < 1) return 'hace ${d.inMinutes} min';
  if (d.inDays < 1) return 'hace ${d.inHours} h';
  return 'hace ${d.inDays} días';
}

IconData syncIcon(SyncService? sync) => switch (sync?.phase) {
  SyncPhase.syncing => Icons.cloud_sync,
  SyncPhase.offline => Icons.cloud_off,
  SyncPhase.error => Icons.sync_problem,
  _ => (sync?.pending ?? 0) > 0 ? Icons.cloud_upload : Icons.cloud_done,
};

/// Fila de Ajustes con el estado de la cuenta. Abre [AccountScreen].
class AccountTile extends StatelessWidget {
  final AuthService auth;
  final SyncService? sync;
  const AccountTile({super.key, required this.auth, this.sync});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auth, ?sync]),
      builder: (context, _) {
        if (!auth.available) {
          return const ListTile(
            leading: Icon(Icons.cloud_off),
            title: Text('Cuenta'),
            subtitle: Text('No disponible en este dispositivo'),
          );
        }
        final u = auth.user;
        return ListTile(
          leading: Icon(u == null ? Icons.cloud_off : syncIcon(sync)),
          title: Text(u == null ? 'Iniciar sesión' : (u.email ?? 'Cuenta')),
          subtitle: Text(
            u == null
                ? 'Para guardar copia en la nube y usar varias tablets'
                : syncSummary(sync),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AccountScreen(auth: auth, sync: sync),
            ),
          ),
        );
      },
    );
  }
}

class AccountScreen extends StatelessWidget {
  final AuthService auth;
  final SyncService? sync;
  const AccountScreen({super.key, required this.auth, this.sync});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([auth, ?sync]),
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Cuenta')),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: auth.signedIn
                  ? _SignedIn(auth: auth, sync: sync)
                  : _SignInForm(auth: auth),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignedIn extends StatelessWidget {
  final AuthService auth;
  final SyncService? sync;
  const _SignedIn({required this.auth, this.sync});

  @override
  Widget build(BuildContext context) {
    final u = auth.user!;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.cloud_done, size: 56),
        const SizedBox(height: 12),
        Text(
          u.email ?? 'Sesión iniciada',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'La sesión se queda guardada en esta tablet. No hace falta volver a '
          'entrar aunque esté días sin conexión.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        if (sync != null) ...[
          Card(
            child: ListTile(
              leading: Icon(syncIcon(sync)),
              title: Text(syncSummary(sync)),
              subtitle: sync!.lastError == null
                  ? null
                  : Text(sync!.lastError!, maxLines: 3),
              trailing: IconButton(
                tooltip: 'Sincronizar ahora',
                icon: const Icon(Icons.sync),
                onPressed: sync!.phase == SyncPhase.syncing
                    ? null
                    : sync!.syncNow,
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        OutlinedButton.icon(
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar sesión'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('¿Cerrar sesión?'),
                content: const Text(
                  'Los datos se quedan en esta tablet, pero dejarán de '
                  'copiarse a la nube hasta que vuelvas a entrar.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Cerrar sesión'),
                  ),
                ],
              ),
            );
            if (ok == true) await auth.signOut();
          },
        ),
      ],
    );
  }
}

class _SignInForm extends StatefulWidget {
  final AuthService auth;
  const _SignInForm({required this.auth});

  @override
  State<_SignInForm> createState() => _SignInFormState();
}

class _SignInFormState extends State<_SignInForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _creating = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() f) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await f();
    } on AuthError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _submit() => _run(
    () => _creating
        ? widget.auth.createAccount(_email.text, _password.text)
        : widget.auth.signInWithEmail(_email.text, _password.text),
  );

  void _reset() => _run(() async {
    if (_email.text.trim().isEmpty) {
      throw const AuthError('Escribe tu email para recuperar la contraseña.');
    }
    await widget.auth.sendPasswordReset(_email.text);
    if (mounted) {
      showAppSnack(context, 'Te hemos enviado un email.');
    }
  });

  @override
  Widget build(BuildContext context) {
    return AutofillGroup(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Inicia sesión una vez y los datos se copiarán a la nube cada vez '
            'que la tablet tenga conexión. Sin cuenta, la app sigue '
            'funcionando igual, solo en esta tablet.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.tonalIcon(
            icon: const Icon(Icons.account_circle),
            label: const Text('Continuar con Google'),
            onPressed: _busy
                ? null
                : () => _run(() async {
                    await widget.auth.signInWithGoogle();
                  }),
          ),
          const SizedBox(height: 16),
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text('o con email'),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: [
              _creating ? AutofillHints.newPassword : AutofillHints.password,
            ],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              helperText: _creating ? 'Mínimo 6 caracteres' : null,
            ),
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_creating ? 'Crear cuenta' : 'Entrar'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _creating = !_creating;
                    _error = null;
                  }),
            child: Text(
              _creating
                  ? 'Ya tengo cuenta: entrar'
                  : '¿No tienes cuenta? Crear una',
            ),
          ),
          if (!_creating)
            TextButton(
              onPressed: _busy ? null : _reset,
              child: const Text('He olvidado la contraseña'),
            ),
        ],
      ),
    );
  }
}
