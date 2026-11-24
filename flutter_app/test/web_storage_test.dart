import 'package:flutter_test/flutter_test.dart';
import 'package:pma/services/local_db/local_db_web.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('web storage keeps rows by key across reopen', () async {
    SharedPreferences.setMockInitialValues({});
    final db = await openLocalDb('pma_db');
    await db.put('entries', {'id': 'a', 'section': 'chips', 'data': '{}'});
    await db.put('entries', {'id': 'b', 'section': 'wafer', 'data': '{}'});
    await db.put('kv_store', {'key': 'pma_fast_mode', 'value': '1'});
    await db.put('entries', {'id': 'a', 'section': 'nimko', 'data': '{}'}); // replace
    await db.deleteMany('entries', ['b']);

    final again = await openLocalDb('pma_db');
    final entries = await again.all('entries');
    expect(entries, hasLength(1));
    expect(entries.single['section'], 'nimko');
    expect((await again.all('kv_store')).single['value'], '1');

    await again.replaceAll('products', [
      {'id': 'p1', 'data': '{}'},
      {'id': 'p2', 'data': '{}'},
    ]);
    await again.clear('entries');
    final third = await openLocalDb('pma_db');
    expect(await third.all('entries'), isEmpty);
    expect(await third.all('products'), hasLength(2));
  });
}
