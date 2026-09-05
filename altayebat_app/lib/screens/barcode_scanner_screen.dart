import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../services/cart_bridge.dart';
import '../services/supabase_service.dart';

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
  );

  bool _busy = false;
  bool _torchEnabled = false;
  String? _error;
  Map<String, dynamic>? _productData;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_busy) return;

    String? raw;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        raw = value;
        break;
      }
    }

    if (raw == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    await _controller.stop();

    try {
      final product = await SupabaseService.lookupProductByBarcode(raw);
      if (!mounted) return;

      if (product == null) {
        setState(() {
          _productData = null;
          _error = 'ما لقينا منتج متوفر بهذا الباركود.';
        });
      } else {
        setState(() => _productData = product);
      }
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _error = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _scanAgain() async {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = null;
      _productData = null;
    });
    await _controller.start();
  }

  void _addToCart() {
    final data = _productData;
    if (data == null) return;

    final product = Product.fromMap(data);
    final dynamic cart = context.read<CartProvider>();
    final added = CartBridge.addProduct(cart, product);

    if (!added) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تعذر إضافة المنتج للسلة. جرّب إضافته من صفحة المنتجات.',
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('تمت إضافة ${product.name} للسلة')));
    _scanAgain();
  }

  @override
  Widget build(BuildContext context) {
    final product = _productData;

    return Scaffold(
      appBar: AppBar(
        title: const Text('امسح باركود المنتج'),
        actions: [
          IconButton(
            tooltip: 'الفلاش',
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) {
                setState(() => _torchEnabled = !_torchEnabled);
              }
            },
            icon: Icon(_torchEnabled ? Icons.flash_on : Icons.flash_off),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: _controller, onDetect: _onDetect),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 265,
                      height: 165,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(22),
                      ),
                    ),
                  ),
                ),
                const PositionedDirectional(
                  start: 18,
                  end: 18,
                  bottom: 18,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xB3000000),
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Text(
                        'وجّه الكاميرا نحو الباركود. البحث يتم تلقائيًا.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_busy || _error != null || product != null)
            Expanded(
              flex: 4,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                child: _buildResult(product),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResult(Map<String, dynamic>? product) {
    if (_busy && product == null && _error == null) {
      return const Column(
        children: [
          SizedBox(height: 18),
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('جاري البحث عن المنتج...'),
        ],
      );
    }

    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF9F1239),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _scanAgain,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('امسح مرة ثانية'),
          ),
        ],
      );
    }

    if (product == null) return const SizedBox.shrink();

    final name = product['name']?.toString() ?? 'منتج';
    final price = _asDouble(product['price']);
    final stock = _asInt(product['stock_qty']);
    final imageUrl = product['image_url']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductImage(url: imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${price.toStringAsFixed(2)} د.أ',
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFFE31E24),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'متوفر: $stock',
                    style: const TextStyle(
                      color: Color(0xFF6B7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: _addToCart,
          icon: const Icon(Icons.add_shopping_cart),
          label: const Text('أضف للسلة'),
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: _scanAgain,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('امسح منتج ثاني'),
        ),
      ],
    );
  }

  double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }

  int _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class _ProductImage extends StatelessWidget {
  final String? url;

  const _ProductImage({required this.url});

  @override
  Widget build(BuildContext context) {
    final normalized = url?.trim();

    if (normalized == null || normalized.isEmpty) {
      return Container(
        width: 92,
        height: 92,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(
          Icons.inventory_2_outlined,
          size: 34,
          color: Color(0xFF9CA3AF),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        normalized,
        width: 92,
        height: 92,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          width: 92,
          height: 92,
          alignment: Alignment.center,
          color: const Color(0xFFF3F4F6),
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
