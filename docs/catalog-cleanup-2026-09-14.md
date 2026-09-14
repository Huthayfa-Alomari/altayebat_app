# Altayebat catalog cleanup — 2026-09-14

Production Supabase project: `wfvuojrhxewogdnynytf`.

## Owner exclusions

The following storefront groups are intentionally excluded:

- Fruits and vegetables (`الخضار والفواكه`)
- Pet food/supplies (`مستلزمات الحيوانات الأليفة`)

46 live products were removed after verifying they had no order-item, favorite, or active-offer references. The categories remain in taxonomy but are inactive, and related Benchmark v2 staging candidates are marked `REJECTED` so they are not promoted again.

## Arabic localization

The remaining Benchmark v2 live catalog was localized to Arabic while preserving the original English value in `products.name_en`.

Verified production state after localization:

- Total live products: 684
- Benchmark v2 live products: 397
- Benchmark products with Arabic `name`: 397
- Benchmark products still starting with Latin text: 0
- Benchmark products missing `brand_id`: 0
- Products missing images: 0

Manual/user-edited Arabic names were not overwritten by the automated cleanup.

## Image cleanup

The original Benchmark publish used broad category-level fallback images, creating very visible duplicates. Product images were progressively replaced using product/brand/variant-specific public product imagery where a reliable match was available.

Latest verified state during cleanup:

- Distinct image URLs: 605 across 684 live products
- Remaining shared-image products: 123
- Largest shared-image group: 8 products

Some remaining shared images are intentional/acceptable when they represent the same product family in different pack sizes. Do not force unique images when doing so would require using an incorrect product image.

## Data safety rules

- Do not invent barcodes.
- Do not copy competitor reference prices over user-edited store prices without explicit intent.
- Do not re-add excluded produce or pet-food candidates from Benchmark staging.
- Preserve `name_en` when editing the Arabic storefront name.
- Prefer exact product/variant images; a same-family image is acceptable only when an exact pack image cannot be verified.
