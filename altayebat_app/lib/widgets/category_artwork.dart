import 'package:flutter/material.dart';
import '../models/category.dart';
import '../theme/app_theme.dart';

String normalizeCategoryName(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp('[أإآ]'), 'ا')
    .replaceAll(RegExp('[\u064B-\u065F\u0670]'), '');

/// Brandless category still lifes, never used as product photographs.
class CategoryArtwork extends StatelessWidget {
  final ProductCategory category;
  final double size;
  const CategoryArtwork({super.key, required this.category, this.size = 112});
  static const asset = 'assets/images/category-studio-atlas.png';
  static final _cells = <String, int>{
    for (final entry in const {
      'الطازج واللحوم': 0,
      'الألبان والمبردات': 1,
      'البقالة': 2,
      'سناكات وحلويات': 3,
      'المشروبات والقهوة': 4,
      'مجمدات ووجبات جاهزة': 5,
      'المنزل والتنظيف': 6,
      'العناية والطفل': 7,
      'مكسرات': 8,
      'السناكات والحلويات': 9,
      'العناية الشخصية': 10,
      'عناية الأطفال': 11,
      'المجمدات': 12,
      'الألبان والأجبان': 13,
      'اللحوم والدواجن': 14,
      'الأرز': 15,
      'بقوليات': 16,
      'الزيوت': 17,
      'معكرونة وشعيرية': 18,
      'مرقة وشوربات': 19,
      'سكر ومستلزمات الخَبز': 20,
      'معلبات وصلصات': 21,
      'طحينية وحلاوة ومربى': 22,
      'بهارات وأعشاب': 23,
      'خبز ومخبوزات': 24,
      'تمور وعسل': 25,
      'أخرى': 26,
      'غسيل الملابس': 27,
      'تنظيف المنزل والجلي': 28,
      'مناديل وورقيات': 29,
      'مستهلكات منزلية': 30,
      'المشروبات': 31,
      'قهوة': 32,
      'فواكه': 33,
      'خضروات': 34,
      'أسماك ومأكولات بحرية': 35,
    }.entries)
      normalizeCategoryName(entry.key): entry.value,
  };
  @override
  Widget build(BuildContext context) {
    final index = _cells[normalizeCategoryName(category.name)];
    final url = category.imageUrl?.trim();
    // Respect artwork uploaded by the admin; replace arbitrary legacy product covers.
    final network =
        url != null &&
        url.isNotEmpty &&
        (index == null ||
            url.contains('/categories/') ||
            !url.contains('/product-images/'));
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: network
            ? Image.network(
                url,
                fit: BoxFit.contain,
                cacheWidth: 384,
                errorBuilder: (_, error, stack) => _local(index),
              )
            : _local(index),
      ),
    );
  }

  Widget _local(int? index) {
    if (index == null)
      return const ColoredBox(
        color: AppColors.skySoft,
        child: Icon(
          Icons.shopping_basket_outlined,
          color: AppColors.navy,
          size: 32,
        ),
      );
    return ClipRect(
      child: OverflowBox(
        minWidth: size * 6,
        maxWidth: size * 6,
        minHeight: size * 6,
        maxHeight: size * 6,
        alignment: Alignment((index % 6) * 0.4 - 1, (index ~/ 6) * 0.4 - 1),
        child: Image.asset(
          asset,
          width: size * 6,
          height: size * 6,
          fit: BoxFit.fill,
          cacheWidth: 1536,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class CategoryTile extends StatelessWidget {
  final ProductCategory category;
  final VoidCallback onTap;
  final bool compact;
  const CategoryTile({
    super.key,
    required this.category,
    required this.onTap,
    this.compact = false,
  });
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'تسوق ${category.name}',
    child: Material(
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!compact)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Text(
                    category.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    child: CategoryArtwork(
                      category: category,
                      size: compact ? 112 : 136,
                    ),
                  ),
                ),
              ),
              if (compact)
                Text(
                  category.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
