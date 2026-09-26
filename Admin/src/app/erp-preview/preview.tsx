'use client';

import { useMemo, useState } from 'react';
import { parseDemoScaleLabel, type ScaleSaleLine } from '@/lib/erp/scale-label';
import './preview.css';

type Module = 'overview' | 'pos' | 'inventory' | 'accounting' | 'reports' | 'hr' | 'audit';
const fmt = (n: number) => n.toFixed(3);
const modules: { id: Module; title: string; short: string }[] = [
  { id: 'overview', title: 'نظرة عامة', short: 'الرئيسية' },
  { id: 'pos', title: 'نقطة البيع والميزان', short: 'POS' },
  { id: 'inventory', title: 'المستودعات والمشتريات', short: 'المخزون' },
  { id: 'accounting', title: 'المحاسبة العامة', short: 'المحاسبة' },
  { id: 'reports', title: 'التقارير المالية', short: 'التقارير' },
  { id: 'hr', title: 'شؤون الموظفين', short: 'الموظفون' },
  { id: 'audit', title: 'التدقيق والرقابة', short: 'التدقيق' },
];

const products = [
  { code: '000001', name: 'صنف الملصق الموزون', stock: '146.800 كغ', price: '5.000', flag: 'وزني' },
  { code: '100204', name: 'أرز أبيض 5 كغ', stock: '82 قطعة', price: '7.250', flag: 'قطعة' },
  { code: '100318', name: 'حليب كامل الدسم', stock: '24 قطعة', price: '1.350', flag: 'قطعة' },
  { code: '100449', name: 'زيت نباتي 1.8 لتر', stock: '9 قطع', price: '3.890', flag: 'تنبيه' },
];

const accounts = [
  { code: '1010', name: 'الصندوق', debit: 4120, credit: 120, balance: 4000 },
  { code: '1200', name: 'المخزون', debit: 11250, credit: 1250, balance: 10000 },
  { code: '2100', name: 'ذمم الموردين', debit: 1000, credit: 4000, balance: -3000 },
  { code: '3100', name: 'رأس المال', debit: 0, credit: 9000, balance: -9000 },
  { code: '4100', name: 'المبيعات', debit: 0, credit: 2200, balance: -2200 },
  { code: '5100', name: 'تكلفة المبيعات', debit: 1250, credit: 50, balance: 1200 },
];

function Table({ heads, rows }: { heads: string[]; rows: (string | number)[][] }) {
  return <div className="erp-table-wrap"><table className="erp-table"><thead><tr>{heads.map(h => <th key={h}>{h}</th>)}</tr></thead>
    <tbody>{rows.map((r, i) => <tr key={i}>{r.map((v, j) => <td key={j}>{v}</td>)}</tr>)}</tbody></table></div>;
}

function SectionTitle({ eyebrow, title, detail }: { eyebrow: string; title: string; detail?: string }) {
  return <div className="erp-section-title"><span>{eyebrow}</span><h2>{title}</h2>{detail && <p>{detail}</p>}</div>;
}

export default function ErpPreview() {
  const [active, setActive] = useState<Module>('overview');
  const [barcode, setBarcode] = useState('2000001002001');
  const [cart, setCart] = useState<ScaleSaleLine[]>([]);
  const [notice, setNotice] = useState('');
  const [search, setSearch] = useState('');
  const total = useMemo(() => cart.reduce((sum, line) => sum + line.amount, 0), [cart]);
  const shownProducts = products.filter(p => `${p.name} ${p.code}`.includes(search.trim()));

  function scan() {
    try {
      const line = parseDemoScaleLabel(barcode);
      if (cart.some(item => item.code === line.code)) throw new Error('هذا الملصق موجود في السلة التجريبية بالفعل.');
      setCart(old => [...old, line]);
      setBarcode('');
      setNotice(`أُضيف ${fmt(line.quantity)} كغ إلى السلة.`);
    } catch (error) {
      setNotice(error instanceof Error ? error.message : 'تعذر قراءة الملصق.');
    }
  }

  return <div className="erp-shell" dir="rtl">
    <aside className="erp-nav" aria-label="أقسام ERP">
      <div className="erp-brand"><span className="erp-brand-mark">ط</span><div><strong>الطيبات</strong><small>ERP · نسخة عرض</small></div></div>
      <p className="erp-nav-label">مساحة العمل</p>
      <nav>{modules.map((m, i) => <button key={m.id} type="button" onClick={() => { setActive(m.id); setNotice(''); }}
        aria-current={active === m.id ? 'page' : undefined} className={active === m.id ? 'selected' : ''}>
        <span className="erp-nav-index">{String(i + 1).padStart(2, '0')}</span><span>{m.title}</span></button>)}</nav>
      <div className="erp-nav-footer">عرض تجريبي مستقل<br />لا يغيّر بيانات الطيبات الحقيقية.</div>
    </aside>

    <main className="erp-content">
      <header className="erp-topbar"><div><span className="erp-kicker">أسواق الطيبات / إدارة المتجر</span><h1>{modules.find(m => m.id === active)?.title}</h1></div>
        <div className="erp-top-actions"><span className="erp-live-dot" />بيانات توضيحية <a href="/dashboard">لوحة الطيبات الحالية</a></div></header>

      <div className="erp-mobile-nav" aria-label="أقسام ERP على الهاتف">{modules.map(m => <button key={m.id} type="button"
        className={active === m.id ? 'selected' : ''} onClick={() => setActive(m.id)}>{m.short}</button>)}</div>

      {active === 'overview' && <>
        <div className="erp-hero"><div><span>مسار عمل واحد، من الرف إلى التقرير</span><h2>إدارة المتجر من شاشة واحدة</h2>
          <p>نموذج عرض يوضح كيف تلتقي مبيعات الكاشير وطلبات التطبيق والمستودع والموظفون في سجل قابل للمراجعة.</p></div>
          <button type="button" onClick={() => setActive('pos')}>جرّب ملصق الميزان ←</button></div>
        <div className="erp-kpis">{[
          ['مبيعات اليوم', '1,284.750', 'د.أ · مثال توضيحي'],
          ['الطلبات', '48', 'تطبيق + كاشير'],
          ['أصناف تحتاج متابعة', '12', 'منخفضة المخزون'],
          ['فروقات تحتاج تدقيق', '2', 'بنود مفتوحة'],
        ].map(([label, value, hint]) => <div className="erp-kpi" key={label}><span>{label}</span><strong>{value}</strong><small>{hint}</small></div>)}</div>
        <div className="erp-grid"><section className="erp-card"><SectionTitle eyebrow="سير العمل" title="من البيع حتى القيد" detail="كل خطوة في التشغيل الفعلي تحتاج تحققًا واعتمادًا قبل الترحيل." />
          <ol className="erp-flow"><li><b>01</b><span>مسح باركود المنتج أو ملصق الميزان</span></li><li><b>02</b><span>التحقق من السعر والمخزون في مصدر واحد</span></li><li><b>03</b><span>اعتماد البيع وإصدار الإيصال</span></li><li><b>04</b><span>ترحيل المخزون والقيد المزدوج مع أثر تدقيق</span></li></ol></section>
          <section className="erp-card"><SectionTitle eyebrow="الجاهزية" title="ما الذي يظهر في هذه النسخة؟" />
            <div className="erp-status-list"><p><b>متاح في العرض</b><span>تجربة الملصق، السلة، صفحات الوحدات، نماذج التقارير.</span></p>
              <p><b>موجود في تطبيق الطيبات</b><span>المنتجات الموزونة، الطلبات، لوحة الإدارة والإيصالات.</span></p>
              <p><b>يتطلب تنفيذًا</b><span>الترحيل المحاسبي، دورة المشتريات والرواتب، التكامل الآمن للمخزون.</span></p></div></section></div>
      </>}

      {active === 'pos' && <>
        <div className="erp-panel-intro"><SectionTitle eyebrow="نقطة البيع" title="امسح الملصق المطبوع" detail="العينة من الصورة التي أرسلتها: الصنف 000001، وزن 0.200 كغ، سعر الكيلو 5.000 د.أ." /><span className="erp-pill">قارئ USB أو إدخال يدوي</span></div>
        <div className="erp-grid erp-pos-grid"><section className="erp-card"><form onSubmit={e => { e.preventDefault(); scan(); }} className="erp-scan-form">
          <label htmlFor="erp-barcode">باركود الميزان EAN-13</label><input id="erp-barcode" inputMode="numeric" autoComplete="off" value={barcode}
            onChange={e => setBarcode(e.target.value)} placeholder="2000001002001" />
          <button type="submit" disabled={!barcode.trim()}>إضافة الملصق للسلة</button></form>
          <div className="erp-label-diagram"><span>2<br /><small>بادئة</small></span><span>000001<br /><small>رقم الصنف</small></span><span>00200<br /><small>الوزن بالغرام</small></span><span>1<br /><small>التحقق</small></span></div>
          {notice && <p className="erp-notice" role="status">{notice}</p>}
          <div className="erp-info">تتحقق النسخة من رقم EAN-13 والوزن وربط الصنف، وتمنع تكرار الملصق داخل السلة. صيغة أجهزة أخرى تُضبط بعد فحص عينة فعلية.</div>
        </section><section className="erp-card"><SectionTitle eyebrow="فاتورة مبدئية" title="سلة الكاشير" />
          {cart.length ? <Table heads={['الصنف', 'الكمية', 'السعر/كغ', 'الإجمالي']} rows={cart.map(l => [l.name, `${fmt(l.quantity)} كغ`, fmt(l.unitPrice), fmt(l.amount)])} />
            : <p className="erp-empty">امسح ملصق الميزان لإضافة الصنف.</p>}
          <div className="erp-total"><span>مجموع المعاينة</span><strong>{fmt(total)} د.أ</strong></div>
          {cart.length > 0 && <button className="erp-quiet" type="button" onClick={() => { setCart([]); setBarcode('2000001002001'); setNotice('تم تفريغ السلة التجريبية.'); }}>تفريغ السلة</button>}
          <p className="erp-muted">لا يتم تحصيل مبلغ أو إصدار فاتورة أو خصم مخزون في نسخة العرض.</p></section></div>
      </>}

      {active === 'inventory' && <>
        <div className="erp-kpis">{[['الأصناف', '11,443', 'قيمة من حصر سابق · مثال'], ['الأصناف الوزنية', '182', 'تحتاج معايرة وحدات'], ['المستودعات', '02', 'عرض توضيحي'], ['أوامر الشراء', '06', 'تحت المراجعة']].map(([a,b,c]) => <div className="erp-kpi" key={a}><span>{a}</span><strong>{b}</strong><small>{c}</small></div>)}</div>
        <section className="erp-card"><SectionTitle eyebrow="دليل المخزون" title="الأصناف والحركات" detail="الأرقام أدناه بيانات مثال لنسخة العرض؛ مخزون الإنتاج يبقى في قاعدة الطيبات الحالية." />
          <label className="erp-search">بحث عن صنف أو باركود<input value={search} onChange={e => setSearch(e.target.value)} placeholder="اسم الصنف أو رقمه" /></label>
          <Table heads={['رمز الصنف', 'الصنف', 'الرصيد', 'السعر', 'النوع']} rows={shownProducts.map(p => [p.code,p.name,p.stock,`${p.price} د.أ`,p.flag])} />
          <p className="erp-muted">التنفيذ الفعلي: استلام مشتريات، تحويل مستودعي، جرد وتسويات مع سجل حركة واحد، دون تكرار خصم الطلبات الإلكترونية.</p></section>
      </>}

      {active === 'accounting' && <>
        <div className="erp-panel-intro"><SectionTitle eyebrow="دفتر الأستاذ" title="شجرة الحسابات والقيود" detail="قيم توضيحية متوازنة لشرح فكرة القيد المزدوج؛ لم تُستخرج من معاملات المتجر." /><span className="erp-pill">مدين = دائن</span></div>
        <section className="erp-card"><Table heads={['الحساب', 'الاسم', 'مدين د.أ', 'دائن د.أ', 'الرصيد']} rows={accounts.map(a => [a.code,a.name,fmt(a.debit),fmt(a.credit),fmt(Math.abs(a.balance))])} />
          <div className="erp-total"><span>ميزان المراجعة التجريبي</span><strong>{fmt(accounts.reduce((s,a) => s + a.debit,0))} = {fmt(accounts.reduce((s,a) => s + a.credit,0))} د.أ</strong></div></section>
        <div className="erp-grid"><section className="erp-card"><SectionTitle eyebrow="مثال قيد" title="بيع نقدي موزون" />
          <Table heads={['الحساب', 'مدين', 'دائن']} rows={[["الصندوق", "1.000", "—"],["المبيعات", "—", "1.000"]]} /></section>
          <section className="erp-card"><SectionTitle eyebrow="ضوابط" title="الترحيل المالي" /><p className="erp-prose">في الإنتاج، قيود البيع والتكلفة تُرحّل داخل معاملة واحدة بعد التحقق من مخزون الصنف وسعره، مع منع تكرار العملية. القيود المعتمدة تُصحح بقيد عكسي ويحفظ أثر كل اعتماد.</p></section></div>
      </>}

      {active === 'reports' && <>
        <div className="erp-kpis">{[['إيرادات الفترة', '2,200.000', 'د.أ'], ['تكلفة المبيعات', '1,200.000', 'د.أ'], ['مجمل الربح', '1,000.000', 'د.أ'], ['هامش الربح', '45.45%', 'بيانات توضيحية']].map(([a,b,c]) => <div className="erp-kpi" key={a}><span>{a}</span><strong>{b}</strong><small>{c}</small></div>)}</div>
        <div className="erp-grid"><section className="erp-card"><SectionTitle eyebrow="قائمة الدخل" title="نتيجة أعمال نموذجية" />
          <Table heads={['البند', 'القيمة د.أ']} rows={[["المبيعات","2,200.000"],["تكلفة المبيعات","(1,200.000)"],["مجمل الربح","1,000.000"]]} /></section>
          <section className="erp-card"><SectionTitle eyebrow="المركز المالي" title="ميزانية نموذجية" />
          <Table heads={['البند', 'القيمة د.أ']} rows={[["النقد والمخزون","14,000.000"],["الالتزامات","3,000.000"],["رأس المال والأرباح","11,000.000"]]} /></section></div>
        <p className="erp-muted">في النسخة الحقيقية ستُحسب التقارير من قيود دفتر الأستاذ المعتمدة، مع مقارنة الصندوق والمخزون والذمم، وليس من أرقام لوحة الطلبات فقط.</p>
      </>}

      {active === 'hr' && <>
        <div className="erp-kpis">{[['الموظفون', '24', 'مثال توضيحي'], ['حضور اليوم', '21', 'وردية صباحية'], ['الإجازات', '2', 'بانتظار الاعتماد'], ['مسير الرواتب', 'مسودة', 'لا ترحيل مالي']].map(([a,b,c]) => <div className="erp-kpi" key={a}><span>{a}</span><strong>{b}</strong><small>{c}</small></div>)}</div>
        <section className="erp-card"><SectionTitle eyebrow="شؤون الموظفين" title="دورة الموظف والرواتب" detail="نموذج يوضح الملف الوظيفي والحضور والإجازات والرواتب؛ الأسماء أدناه أمثلة غير حقيقية." />
          <Table heads={['الموظف', 'القسم', 'الدوام', 'الإجازة', 'الحالة']} rows={[["موظف 001","الكاشير","09:00–17:00","0 يوم","على رأس العمل"],["موظف 002","المستودع","08:00–16:00","يومان","طلب قيد الموافقة"],["موظف 003","المشتريات","09:00–17:00","0 يوم","على رأس العمل"]]} />
          <p className="erp-muted">الرواتب في الإنتاج تحتاج صلاحيات منفصلة واعتمادات وسرية بيانات، وتُرحّل إلى المحاسبة بعد مراجعة المسير فقط.</p></section>
      </>}

      {active === 'audit' && <>
        <div className="erp-panel-intro"><SectionTitle eyebrow="الرقابة" title="التدقيق الداخلي والخارجي" detail="أمثلة لملف أدلة المراجعة والاختبارات الرقابية، دون الادعاء بأنها نتائج فحص حقيقي." /><span className="erp-pill">أثر وتوثيق</span></div>
        <div className="erp-grid"><section className="erp-card"><SectionTitle eyebrow="اختبارات رقابية" title="نقاط الفحص" />
          <Table heads={['الاختبار', 'الهدف', 'الحالة']} rows={[["مطابقة الصندوق","مبيعات POS مقابل التحصيل","مثال: مفتوح"],["مطابقة المخزون","حركات البيع والجرد مقابل الرصيد","مثال: مفتوح"],["القيد المزدوج","مدين = دائن لكل مستند","قاعدة إلزامية"],["فصل الصلاحيات","إنشاء واعتماد وصرف","يتطلب إعداد"]]} /></section>
          <section className="erp-card"><SectionTitle eyebrow="ملف المدقق" title="ما يمكن تصديره لاحقًا" /><div className="erp-status-list"><p><b>سلسلة المستندات</b><span>مرجع الطلب، الإيصال، حركة المخزون، القيد، ومن اعتمده.</span></p><p><b>الأدلة</b><span>جرد المخزون، كشوف الموردين، تسوية الصندوق والبنك.</span></p><p><b>الملاحظات</b><span>تسجيل الملاحظة ومسؤول المعالجة وتاريخ الإغلاق.</span></p></div></section></div>
      </>}
      <footer className="erp-footer">الطيبات ERP · تصور تفاعلي للعرض · لا يحتوي بيانات تشغيلية فعلية ولا ينفذ عمليات مالية.</footer>
    </main>
  </div>;
}
