"use client"

import { useEffect, useRef, useState } from 'react'
import { BrowserMultiFormatReader } from '@zxing/browser'

type ScannerControls = { stop: () => void }

type Props = {
  open: boolean
  onClose: () => void
  onDetected: (barcode: string) => void
}

export function BarcodeScannerDialog({ open, onClose, onDetected }: Props) {
  const videoRef = useRef<HTMLVideoElement | null>(null)
  const controlsRef = useRef<ScannerControls | null>(null)
  const readerRef = useRef<BrowserMultiFormatReader | null>(null)
  const detectedRef = useRef(false)
  const [error, setError] = useState<string | null>(null)
  const [starting, setStarting] = useState(false)

  useEffect(() => {
    if (!open) return

    let cancelled = false
    detectedRef.current = false
    setError(null)
    setStarting(true)

    async function start() {
      if (!navigator.mediaDevices?.getUserMedia) {
        setError('المتصفح لا يدعم الوصول إلى الكاميرا. أدخل الباركود يدويًا.')
        setStarting(false)
        return
      }

      const reader = new BrowserMultiFormatReader()
      readerRef.current = reader

      try {
        const controls = await reader.decodeFromConstraints(
          {
            audio: false,
            video: {
              facingMode: { ideal: 'environment' },
              width: { ideal: 1280 },
              height: { ideal: 720 },
            },
          },
          videoRef.current ?? undefined,
          (result, _error, callbackControls) => {
            if (!result || detectedRef.current) return

            const value = result.getText().trim()
            if (!value) return

            detectedRef.current = true
            callbackControls.stop()
            onDetected(value)
          },
        )

        if (cancelled) {
          controls.stop()
          return
        }

        controlsRef.current = controls
      } catch (e) {
        if (!cancelled) {
          const message = e instanceof Error ? e.message : String(e)
          setError(
            message.toLowerCase().includes('permission') ||
              message.toLowerCase().includes('notallowed')
              ? 'لم يتم منح صلاحية الكاميرا. اسمح للمتصفح باستخدام الكاميرا ثم جرّب مرة ثانية.'
              : `تعذر تشغيل الكاميرا: ${message}`,
          )
        }
      } finally {
        if (!cancelled) setStarting(false)
      }
    }

    void start()

    return () => {
      cancelled = true
      controlsRef.current?.stop()
      controlsRef.current = null
      readerRef.current = null
    }
  }, [open, onDetected])

  if (!open) return null

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/65 p-4"
      role="dialog"
      aria-modal="true"
      aria-label="ماسح الباركود"
      onMouseDown={(event) => {
        if (event.currentTarget === event.target) onClose()
      }}
    >
      <div className="w-full max-w-lg overflow-hidden rounded-2xl bg-white shadow-2xl">
        <div className="flex items-center justify-between border-b px-4 py-3">
          <div>
            <h2 className="text-lg font-bold">مسح الباركود</h2>
            <p className="text-xs text-gray-500">وجّه الكاميرا نحو باركود المنتج</p>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-lg px-3 py-2 text-sm font-semibold text-gray-600 hover:bg-gray-100"
          >
            إغلاق
          </button>
        </div>

        <div className="relative aspect-video bg-black">
          <video
            ref={videoRef}
            className="h-full w-full object-cover"
            autoPlay
            muted
            playsInline
          />

          <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
            <div className="h-28 w-[82%] rounded-xl border-2 border-white shadow-[0_0_0_999px_rgba(0,0,0,.22)]" />
          </div>

          {starting && (
            <div className="absolute inset-0 flex items-center justify-center bg-black/35 text-sm font-semibold text-white">
              جاري تشغيل الكاميرا...
            </div>
          )}
        </div>

        <div className="p-4">
          {error ? (
            <div className="rounded-xl bg-red-50 p-3 text-sm font-medium text-red-700">
              {error}
            </div>
          ) : (
            <p className="text-center text-sm text-gray-600">
              لا تحتاج تضغط تصوير؛ القراءة تتم تلقائيًا.
            </p>
          )}
        </div>
      </div>
    </div>
  )
}
