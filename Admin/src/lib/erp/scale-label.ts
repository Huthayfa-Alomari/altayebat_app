export type ScaleSaleLine = {
  code: string;
  name: string;
  quantity: number;
  unitPrice: number;
  amount: number;
};

export function ean13CheckDigit(body: string): number {
  if (!/^\d{12}$/.test(body)) throw new Error('EXPECTED_TWELVE_DIGITS');
  const sum = [...body].reduce((total, digit, i) => total + Number(digit) * (i % 2 ? 3 : 1), 0);
  return (10 - (sum % 10)) % 10;
}

// This format is demonstrated by the supplied 2000001002001 label; it is
// configurable in the production design and must be verified on more samples.
export function parseDemoScaleLabel(value: string): ScaleSaleLine {
  const code = value.trim();
  if (!/^\d{13}$/.test(code) || Number(code[12]) !== ean13CheckDigit(code.slice(0, 12))) {
    throw new Error('الباركود غير صالح أو رقم التحقق غير صحيح.');
  }
  if (code[0] !== '2') throw new Error('هذا ليس ملصق ميزان بالصيغة التجريبية.');
  const plu = code.slice(1, 7);
  if (plu !== '000001') throw new Error(`رقم الصنف ${plu} غير مربوط في نسخة العرض.`);
  const grams = Number(code.slice(7, 12));
  if (grams <= 0) throw new Error('وزن الملصق يجب أن يكون أكبر من الصفر.');
  const quantity = grams / 1000;
  const unitPrice = 5;
  return { code, name: 'صنف الملصق الموزون', quantity, unitPrice,
    amount: (grams * 5000) / 1_000_000 };
}
