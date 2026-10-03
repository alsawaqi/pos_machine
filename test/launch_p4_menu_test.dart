import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_machine/models/pos_models.dart';
import 'package:pos_machine/services/config_mapper.dart';
import 'package:pos_machine/services/local_order_storage_service.dart';
import 'package:pos_machine/widgets/product_artwork.dart';
import 'support/fake_order_storage.dart';
import 'workspace_machine_harness.dart';

/// LAUNCH-P4 C4 / H11 — the till shows the merchant's photo (through the
/// device image cache) or an initials placeholder; never a coffee picture.
/// (H5 / L1 / M1 are proven at the catalog boundary in
/// launch_p4_menu_config_test.dart.)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initials: two words -> two letters, Arabic too', () {
    expect(ProductArtwork.initialsOf('Iced Latte'), 'IL');
    expect(ProductArtwork.initialsOf('espresso'), 'E');
    expect(ProductArtwork.initialsOf('لاتيه بارد'), 'لب');
    expect(ProductArtwork.initialsOf('  '), '?');
  });

  testWidgets('no photo: initials placeholder, no image asset', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: ProductArtwork(name: 'Iced Latte')),
    );
    expect(find.text('IL'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('photo: the cached network image is used', (tester) async {
    final urls = <String>[];
    ProductArtwork.debugNetworkImage = (url, fallback) {
      urls.add(url);
      return const SizedBox(key: ValueKey('network-photo'));
    };
    addTearDown(() => ProductArtwork.debugNetworkImage = null);
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductArtwork(
          name: 'Iced Latte',
          imageUrl: 'https://order.mithqal.net/storage/products/7.jpg',
        ),
      ),
    );
    expect(find.byKey(const ValueKey('network-photo')), findsOneWidget);
    expect(urls, ['https://order.mithqal.net/storage/products/7.jpg']);
  });

  group('the real product grid', () {
    const channels = [
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      MethodChannel('pos_machine/rear_display_host'),
      MethodChannel('sunmi_printer_plus'),
    ];
    setUp(() {
      debugOrderStorageOverride = FakeOrderStorage();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        channels[0],
        (call) async => call.method == 'read' ? 'test-token' : null,
      );
      messenger.setMockMethodCallHandler(
        channels[1],
        (call) async => call.method == 'getPresentationDisplays'
            ? <Map<String, dynamic>>[]
            : true,
      );
      messenger.setMockMethodCallHandler(channels[2], (_) async => null);
    });
    tearDown(() {
      debugOrderStorageOverride = null;
      ProductArtwork.debugNetworkImage = null;
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      }
    });

    testWidgets('tiles show the photo or initials, in display order', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final urls = <String>[];
      ProductArtwork.debugNetworkImage = (url, fallback) {
        urls.add(url);
        return const SizedBox.expand(key: ValueKey('network-photo'));
      };
      await pumpWorkspaceMachine(
        tester,
        mode: 'off',
        toggle: false,
        catalog: const CatalogSnapshot(
          categories: ['Coffee'],
          products: [
            Product(
              id: '2',
              name: 'Flat White',
              category: 'Coffee',
              price: 1.6,
              imageUrl: 'https://order.mithqal.net/storage/products/2.jpg',
            ),
            Product(id: '1', name: 'Iced Latte', category: 'Coffee', price: 1.8),
          ],
          floors: [],
          tables: [],
          taxes: [],
        ),
      );
      expect(urls, contains('https://order.mithqal.net/storage/products/2.jpg'));
      expect(find.text('IL'), findsWidgets);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName.contains('latte'),
        ),
        findsNothing,
      );
      // The grid keeps the catalog's (display) order.
      final flat = tester.getTopLeft(find.text('Flat White').first);
      final iced = tester.getTopLeft(find.text('Iced Latte').first);
      expect(
        flat.dy < iced.dy || (flat.dy == iced.dy && flat.dx < iced.dx),
        isTrue,
      );
      await disposeWorkspaceMachine(tester);
    });
  });
}
