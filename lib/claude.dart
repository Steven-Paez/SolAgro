import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

// Llamada directa a la API de Claude (Messages API) para generar una guía a
// partir de un PDF. Dart no tiene SDK oficial, por eso se usa HTTP.
// La respuesta llega por partes (streaming) para mostrarla mientras se escribe.

/// Modelo que genera las guías. Para gastar menos se puede cambiar por
/// 'claude-sonnet-5-5'; la calidad en ejercicios con cálculos baja algo.
const modelo = 'claude-opus-5-5';

/// Tamaño máximo del PDF. La API admite 32 MB por petición y el archivo crece
/// un tercio al codificarse, así que se deja margen.
const maxBytesPdf = 20 * 1024 * 1024;

class ErrorClaude implements Exception {
  ErrorClaude(this.mensaje);
  final String mensaje;

  @override
  String toString() => mensaje;
}

enum TipoGuia {
  taller(
    'Resolver taller',
    'El documento es un taller o lista de ejercicios. Resuelve cada punto en '
        'el orden en que aparece: enunciado resumido, datos, fórmula que se '
        'usa y por qué, procedimiento paso a paso con unidades, y respuesta '
        'final. En las preguntas teóricas, responde y explica el razonamiento. '
        'Si a un punto le faltan datos o es ambiguo, dilo y resuélvelo con el '
        'supuesto más razonable, dejándolo explícito.',
  ),
  estudio(
    'Guía de estudio',
    'El documento es una lectura de clase. Elabora una guía de estudio: ideas '
        'principales, conceptos clave con su definición, cómo se relacionan '
        'entre sí, fórmulas o datos que conviene memorizar, errores frecuentes '
        'y, al final, entre 8 y 10 preguntas de repaso con su respuesta.',
  ),
  resumen(
    'Resumen',
    'Resume el documento para alguien que debe estudiarlo: de qué trata, las '
        'ideas centrales en orden y las conclusiones. Conserva cifras, '
        'fórmulas y definiciones importantes.',
  ),
  preguntas(
    'Examen de práctica',
    'A partir del documento, escribe un examen de práctica de 12 preguntas '
        'que mezcle selección múltiple, respuesta corta y, si el tema lo '
        'permite, ejercicios numéricos. Pon todas las respuestas explicadas '
        'al final, en una sección aparte.',
  );

  const TipoGuia(this.rotulo, this.instruccion);
  final String rotulo;
  final String instruccion;
}

const _sistema =
    'Eres tutor universitario de ingeniería agronómica: química, bioquímica, '
    'suelos y fertilidad, ecología, fisiología vegetal, riego y producción de '
    'cultivos. Trabajas sobre el documento que adjunta el estudiante.\n\n'
    'Tu respuesta se muestra en una pantalla de teléfono que no interpreta '
    'Markdown, así que escribe texto plano: títulos en una línea propia, '
    'numeración 1., 2., 3. y guiones para las listas; sin asteriscos, sin '
    'almohadillas y sin tablas. Escribe cada fórmula en una sola línea y '
    'siempre con unidades.\n\n'
    'Responde en español. Apóyate en el documento; cuando añadas algo que no '
    'está en él, indícalo. Si el documento no trae la información necesaria '
    'para algo, dilo en lugar de inventarlo.';

String _explicarError(int codigo, String cuerpo) {
  String detalle = '';
  try {
    final j = jsonDecode(cuerpo) as Map<String, dynamic>;
    detalle = ((j['error'] as Map?)?['message'] as String?) ?? '';
  } catch (_) {}
  switch (codigo) {
    case 401:
      return 'La clave de la API no es válida. Revísala en el ícono de la llave.';
    case 402:
    case 403:
      return 'La cuenta de la API no tiene saldo o permiso para este modelo. $detalle';
    case 413:
      return 'El PDF es demasiado grande para enviarlo. Prueba con menos páginas.';
    case 429:
      return 'Se alcanzó el límite de uso de la cuenta. Espera un minuto y vuelve a intentar.';
    case 500:
    case 529:
      return 'El servicio está saturado en este momento. Vuelve a intentar en unos minutos.';
    default:
      return 'La API rechazó la petición ($codigo). $detalle';
  }
}

/// Envía el PDF y devuelve el texto de la guía a medida que se genera.
/// Lanza [ErrorClaude] con un mensaje para mostrar al estudiante.
Stream<String> pedirGuia({
  required String clave,
  required Uint8List pdf,
  required TipoGuia tipo,
  String extra = '',
}) async* {
  if (pdf.length > maxBytesPdf) {
    throw ErrorClaude('El PDF pesa más de 20 MB. Prueba con menos páginas.');
  }
  final instruccion = extra.trim().isEmpty
      ? tipo.instruccion
      : '${tipo.instruccion}\n\nIndicaciones del estudiante: ${extra.trim()}';

  final cuerpo = {
    'model': modelo,
    'max_tokens': 64000,
    'stream': true,
    'thinking': {'type': 'adaptive'},
    'output_config': {'effort': 'high'},
    // Si el modelo declina por un filtro de seguridad, la API reintenta sola
    // con el modelo de respaldo recomendado.
    'fallbacks': 'default',
    'system': _sistema,
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'document',
            'source': {
              'type': 'base64',
              'media_type': 'application/pdf',
              'data': base64Encode(pdf),
            },
          },
          {'type': 'text', 'text': instruccion},
        ],
      },
    ],
  };

  final cliente = http.Client();
  try {
    final peticion =
        http.Request('POST', Uri.parse('https://api.anthropic.com/v1/messages'))
          ..headers.addAll({
            'content-type': 'application/json',
            'x-api-key': clave,
            'anthropic-version': '2023-06-01',
            'anthropic-beta': 'server-side-fallback-2026-07-01',
          })
          ..body = jsonEncode(cuerpo);

    final respuesta =
        await cliente.send(peticion).timeout(const Duration(minutes: 5));
    if (respuesta.statusCode != 200) {
      final texto = await respuesta.stream.bytesToString();
      throw ErrorClaude(_explicarError(respuesta.statusCode, texto));
    }

    final lineas = respuesta.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final linea in lineas) {
      if (!linea.startsWith('data:')) continue;
      final evento =
          jsonDecode(linea.substring(5).trim()) as Map<String, dynamic>;
      switch (evento['type']) {
        case 'content_block_delta':
          final delta = evento['delta'] as Map<String, dynamic>;
          if (delta['type'] == 'text_delta') yield delta['text'] as String;
        case 'message_delta':
          final motivo = (evento['delta'] as Map?)?['stop_reason'];
          if (motivo == 'refusal') {
            throw ErrorClaude(
                'El modelo no pudo responder sobre este documento. '
                'Prueba con otro archivo o cambia las indicaciones.');
          }
          if (motivo == 'max_tokens') {
            yield '\n\n[La respuesta se cortó por longitud. Genera otra guía '
                'pidiendo solo una parte del documento.]';
          }
        case 'error':
          final e = evento['error'] as Map?;
          throw ErrorClaude(
              'El servicio interrumpió la respuesta: ${e?['message'] ?? ''}');
      }
    }
  } on TimeoutException {
    throw ErrorClaude('La conexión tardó demasiado. Revisa el internet.');
  } on http.ClientException {
    throw ErrorClaude(
        'No hay conexión. Generar una guía necesita internet; las guías ya '
        'guardadas sí se pueden leer sin conexión.');
  } finally {
    cliente.close();
  }
}
