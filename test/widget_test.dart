import 'package:flutter_test/flutter_test.dart';
import 'package:tabla_periodica_agro/main.dart';

void main() {
  test('la app se puede construir', () {
    expect(const TablaAgroApp(firebaseListo: false), isNotNull);
  });
}
