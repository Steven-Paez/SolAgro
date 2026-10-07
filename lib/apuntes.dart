import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

// Apuntes del estudiante. Cada cuenta ve solo sus apuntes:
//   usuarios/{uid}/apuntes/{id} -> titulo, materia, texto, creado, actualizado
// Firestore guarda una copia en el teléfono: se puede leer y escribir sin
// internet y los cambios suben solos cuando vuelve la conexión.

const materias = [
  'General',
  'Química',
  'Bioquímica',
  'Ecología',
  'Suelos y fertilidad',
  'Fisiología vegetal',
  'Riego y drenaje',
  'Producción de cultivos',
  'Genética',
];

typedef Coleccion = CollectionReference<Map<String, dynamic>>;
typedef Apunte = QueryDocumentSnapshot<Map<String, dynamic>>;

String fechaCorta(Timestamp? t) {
  if (t == null) return '';
  final d = t.toDate();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(d.day)}/${dos(d.month)}/${d.year} ${dos(d.hour)}:${dos(d.minute)}';
}

/// Decide qué mostrar: aviso si falta configurar Firebase, ingreso si no hay
/// sesión, o la pantalla que construye [conUsuario] cuando ya hay cuenta.
class ConSesion extends StatelessWidget {
  const ConSesion({
    super.key,
    required this.firebaseListo,
    required this.conUsuario,
  });

  final bool firebaseListo;
  final Widget Function(User usuario) conUsuario;

  @override
  Widget build(BuildContext context) {
    if (!firebaseListo) {
      return const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Esta sección todavía no está conectada a Firebase.\n\n'
              'Falta ejecutar «flutterfire configure» en el proyecto '
              '(ver LEEME.md).',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, s) {
        if (s.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final usuario = s.data;
        return usuario == null ? const PaginaIngreso() : conUsuario(usuario);
      },
    );
  }
}

class PaginaIngreso extends StatefulWidget {
  const PaginaIngreso({super.key});

  @override
  State<PaginaIngreso> createState() => _PaginaIngresoState();
}

class _PaginaIngresoState extends State<PaginaIngreso> {
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _ocupado = false;
  String? _mensaje;

  @override
  void dispose() {
    _correo.dispose();
    _clave.dispose();
    super.dispose();
  }

  String _explicar(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'El correo no tiene un formato válido.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      case 'email-already-in-use':
        return 'Ya existe una cuenta con ese correo. Usa «Entrar».';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'network-request-failed':
        return 'Sin conexión. Para entrar por primera vez se necesita internet.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera unos minutos.';
      default:
        return 'No se pudo completar (${e.code}).';
    }
  }

  Future<void> _enviar({required bool crear}) async {
    final correo = _correo.text.trim();
    if (correo.isEmpty || _clave.text.isEmpty) {
      setState(() => _mensaje = 'Escribe el correo y la contraseña.');
      return;
    }
    setState(() {
      _ocupado = true;
      _mensaje = null;
    });
    try {
      final auth = FirebaseAuth.instance;
      if (crear) {
        await auth.createUserWithEmailAndPassword(
            email: correo, password: _clave.text);
      } else {
        await auth.signInWithEmailAndPassword(
            email: correo, password: _clave.text);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _mensaje = _explicar(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _recuperar() async {
    final correo = _correo.text.trim();
    if (correo.isEmpty) {
      setState(() => _mensaje = 'Escribe tu correo para enviarte el enlace.');
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: correo);
      if (mounted) {
        setState(() => _mensaje = 'Enlace enviado a $correo. Revisa el correo.');
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _mensaje = _explicar(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Tu cuenta', style: tema.textTheme.headlineMedium),
                const SizedBox(height: 8),
                const Text(
                  'Entra con tu correo para que tus apuntes y guías queden '
                  'guardados en la nube y los recuperes en cualquier teléfono.',
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                      labelText: 'Correo', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clave,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Contraseña', border: OutlineInputBorder()),
                  onSubmitted: (_) => _enviar(crear: false),
                ),
                if (_mensaje != null) ...[
                  const SizedBox(height: 12),
                  Text(_mensaje!, style: TextStyle(color: tema.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _ocupado ? null : () => _enviar(crear: false),
                  child: Text(_ocupado ? 'Un momento…' : 'Entrar'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _ocupado ? null : () => _enviar(crear: true),
                  child: const Text('Crear cuenta'),
                ),
                TextButton(
                  onPressed: _ocupado ? null : _recuperar,
                  child: const Text('Olvidé mi contraseña'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PaginaApuntes extends StatefulWidget {
  const PaginaApuntes({super.key, required this.usuario});

  final User usuario;

  @override
  State<PaginaApuntes> createState() => _PaginaApuntesState();
}

class _PaginaApuntesState extends State<PaginaApuntes> {
  String _buscar = '';
  String? _materia;

  Coleccion get _col => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(widget.usuario.uid)
      .collection('apuntes');

  void _abrir([Apunte? apunte]) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PaginaEditor(coleccion: _col, apunte: apunte),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis apuntes'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (_) => FirebaseAuth.instance.signOut(),
            itemBuilder: (_) => [
              PopupMenuItem(
                  enabled: false, child: Text(widget.usuario.email ?? '')),
              const PopupMenuItem(value: 'salir', child: Text('Cerrar sesión')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrir,
        icon: const Icon(Icons.add),
        label: const Text('Nuevo apunte'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col
            .orderBy('actualizado', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('No se pudieron leer los apuntes: ${s.error}'),
              ),
            );
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final todos = s.data!.docs;
          final q = _buscar.toLowerCase();
          final lista = todos.where((d) {
            final a = d.data();
            if (_materia != null && a['materia'] != _materia) return false;
            if (q.isEmpty) return true;
            return '${a['titulo']} ${a['texto']}'.toLowerCase().contains(q);
          }).toList();
          final usadas = {for (final d in todos) d.data()['materia'] as String?}
            ..remove(null);

          return Column(
            children: [
              if (s.data!.metadata.isFromCache)
                Container(
                  width: double.infinity,
                  color: tema.colorScheme.surfaceContainerHighest,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: const Text(
                    'Sin conexión: ves la copia guardada en el teléfono. '
                    'Los cambios subirán cuando vuelva el internet.',
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar en mis apuntes',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _buscar = v),
                ),
              ),
              if (usadas.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final m in usadas)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(m!),
                            selected: _materia == m,
                            onSelected: (on) =>
                                setState(() => _materia = on ? m : null),
                          ),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: lista.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            todos.isEmpty
                                ? 'Todavía no hay apuntes. Toca «Nuevo apunte» '
                                    'para escribir el primero.'
                                : 'Ningún apunte coincide con la búsqueda.',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.only(bottom: 96),
                        itemCount: lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final d = lista[i];
                          final a = d.data();
                          final pendiente = d.metadata.hasPendingWrites;
                          final titulo = (a['titulo'] as String?) ?? '';
                          return ListTile(
                            title: Text(
                              titulo.isEmpty ? 'Sin título' : titulo,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              '${a['materia'] ?? 'General'} · '
                              '${fechaCorta(a['actualizado'] as Timestamp?)}\n'
                              '${(a['texto'] as String?) ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: Tooltip(
                              message: pendiente
                                  ? 'Guardado en el teléfono; falta subirlo'
                                  : 'Guardado en la nube',
                              child: Icon(
                                pendiente
                                    ? Icons.cloud_upload_outlined
                                    : Icons.cloud_done_outlined,
                                color: pendiente
                                    ? tema.colorScheme.tertiary
                                    : tema.colorScheme.primary,
                              ),
                            ),
                            onTap: () => _abrir(d),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class PaginaEditor extends StatefulWidget {
  const PaginaEditor({super.key, required this.coleccion, this.apunte});

  final Coleccion coleccion;
  final Apunte? apunte;

  @override
  State<PaginaEditor> createState() => _PaginaEditorState();
}

class _PaginaEditorState extends State<PaginaEditor> {
  late final TextEditingController _titulo;
  late final TextEditingController _texto;
  late String _materia;

  @override
  void initState() {
    super.initState();
    final a = widget.apunte?.data() ?? const <String, dynamic>{};
    _titulo = TextEditingController(text: (a['titulo'] as String?) ?? '');
    _texto = TextEditingController(text: (a['texto'] as String?) ?? '');
    final m = a['materia'] as String?;
    _materia = materias.contains(m) ? m! : materias.first;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _texto.dispose();
    super.dispose();
  }

  void _guardar() {
    if (_titulo.text.trim().isEmpty && _texto.text.trim().isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final ahora = Timestamp.now();
    final datos = <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'materia': _materia,
      'texto': _texto.text,
      'actualizado': ahora,
    };
    // No se espera la respuesta: sin internet la escritura queda en cola y
    // el Future no termina hasta que el servidor confirma.
    if (widget.apunte == null) {
      widget.coleccion.add({...datos, 'creado': ahora});
    } else {
      widget.apunte!.reference.update(datos);
    }
    Navigator.of(context).pop();
  }

  Future<void> _borrar() async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar este apunte?'),
        content: const Text('Se borra del teléfono y de la nube. No se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (si != true || !mounted) return;
    widget.apunte!.reference.delete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.apunte == null ? 'Nuevo apunte' : 'Editar apunte'),
        actions: [
          if (widget.apunte != null)
            IconButton(
              tooltip: 'Borrar',
              onPressed: _borrar,
              icon: const Icon(Icons.delete_outline),
            ),
          TextButton(onPressed: _guardar, child: const Text('Guardar')),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _titulo,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                    labelText: 'Título', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _materia,
                decoration: const InputDecoration(
                    labelText: 'Materia', border: OutlineInputBorder()),
                items: [
                  for (final m in materias)
                    DropdownMenuItem(value: m, child: Text(m)),
                ],
                onChanged: (v) => setState(() => _materia = v ?? _materia),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: TextField(
                  controller: _texto,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Escribe aquí: fórmulas, dudas, resúmenes de clase…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}