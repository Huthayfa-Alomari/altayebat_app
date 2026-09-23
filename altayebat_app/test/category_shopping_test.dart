import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:altayebat_app/models/category.dart';
import 'package:altayebat_app/models/category_tree.dart';
import 'package:altayebat_app/models/product.dart';
import 'package:altayebat_app/providers/cart_provider.dart';
import 'package:altayebat_app/screens/categories_screen.dart';
import 'package:altayebat_app/screens/home_screen_v2.dart';
import 'package:altayebat_app/services/catalog_service.dart';
import 'package:altayebat_app/theme/app_theme.dart';
import 'package:altayebat_app/widgets/category_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

final grocery = ProductCategory(id: 'grocery', name: 'البقالة', sortOrder: 0);
final rice = ProductCategory(
  id: 'rice',
  name: 'الأرز',
  parentId: 'grocery',
  sortOrder: 0,
);
final oil = ProductCategory(
  id: 'oil',
  name: 'الزيوت',
  parentId: 'grocery',
  sortOrder: 1,
);
final allCategories = [
  grocery,
  rice,
  oil,
  ProductCategory(
    id: 'pasta',
    name: 'معكرونة وشعيرية',
    parentId: 'grocery',
    sortOrder: 2,
  ),
  ProductCategory(id: 'dairy', name: 'الألبان والمبردات', sortOrder: 1),
  ProductCategory(
    id: 'cheese',
    name: 'الألبان والأجبان',
    parentId: 'dairy',
    sortOrder: 0,
  ),
  ProductCategory(id: 'meat', name: 'الطازج واللحوم', sortOrder: 2),
  ProductCategory(
    id: 'chicken',
    name: 'اللحوم والدواجن',
    parentId: 'meat',
    sortOrder: 0,
  ),
  ProductCategory(id: 'snacks', name: 'سناكات وحلويات', sortOrder: 3),
  ProductCategory(id: 'drinks', name: 'المشروبات والقهوة', sortOrder: 4),
  ProductCategory(id: 'frozen', name: 'مجمدات ووجبات جاهزة', sortOrder: 5),
  ProductCategory(id: 'clean', name: 'المنزل والتنظيف', sortOrder: 6),
  ProductCategory(id: 'baby', name: 'العناية والطفل', sortOrder: 7),
];
Product product(String id, String name) =>
    Product(id: id, name: name, price: 1.49, stockQty: 20, isAvailable: true);
CatalogPage page(List<Product> items, {bool more = false, int? next}) =>
    CatalogPage(items: items, hasMore: more, nextOffset: next ?? items.length);

typedef Request = ({
  String? category,
  String? query,
  int offset,
  CatalogSort sort,
  bool stock,
});

class FakeCatalog extends CatalogRepository {
  final calls = <Request>[];
  Future<CatalogPage> Function(Request)? responder;
  @override
  Future<List<ProductCategory>> categories({bool forceRefresh = false}) async =>
      allCategories;
  @override
  Future<CatalogPage> products({
    String? categoryId,
    String? searchQuery,
    int offset = 0,
    CatalogSort sort = CatalogSort.newest,
    bool inStockOnly = false,
    bool forceRefresh = false,
  }) async {
    final request = (
      category: categoryId,
      query: searchQuery,
      offset: offset,
      sort: sort,
      stock: inStockOnly,
    );
    calls.add(request);
    return responder == null
        ? page([
            product('first', 'أرز بسمتي طويل الحبة'),
            product('second', 'زيت ذرة نقي'),
            product('third', 'معكرونة قمح'),
            product('fourth', 'سكر أبيض'),
          ])
        : await responder!(request);
  }
}

final previewKey = GlobalKey();
Future<CartProvider> mount(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(375, 812),
  double scale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final cart = CartProvider();
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: cart,
      child: MaterialApp(
        theme: AppTheme.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
            disableAnimations: true,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: RepaintBoundary(key: previewKey, child: child!),
          ),
        ),
        home: child,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return cart;
}

Future<void> preview(WidgetTester tester, String name) async {
  const directory = String.fromEnvironment('UI_PREVIEW_DIR');
  if (directory.isEmpty) return;
  await tester.runAsync(() async {
    await precacheImage(
      const AssetImage(CategoryArtwork.asset),
      tester.element(find.byKey(previewKey)),
    );
  });
  await tester.pump();
  await tester.runAsync(() async {
    final boundary =
        previewKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await Directory(directory).create(recursive: true);
    await File(
      '$directory/$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('IBMPlexSansArabic')
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Regular.ttf'))
      ..addFont(rootBundle.load('assets/fonts/IBMPlexSansArabic-Bold.ttf'));
    await loader.load();
  });
  test(
    'category hierarchy includes descendants and tolerates orphan/cyclic data',
    () {
      final child = ProductCategory(
        id: 'child',
        name: 'فرعي',
        parentId: 'rice',
        sortOrder: 0,
      );
      final orphan = ProductCategory(
        id: 'orphan',
        name: 'جديد',
        parentId: 'missing',
        sortOrder: 0,
      );
      final a = ProductCategory(
        id: 'a',
        name: 'أ',
        parentId: 'b',
        sortOrder: 0,
      );
      final b = ProductCategory(
        id: 'b',
        name: 'ب',
        parentId: 'a',
        sortOrder: 0,
      );
      final tree = CategoryTree([...allCategories, child, orphan, a, b]);
      expect(tree.rootOf(child).id, grocery.id);
      expect(
        tree.descendantsOf(grocery.id).map((c) => c.id),
        containsAll(['rice', 'oil', 'child']),
      );
      expect(tree.roots, contains(orphan));
      expect(tree.descendantsOf('a').map((c) => c.id), ['b']);
      expect(tree.pathTo(a), hasLength(2));
    },
  );
  testWidgets(
    'browse child, switch sibling, search and sort query the selected category',
    (tester) async {
      final repo = FakeCatalog();
      await mount(tester, CategoriesScreen(repository: repo));
      await preview(tester, 'categories');
      await tester.tap(find.widgetWithText(CategoryTile, 'الأرز'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.category, 'rice');
      await tester.tap(find.text('الزيوت'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.category, 'oil');
      await tester.enterText(find.byType(TextField), 'ذرة');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(repo.calls.last.query, 'ذرة');
      await tester.tap(find.text('ترتيب'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('السعر: الأقل أولًا'));
      await tester.pumpAndSettle();
      expect(repo.calls.last.sort, CatalogSort.priceLow);
      expect(repo.calls.last.category, 'oil');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('a late response cannot replace the newly selected category', (
    tester,
  ) async {
    final pending = Completer<CatalogPage>();
    final repo = FakeCatalog()
      ..responder = (r) => r.category == 'rice'
          ? pending.future
          : Future.value(page([product('new', 'زيت جديد')]));
    await mount(
      tester,
      CategoryProductsScreen(
        category: oil,
        categories: allCategories,
        repository: repo,
      ),
    );
    await tester.tap(find.text('الأرز'));
    await tester.pump();
    await tester.tap(find.text('الزيوت').first);
    await tester.pumpAndSettle();
    pending.complete(page([product('stale', 'أرز قديم')]));
    await tester.pumpAndSettle();
    expect(find.text('زيت جديد'), findsOneWidget);
    expect(find.text('أرز قديم'), findsNothing);
  });
  testWidgets(
    'failed pagination preserves loaded products and can be retried',
    (tester) async {
      var failed = false;
      final repo = FakeCatalog()
        ..responder = (r) async {
          if (r.offset == 0)
            return page([product('first', 'منتج أول')], more: true, next: 30);
          if (!failed) {
            failed = true;
            throw Exception('offline');
          }
          return page([product('second', 'منتج ثان')], next: 31);
        };
      await mount(
        tester,
        CategoryProductsScreen(
          category: rice,
          categories: allCategories,
          repository: repo,
        ),
      );
      await tester.tap(find.text('عرض المزيد'));
      await tester.pumpAndSettle();
      expect(find.text('منتج أول'), findsOneWidget);
      await tester.tap(find.text('إعادة محاولة تحميل المزيد'));
      await tester.pumpAndSettle();
      expect(find.text('منتج ثان'), findsOneWidget);
      expect(repo.calls.last.offset, 30);
    },
  );
  for (final size in [
    const Size(320, 740),
    const Size(375, 812),
    const Size(844, 390),
    const Size(800, 1000),
  ]) {
    testWidgets('products and cart fit $size', (tester) async {
      final cart = await mount(
        tester,
        CategoryProductsScreen(
          category: rice,
          categories: allCategories,
          repository: FakeCatalog(),
        ),
        size: size,
      );
      await tester.tap(find.text('أضف').first);
      await tester.pumpAndSettle();
      expect(cart.itemCount, 1);
      expect(tester.takeException(), isNull);
      if (size.width == 375) await preview(tester, 'products');
    });
  }
  testWidgets('category pages and cart support large accessibility text', (
    tester,
  ) async {
    await mount(tester, CategoriesScreen(repository: FakeCatalog()), scale: 2);
    expect(tester.takeException(), isNull);
    final cart = await mount(
      tester,
      CategoryProductsScreen(
        category: rice,
        categories: allCategories,
        repository: FakeCatalog(),
      ),
      scale: 2,
    );
    cart.add(product('first', 'أرز بسمتي طويل الحبة'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await preview(tester, 'products-large-text');
  });
  testWidgets('home category artwork opens its live department', (
    tester,
  ) async {
    final repo = FakeCatalog();
    await mount(tester, HomeScreen(repository: repo));
    expect(find.byType(CategoryTile), findsNWidgets(8));
    await preview(tester, 'home');
    await tester.tap(find.widgetWithText(CategoryTile, 'البقالة'));
    await tester.pumpAndSettle();
    expect(find.byType(CategoryProductsScreen), findsOneWidget);
    expect(repo.calls.last.category, 'grocery');
    expect(tester.takeException(), isNull);
  });
}
