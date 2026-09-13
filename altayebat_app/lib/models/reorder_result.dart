import 'product.dart';

class ReorderLine {
  final Product product;
  final int quantity;

  const ReorderLine({required this.product, required this.quantity});
}

class ReorderResult {
  final List<ReorderLine> lines;
  final int unavailableCount;
  final int adjustedCount;

  const ReorderResult({
    required this.lines,
    this.unavailableCount = 0,
    this.adjustedCount = 0,
  });

  bool get isEmpty => lines.isEmpty;
}
