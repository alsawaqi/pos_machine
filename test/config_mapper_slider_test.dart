import 'package:flutter_test/flutter_test.dart';

import 'package:pos_machine/data/db/app_database.dart';
import 'package:pos_machine/services/config_mapper.dart';

/// Phase 3 — the advertising `sliders` slice survives parse → Drift companions,
/// and toCatalog flattens every slider's slides into one play-ordered ad loop
/// (by slider display order, then slide sort order), dropping empty-url slides.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConfigMapper sliders', () {
    test('parse() flattens sliders + items into companions', () {
      final parsed = ConfigMapper.parse(<String, dynamic>{
        'sliders': [
          {
            'id': 1,
            'uuid': 'u-1',
            'name': 'Ramadan',
            'loop_interval_seconds': 8,
            'items': [
              {
                'id': 11,
                'content_asset_id': 100,
                'advertiser_id': 7,
                'sort_order': 0,
                'duration_seconds': 5,
                'type': 'image',
                'url': 'https://cdn/x.jpg',
                'thumbnail_url': 'https://cdn/t.jpg',
              },
              {
                'id': 12,
                'content_asset_id': 101,
                'advertiser_id': 7,
                'sort_order': 1,
                'duration_seconds': null, // falls back to the loop interval
                'type': 'video',
                'url': 'https://cdn/v.mp4',
              },
            ],
          },
        ],
      });

      expect(parsed.sliders, hasLength(1));
      expect(parsed.sliders.first.id.value, 1);
      expect(parsed.sliders.first.loopIntervalSeconds.value, 8);
      expect(parsed.sliderItems, hasLength(2));
      expect(parsed.sliderItems.first.durationSeconds.value, 5);
      // Null item duration falls back to the slider loop interval (8).
      expect(parsed.sliderItems[1].durationSeconds.value, 8);
      expect(parsed.sliderItems[1].type.value, 'video');
    });

    test('toCatalog() flattens adSlides in play order, dropping empty urls', () {
      final catalog = ConfigMapper.toCatalog(
        null,
        const [], // categories
        const [], // products
        const [], // floors
        const [], // tables
        const [], // taxes
        const [], // addonGroups
        const [], // addons
        const [], // deliveryProviders
        const [], // expenseCategories
        const [], // branchStock
        const [], // discounts
        const [], // loyaltyRules
        const [], // customers
        const [], // ingredients
        null, // meta
        const [], // voidReasons
        const [], // compReasons
        const [], // offers
        const [], // staffMessages
        [
          // Out of order on purpose — display_order decides which plays first.
          const MarketingSliderRow(
              id: 2, uuid: 'u2', name: 'B', loopIntervalSeconds: 6, displayOrder: 1),
          const MarketingSliderRow(
              id: 1, uuid: 'u1', name: 'A', loopIntervalSeconds: 6, displayOrder: 0),
        ],
        [
          const MarketingSliderItemRow(
              id: 21, sliderId: 2, contentAssetId: 200, sortOrder: 0, durationSeconds: 6, type: 'image', url: 'https://cdn/b0.jpg'),
          const MarketingSliderItemRow(
              id: 12, sliderId: 1, contentAssetId: 101, sortOrder: 1, durationSeconds: 6, type: 'video', url: 'https://cdn/a1.mp4'),
          const MarketingSliderItemRow(
              id: 11, sliderId: 1, contentAssetId: 100, sortOrder: 0, durationSeconds: 5, type: 'image', url: 'https://cdn/a0.jpg'),
          // Empty url → dropped.
          const MarketingSliderItemRow(
              id: 99, sliderId: 1, contentAssetId: 0, sortOrder: 2, durationSeconds: 6, type: 'image', url: ''),
        ],
      );

      // slider 1 (display 0) → items [11 sort0, 12 sort1], then slider 2 → [21].
      expect(catalog.adSlides.map((s) => s.itemId).toList(), [11, 12, 21]);
      expect(catalog.adSlides.first.type, 'image');
      expect(catalog.adSlides.first.durationSeconds, 5);
      expect(catalog.adSlides[1].isVideo, isTrue);
      expect(catalog.adSlides.any((s) => s.itemId == 99), isFalse);
    });
  });
}
