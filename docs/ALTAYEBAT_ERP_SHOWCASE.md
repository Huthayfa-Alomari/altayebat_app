# Altayebat ERP showcase branch

Branch: `codex/altayebat-erp-showcase`. The existing `main` branch and production Supabase database are not modified by this work.

## Open the presentation

From `Admin`, run `npm ci && npm run dev` and visit `http://localhost:3000/erp-preview`. The route is intentionally a **self-contained presentation** with clearly labelled example figures. It requires no Supabase keys and does not write orders, payments, inventory or journals. The existing authenticated admin sidebar also links to it. Test the photographed label `2000001002001` under POS; it decodes PLU `000001`, 0.200 kg at 5.000 JOD/kg to 1.000 JOD.

## What is already in the app

- A Next.js admin portal, Flutter customer app, Supabase orders/products, measured products (integer stock scaled by 1000 for kg/liter), electronic order receipts and payment processing.
- Checkout and refund paths update `public.products.stock_qty` in existing database functions. This is currently the authoritative online-order stock field.

## Work required before calling this a live ERP

| Area | Production design | Acceptance condition |
| --- | --- | --- |
| POS | Authenticated terminal and cashier session; label profiles/PLU mapping scoped to store; server-side price/stock revalidation; payment capture/idempotency | An identical request cannot sell twice; refunds reverse stock and money together |
| Inventory | Introduce a transactionally posted stock movement kernel while migrating **all** checkout, cancellation, returns, admin adjustments and imports to it; `products.stock_qty` becomes derived or a locked projection | Online and till orders share one available stock value, including kg scaled by 1000; reconciliation starts at zero |
| Purchasing | Supplier master, purchase orders, receipts and invoice matching, warehouse locations, stock valuation method | Only accepted receipts add stock and the matching liability is posted once |
| Accounting | Tenant chart, immutable balanced journal entries and reversal, fiscal periods, cash/bank, AR/AP and cost of sales | Every sale/receipt/payroll event posts exactly once, balanced, within an open period |
| Financial reports | Trial balance, income statement, balance sheet, cash flow, stock valuation, aging and reconciliations from posted entries | No numbers pulled from the showcase; statement totals tie to the ledger |
| HR | Employee file, role permissions, attendance, leave approval, payroll draft and approval | Payroll requires separation of preparer/approver and restricted employee data |
| Audit | Immutable approval/event trail, supporting evidence, exception queue, external auditor read-only role and exports | Each posted document traces to source, actor, time and reversal |

## Migration order

1. Obtain a current database schema baseline, function inventory and a staging database copy. The repo's migration directory does not contain the complete original definitions of core tables, so applying speculative production SQL would be unsafe.
2. Freeze and test stock semantics (`stock_qty` in pieces or millesimal kg), reservation timing, card-payment failure and return paths. Build reconciliation against existing orders.
3. Introduce shared inventory posting and run online-order and POS flows through that same transaction boundary. Backfill a dated opening balance and compare each product/store balance before switching reads.
4. Introduce journal posting and idempotent event references, then integrate sales, purchasing and payroll one at a time. Preserve existing order receipts as operational documents until journal reconciliation passes.
5. Add roles, audit evidence and financial reports, then validate with a real till, scale labels of different PLUs/weights and accountant-reviewed sample transactions.

The demo's numbers are illustrative. The sample barcode format is only proven for the one supplied label; production configuration needs more labelled examples and scanner tests.
