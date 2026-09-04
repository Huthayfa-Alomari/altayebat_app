"use client"

import { useCallback, useEffect, useRef, useState } from 'react'
import type { SupabaseClient } from '@supabase/supabase-js'
import { BarcodeScannerDialog } from './barcode-scanner-dialog'
import { type BarcodeStatus, validateAdminBarcode } from '@/lib/barcode'

type Props = {
  supabase: SupabaseClient
  storeId: string
  productId?: string | null
  value: string
  onChange: (value: string) => void
  disabled?: boolean
}

export function BarcodeField({
  supabase,
  storeId,
  productId,
  value,
  onChange,
  disabled = false,
}: Props) {
  const [scannerOpen, setScannerOpen] = useState(false)
  const [status, setStatus] = useState<BarcodeStatus | null>(null)
  const [checking, setChecking] = useState(false)
  const requestIdRef = useRef(0)

  const check = useCallback(
    async (raw: string) => {
      const barcode = raw.trim()
      const requestId = ++requestIdRef.current

      if (!barcode) {
        setStatus(null)
        setChecking(false)
        return
      }

      setChecking(true)
      try {
        const result = await validateAdminBarcode(supabase, {
          storeId,
          barcode,
          excludeProductId: productId ?? null,
        })
        if (requestId === requestIdRef.current) setStatus(result)
      } catch (error) {
        if (requestId === requestIdRef.current) {
          setStatus({
            valid: false,
            available: false,
            reason: error instanceof Error ? error.message : 'CHECK_FAILED',
          })
        }
      } finally {
        if (requestId === requestIdRef.current) setChecking(false)
      }
    },
    [productId, storeId, supabase],
  )

  useEffect(() => {
    const timer = window.setTimeout(() => {
      void check(value)
    }, 450)
    return () => window.clearTimeout(timer)
  }, [check, value])

  const duplicate = status?.reason === 'DUPLICATE'
  const available = status?.available === true

  return (
    <div className="space-y-2">
      <label htmlFor="barcode" className="block text-sm font-semibold text-gray-800">
        الباركود
      </label>

      <div className="flex gap-2">
        <input
          id="barcode"
          name="barcode"
          type="text"
          inputMode="numeric"
          autoComplete="off"
          maxLength={64}
          value={value}
          disabled={disabled}
          onChange={(event) => onChange(event.target.value)}
          onBlur={() => {
            const trimmed = value.trim()
            if (trimmed !== value) onChange(trimmed)
          }}
          placeholder="مثال: 6251234567890"
          className={`min-w-0 flex-1 rounded-xl border px-3 py-2.5 outline-none transition focus:ring-2 ${
            duplicate
              ? 'border-red-400 focus:ring-red-100'
              : available
                ? 'border-green-400 focus:ring-green-100'
                : 'border-gray-300 focus:border-red-500 focus:ring-red-100'
          }`}
        />

        <button
          type="button"
          disabled={disabled}
          onClick={() => setScannerOpen(true)}
          className="shrink-0 rounded-xl bg-gray-900 px-4 py-2.5 text-sm font-bold text-white transition hover:bg-black disabled:opacity-50"
        >
          مسح بالكاميرا
        </button>
      </div>

      <div className="min-h-5 text-xs">
        {checking ? (
          <span className="text-gray-500">جاري التأكد من الباركود...</span>
        ) : duplicate ? (
          <span className="font-semibold text-red-600">
            هذا الباركود مستخدم للمنتج: {status?.product_name ?? 'منتج آخر'}
          </span>
        ) : available ? (
          <span className="font-semibold text-green-700">الباركود متاح ✓</span>
        ) : value.trim() ? (
          <span className="text-gray-500">سيتم التحقق تلقائيًا.</span>
        ) : (
          <span className="text-gray-500">اختياري حاليًا، لكنه مطلوب لتفعيل البحث بالمسح.</span>
        )}
      </div>

      <BarcodeScannerDialog
        open={scannerOpen}
        onClose={() => setScannerOpen(false)}
        onDetected={(barcode) => {
          onChange(barcode)
          setScannerOpen(false)
          void check(barcode)
        }}
      />
    </div>
  )
}
