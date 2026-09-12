import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/product.dart';
import '../services/terminal_service.dart';

class TerminalInventoryScreen extends StatefulWidget {
  const TerminalInventoryScreen({super.key});

  @override
  State<TerminalInventoryScreen> createState() => _TerminalInventoryScreenState();
}

class _TerminalInventoryScreenState extends State<TerminalInventoryScreen> {
  final MobileScannerController _scanner = MobileScannerController(
    facing: CameraFacing.back,
  );
  final TextEditingController _stock = TextEditingController();

  Product? _product;
  String? _barcode;
  String? _error;
  bool _busy = false;
  bool _torch = false;

  @override
  void dispose() {
    _scanner.dispose();
    _stock.dispose();
    super.dispose();
  }

  Future<void> _detect(BarcodeCapture capture) async {
    if (_busy || _product != null) return;
    String? value;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        value = raw;
        break;
      }
    }
    if (value == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    await _scanner.stop();

    try {
      final product = await TerminalService.lookupProductByBarcode(value);
      if (!mounted) return;
      if (product == null) {
        setState(() => _error = 'هذا الباركود غير مربوط بمنتج.');
        return;
      }
      _setProduct(product, barcode: value);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _setProduct(Product product, {required String barcode}) {
    final stock = product.displayStock;
    _stock.text = stock == stock.roundToDouble()
        ? stock.toStringAsFixed(0)
        : stock
            .toStringAsFixed(3)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
    setState(() {
      _product = product;
      _barcode = barcode;
      _error = null;
    });
  }

  Future<void> _saveStock() async {
    final product = _product;
    final barcode = _barcode;
    if (product == null || barcode == null || _busy) return;

    final value = double.tryParse(_stock.text.trim());
    if (value == null || value < 0) {
      setState(() => _error = 'اكتب مخزونًا صحيحًا.');
      return;
    }
    if (!product.isMeasured && value != value.roundToDouble()) {
      setState(() => _error = 'مخزون المنتج بالحبة لازم يكون رقم صحيح.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await TerminalService.setProductStock(product, displayQuantity: value);
      final refreshed = await TerminalService.lookupProductByBarcode(barcode);
      if (!mounted) return;
      if (refreshed != null) _setProduct(refreshed, barcode: barcode);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث المخزون.')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _scanAgain() async {
    setState(() {
      _product = null;
      _barcode = null;
      _error = null;
    });
    await _scanner.start();
  }

  void _adjust(double delta) {
    final current = double.tryParse(_stock.text.trim()) ?? 0;
    final next = (current + delta).clamp(0, double.infinity);
    _stock.text = next == next.roundToDouble()
        ? next.toStringAsFixed(0)
        : next.toStringAsFixed(3);
  }

  String _message(Object error) => error
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('PostgrestException(message: ', '');

  @override
  Widget build(BuildContext context) {
    final product = _product;

    return Column(
      children: [
        Expanded(
          flex: product == null ? 5 : 3,
          child: Stack(
            fit: StackFit.expand,
            children: [
              MobileScanner(controller: _scanner, onDetect: _detect),
              IgnorePointer(
                child: Center(
                  child: Container(
                    width: 250,
                    height: 150,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
              PositionedDirectional(
                top: 10,
                end: 10,
                child: IconButton.filledTonal(
                  tooltip: 'الفلاش',
                  onPressed: () async {
                    await _scanner.toggleTorch();
                    if (mounted) setState(() => _torch = !_torch);
                  },
                  icon: Icon(_torch ? Icons.flash_on : Icons.flash_off),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 4,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            child: product == null
                ? _ScannerHint(
                    busy: _busy,
                    error: _error,
                    onAgain: _scanAgain,
                  )
                : _StockEditor(
                    product: product,
                    stockController: _stock,
                    busy: _busy,
                    error: _error,
                    onSave: _saveStock,
                    onAgain: _scanAgain,
                    onAdjust: _adjust,
                  ),
          ),
        ),
      ],
    );
  }
}

class _StockEditor extends StatelessWidget {
  final Product product;
  final TextEditingController stockController;
  final bool busy;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onAgain;
  final ValueChanged<double> onAdjust;

  const _StockEditor({
    required this.product,
    required this.stockController,
    required this.busy,
    required this.error,
    required this.onSave,
    required this.onAgain,
    required this.onAdjust,
  });

  @override
  Widget build(BuildContext context) {
    final quickDelta = product.isMeasured ? 0.5 : 1.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          product.name,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        Text(
          '${product.priceLabel} • الحالي ${product.stockLabel}',
          style: const TextStyle(color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: stockController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'المخزون الجديد (${product.unitLabel})',
            helperText: product.isMeasured
                ? 'مثال: 12.5 يعني 12.5 ${product.unitLabel}'
                : 'عدد القطع الفعلي',
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => onAdjust(-quickDelta),
                child: Text('- ${quickDelta.toStringAsFixed(product.isMeasured ? 1 : 0)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => onAdjust(quickDelta),
                child: Text('+ ${quickDelta.toStringAsFixed(product.isMeasured ? 1 : 0)}'),
              ),
            ),
          ],
        ),
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: const TextStyle(
              color: Color(0xFFB91C1C),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: busy ? null : onSave,
          icon: const Icon(Icons.save_outlined),
          label: const Text('حفظ المخزون'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: busy ? null : onAgain,
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('مسح منتج آخر'),
        ),
      ],
    );
  }
}

class _ScannerHint extends StatelessWidget {
  final bool busy;
  final String? error;
  final VoidCallback onAgain;

  const _ScannerHint({
    required this.busy,
    required this.error,
    required this.onAgain,
  });

  @override
  Widget build(BuildContext context) {
    if (busy) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 10),
            Text('جاري تحميل المنتج...'),
          ],
        ),
      );
    }

    return Column(
      children: [
        const Icon(Icons.qr_code_scanner_rounded, size: 48),
        const SizedBox(height: 10),
        const Text(
          'امسح باركود المنتج',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 5),
        const Text(
          'بعد المسح تقدر تعدل المخزون مباشرة.',
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(color: Color(0xFFB91C1C)),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onAgain,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('حاول مرة ثانية'),
          ),
        ],
      ],
    );
  }
}
