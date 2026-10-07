import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'apuntes.dart';
import 'firebase_options.dart';
import 'guias.dart';

// Etapa 1: la app lleva empaquetada la página completa (assets/web/index.html)
// y la muestra sin conexión. Las pestañas se irán reescribiendo en Dart.
// Los apuntes y las guías generadas desde PDF son nativos y se sincronizan con Firebase.

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var firebaseListo = false;
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    firebaseListo = true;
  } catch (e) {
    // Sin configurar Firebase la tabla sigue funcionando; solo faltan los apuntes.
    debugPrint('Firebase no disponible: $e');
  }
  runApp(TablaAgroApp(firebaseListo: firebaseListo));
}

class TablaAgroApp extends StatelessWidget {
  const TablaAgroApp({super.key, required this.firebaseListo});

  final bool firebaseListo;

  @override
  Widget build(BuildContext context) {
    const verde = Color(0xFF1C6A3A);
    return MaterialApp(
      title: 'Tabla Periódica Agro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: verde, brightness: Brightness.light),
      darkTheme: ThemeData(colorSchemeSeed: verde, brightness: Brightness.dark),
      home: Inicio(firebaseListo: firebaseListo),
    );
  }
}

class Inicio extends StatefulWidget {
  const Inicio({super.key, required this.firebaseListo});

  final bool firebaseListo;

  @override
  State<Inicio> createState() => _InicioState();
}

class _InicioState extends State<Inicio> {
  final _tabla = GlobalKey<PaginaTablaState>();
  int _seccion = 0;

  /// Atrás: desde Apuntes vuelve a la tabla; en la tabla cierra la ficha del
  /// elemento si está abierta y, si no, sale de la app.
  Future<void> _atras() async {
    if (_seccion != 0) {
      setState(() => _seccion = 0);
      return;
    }
    final cerroFicha = await _tabla.currentState?.cerrarFicha() ?? false;
    if (!cerroFicha) SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (salio, _) {
        if (!salio) _atras();
      },
      child: Scaffold(
        body: IndexedStack(
          index: _seccion,
          children: [
            PaginaTabla(key: _tabla),
            ConSesion(
              firebaseListo: widget.firebaseListo,
              conUsuario: (u) => PaginaApuntes(usuario: u),
            ),
            ConSesion(
              firebaseListo: widget.firebaseListo,
              conUsuario: (u) => PaginaGuias(usuario: u),
            ),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _seccion,
          onDestinationSelected: (i) => setState(() => _seccion = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.grid_view_outlined), label: 'Tabla'),
            NavigationDestination(
                icon: Icon(Icons.edit_note_outlined), label: 'Apuntes'),
            NavigationDestination(
                icon: Icon(Icons.auto_stories_outlined), label: 'Guías'),
          ],
        ),
      ),
    );
  }
}

class PaginaTabla extends StatefulWidget {
  const PaginaTabla({super.key});

  @override
  State<PaginaTabla> createState() => PaginaTablaState();
}

class PaginaTablaState extends State<PaginaTabla> {
  late final WebViewController _web;
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => setState(() => _cargando = false),
          // La app no navega a ningún sitio externo: solo su propia página.
          onNavigationRequest: (peticion) => peticion.url.startsWith('file://')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..loadFlutterAsset('assets/web/index.html');
  }

  /// Cierra la ficha del elemento si está abierta. Devuelve si cerró algo.
  Future<bool> cerrarFicha() async {
    final r = await _web.runJavaScriptReturningResult(
      "(()=>{const d=document.getElementById('dlg');"
      "if(d&&d.open){d.close();return true}return false})()",
    );
    return r == true || r.toString() == 'true';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          WebViewWidget(controller: _web),
          if (_cargando) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
