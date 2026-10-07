import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'apuntes.dart' show Coleccion, Apunte, fechaCorta;
import 'claude.dart';

// Guías generadas a partir de un PDF: el estudiante sube el archivo, elige qué
// quiere (resolver taller, guía de estudio, resumen, examen) y el resultado se
// guarda en usuarios/{uid}/guias. Leerlas funciona sin internet; generarlas no.

const _kClave = 'clave_api_claude';

Future<String> _leerClave() async =>
    (await SharedPreferences.getInstance()).getString(_kClave) ?? '';

/// Pide la clave de la API y la guarda solo en este teléfono.
Future<void> pedirClave(BuildContext context) async {
  final campo = TextEditingController(text: await _leerClave());
  if (!context.mounted) return;
  final nueva = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Clave de la API'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Las guías se generan con Claude y necesitan una clave propia. '
            'Se crea en platform.claude.com, sección API keys. '
            'Queda guardada solo en este teléfono.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: campo,
            obscureText: true,
            autocorrect: false,
            decoration: const InputDecoration(
                labelText: 'Clave (empieza por sk-ant-)',
                border: OutlineInputBorder()),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
        FilledButton(
            onPressed: () => Navigator.pop(c, campo.text.trim()),
            child: const Text('Guardar')),
      ],
    ),
  );
  if (nueva != null) {
    await (await SharedPreferences.getInstance()).setString(_kClave, nueva);
  }
}

class PaginaGuias extends StatelessWidget {
  const PaginaGuias({super.key, required this.usuario});

  final User usuario;

  Coleccion get _col => FirebaseFirestore.instance
      .collection('usuarios')
      .doc(usuario.uid)
      .collection('guias');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Guías desde PDF'),
        actions: [
          IconButton(
            tooltip: 'Clave de la API',
            onPressed: () => pedirClave(context),
            icon: const Icon(Icons.key_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => PaginaNuevaGuia(coleccion: _col))),
        icon: const Icon(Icons.upload_file),
        label: const Text('Subir PDF'),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _col.orderBy('creado', descending: true).snapshots(),
        builder: (context, s) {
          if (s.hasError) {
            return Center(child: Text('No se pudieron leer las guías: ${s.error}'));
          }
          if (!s.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final guias = s.data!.docs;
          if (guias.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Sube el PDF de un taller o de una lectura y la app prepara '
                  'la solución paso a paso, una guía de estudio, un resumen o '
                  'un examen de práctica.\n\nGenerar necesita internet; lo que '
                  'ya esté guardado se lee sin conexión.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: guias.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final g = guias[i].data();
              return ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text((g['titulo'] as String?) ?? 'Sin título',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                    '${g['tipo'] ?? ''} · ${fechaCorta(g['creado'] as Timestamp?)}'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => PaginaVerGuia(guia: guias[i]))),
              );
            },
          );
        },
      ),
    );
  }
}

class PaginaNuevaGuia extends StatefulWidget {
  const PaginaNuevaGuia({super.key, required this.coleccion});

  final Coleccion coleccion;

  @override
  State<PaginaNuevaGuia> createState() => _PaginaNuevaGuiaState();
}

class _PaginaNuevaGuiaState extends State<PaginaNuevaGuia> {
  final _extra = TextEditingController();
  final _texto = StringBuffer();
  PlatformFile? _archivo;
  TipoGuia _tipo = TipoGuia.taller;
  bool _generando = false;
  bool _guardada = false;
  String? _error;

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  Future<void> _elegir() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true,
    );
    if (r == null || !mounted) return;
    final f = r.files.single;
    setState(() {
      if (f.bytes == null) {
        _error = 'No se pudo leer el archivo. Prueba a copiarlo al teléfono.';
      } else if (f.size > maxBytesPdf) {
        _error = 'El PDF pesa más de 20 MB. Prueba con menos páginas.';
      } else {
        _archivo = f;
        _error = null;
      }
    });
  }

  Future<void> _generar() async {
    var clave = await _leerClave();
    if (clave.isEmpty) {
      if (!mounted) return;
      await pedirClave(context);
      clave = await _leerClave();
      if (clave.isEmpty) return;
    }
    if (!mounted) return;
    setState(() {
      _generando = true;
      _guardada = false;
      _error = null;
      _texto.clear();
    });
    try {
      final partes = pedirGuia(
        clave: clave,
        pdf: _archivo!.bytes!,
        tipo: _tipo,
        extra: _extra.text,
      );
      await for (final parte in partes) {
        if (!mounted) return;
        setState(() => _texto.write(parte));
      }
      if (_texto.isEmpty) throw ErrorClaude('La respuesta llegó vacía.');
      // Sin await: la escritura queda en la copia local y sube sola.
      widget.coleccion.add({
        'titulo': _archivo!.name.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), ''),
        'tipo': _tipo.rotulo,
        'texto': _texto.toString(),
        'creado': Timestamp.now(),
      });
      if (mounted) setState(() => _guardada = true);
    } on ErrorClaude catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _error = 'Algo falló al generar la guía: $e');
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva guía')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            OutlinedButton.icon(
              onPressed: _generando ? null : _elegir,
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_archivo == null
                  ? 'Elegir PDF'
                  : '${_archivo!.name} · ${(_archivo!.size / 1024 / 1024).toStringAsFixed(1)} MB'),
            ),
            const SizedBox(height: 16),
            Text('¿Qué necesitas?', style: tema.textTheme.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final t in TipoGuia.values)
                  ChoiceChip(
                    label: Text(t.rotulo),
                    selected: _tipo == t,
                    onSelected:
                        _generando ? null : (_) => setState(() => _tipo = t),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _extra,
              enabled: !_generando,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Indicaciones (opcional)',
                hintText: 'Solo los puntos 3 a 6 · Enfócate en el ciclo del nitrógeno',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _archivo == null || _generando ? null : _generar,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_generando ? 'Generando…' : 'Generar'),
            ),
            if (_generando && _texto.isEmpty) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('Leyendo el documento. Puede tardar uno o dos minutos.'),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
            ],
            if (_guardada) ...[
              const SizedBox(height: 16),
              Text('Guardada en tus guías.',
                  style: TextStyle(color: tema.colorScheme.primary)),
            ],
            if (_texto.isNotEmpty) ...[
              const Divider(height: 32),
              SelectableText(_texto.toString()),
            ],
          ],
        ),
      ),
    );
  }
}

class PaginaVerGuia extends StatelessWidget {
  const PaginaVerGuia({super.key, required this.guia});

  final Apunte guia;

  Future<void> _borrar(BuildContext context) async {
    final si = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar esta guía?'),
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
    if (si != true || !context.mounted) return;
    guia.reference.delete();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final g = guia.data();
    final texto = (g['texto'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text((g['titulo'] as String?) ?? 'Guía'),
        actions: [
          IconButton(
            tooltip: 'Copiar',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: texto));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Copiada')));
            },
          ),
          IconButton(
            tooltip: 'Borrar',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _borrar(context),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            '${g['tipo'] ?? ''} · ${fechaCorta(g['creado'] as Timestamp?)}\n\n$texto',
          ),
        ),
      ),
    );
  }
}
