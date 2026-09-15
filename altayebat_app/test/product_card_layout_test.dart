import 'package:altayebat_app/models/product.dart';
import 'package:altayebat_app/providers/cart_provider.dart';
import 'package:altayebat_app/theme/app_theme.dart';
import 'package:altayebat_app/widgets/product_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  Product longNameProduct() => Product(
    id: 'layout-product',
    name: 'منتج تجريبي باسم عربي طويل جدًا لاختبار التفاف النص داخل البطاقة',
    price: 1.49,
    stockQty: 130,
    isAvailable: true,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required double height,
    required double textScale,
  }) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => CartProvider(),
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: MediaQuery(
              data: MediaQueryData(
                size: const Size(375, 812),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Center(
                  child: SizedBox(
                    width: 170,
                    height: height,
                    child: ProductCard(product: longNameProduct()),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('product card does not overflow on a 375px phone', (
    tester,
  ) async {
    await pumpCard(tester, height: 278, textScale: 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('product card remains stable with larger text', (tester) async {
    await pumpCard(tester, height: 305, textScale: 1.3);
    expect(tester.takeException(), isNull);
  });
}
