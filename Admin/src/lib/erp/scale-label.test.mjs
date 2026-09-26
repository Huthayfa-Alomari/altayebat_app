import assert from 'node:assert/strict';
import { test } from 'node:test';
import { ean13CheckDigit, parseDemoScaleLabel } from './scale-label.ts';

test('photographed label produces 0.200 kg and 1.000 JOD', () => {
  const line = parseDemoScaleLabel('2000001002001');
  assert.equal(line.quantity, 0.2);
  assert.equal(line.amount, 1);
  assert.equal(ean13CheckDigit('200000100200'), 1);
});

test('invalid check digit and unmapped PLU are rejected', () => {
  assert.throws(() => parseDemoScaleLabel('2000001002002'), /التحقق/);
  const body = '200000200200';
  assert.throws(() => parseDemoScaleLabel(body + ean13CheckDigit(body)), /غير مربوط/);
});
