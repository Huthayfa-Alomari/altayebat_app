import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/cart_provider.dart';
import '../services/analytics_service.dart';
import '../services/smart_shopping_service.dart';
import '../theme/app_theme.dart';

class AiShoppingAssistantScreen extends StatefulWidget {
  const AiShoppingAssistantScreen({super.key});

  @override
  State<AiShoppingAssistantScreen> createState() =>
      _AiShoppingAssistantScreenState();
}

class _AiShoppingAssistantScreenState extends State<AiShoppingAssistantScreen> {
  final _controller = TextEditingController();
  SmartShoppingResult? _result;
  bool _loading = false;
  String? _error;

  static const _examples = [
    'اعمللي سلة فطور لعيلة 5 أشخاص تحت 20 دينار',
    'شو ناقصني لعمل مقلوبة؟',
    'بدي مواد تنظيف للبيت بحدود 15 دينار',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _ask([String? example]) async {
    final prompt = (example ?? _controller.text).trim();
    if (prompt.length < 3 || _loading) return;
    FocusScope.of(context).unfocus();
    if (example != null) _controller.text = example;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await SmartShoppingService.ask(prompt);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addAll() {
    final result = _result;
    if (result == null || result.items.isEmpty) return;
    final cart = context.read<CartProvider>();
    var added = 0;

    for (final item in result.items) {
      final product = item.product;
      final quantity = product.isMeasured
          ? item.quantity.clamp(product.minQty, product.stockQty)
          : item.quantity.clamp(1, product.stockQty);
      final ok = product.isMeasured
          ? cart.setQuantity(product, quantity)
          : cart.setQuantity(product, quantity);
      if (ok) added++;
    }

    AnalyticsService.track(
      'ai_assistant_add_all',
      entityType: 'ai_assistant',
      properties: {
        'added_lines': added,
        'suggested_lines': result.items.length,
      },
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تمت إضافة $added منتجات إلى السلة')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(title: const Text('مساعد الطيبات الذكي')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.navy, AppColors.skyBlueDark],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'اطلب سلتك بالكلام',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'اكتب المناسبة أو الوصفة أو الميزانية، وأنا أختار من المنتجات الموجودة فعليًا في المتجر.',
                    style: TextStyle(color: Colors.white70, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _controller,
              minLines: 3,
              maxLines: 5,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'مثال: بدي سلة فطور لعيلة 5 أشخاص تحت 20 دينار',
                alignLabelWithHint: true,
                suffixIcon: IconButton(
                  onPressed: _loading ? null : () => _ask(),
                  icon: const Icon(Icons.send_rounded),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _examples
                  .map(
                    (example) => ActionChip(
                      label: Text(
                        example,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _loading ? null : () => _ask(example),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: FilledButton.icon(
                onPressed: _loading ? null : () => _ask(),
                icon: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome_rounded),
                label: Text(
                  _loading ? 'جاري تجهيز السلة...' : 'جهزلي اقتراحات',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F2),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFF9F1239),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
            if (result != null) ...[
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      result.message,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Text(
                    '${result.totalEstimate.toStringAsFixed(2)} د.أ تقريبًا',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...result.items.map((item) => _SuggestionTile(item: item)),
            ],
          ],
        ),
        bottomNavigationBar: result == null || result.items.isEmpty
            ? null
            : SafeArea(
                top: false,
                child: Material(
                  elevation: 12,
                  color: Colors.white,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: SizedBox(
                      height: 54,
                      child: FilledButton.icon(
                        onPressed: _addAll,
                        icon: const Icon(Icons.add_shopping_cart_rounded),
                        label: const Text('أضف الاقتراحات إلى السلة'),
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _SuggestionTile extends StatelessWidget {
  final SmartShoppingItem item;

  const _SuggestionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final product = item.product;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
              ),
              clipBehavior: Clip.antiAlias,
              child: product.imageUrl == null
                  ? const Icon(Icons.shopping_bag_outlined)
                  : Image.network(
                      product.imageUrl!,
                      fit: BoxFit.contain,
                      cacheWidth: 240,
                      filterQuality: FilterQuality.low,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.shopping_bag_outlined),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    product.priceLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              product.isMeasured
                  ? product.formatQuantity(item.quantity)
                  : '×${item.quantity}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
