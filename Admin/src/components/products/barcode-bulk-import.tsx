"use client"

import { useMemo, useState } from "react"
import { useRouter } from "next/navigation"
import { createClient } from "@/lib/supabase/client"

type ProductRef = {
  id: string
  name: string
  sku: string | null
  barcode: string | null
}

type ImportError = {
  row?: number
  reason?: string
  barcode?: string
  sku?: string
  product_name?: string
  existing_product_name?: string
}

type ImportResult = {
  dry_run: boolean
  total: number
  valid: number
  updated: number
  applied: boolean
  errors: ImportError[]
}

function parseCsvLine(line: string) {
  const cells: string[] = []
  let cell = ""
  let quoted = false

  for (let i = 0; i < line.length; i++) {
    const ch = line[i]
    if (ch === '"') {
      if (quoted && line[i + 1] === '"') {
        cell += '"'
        i++
      } else {
        quoted = !quoted
      }
    } else if (ch === "," && !quoted) {
      cells.push(cell)
      cell = ""
    } else {
      cell += ch
    }
  }
  cells.push(cell)
  return cells
}

function cleanCell(value: string) {
  let v = value.replace(/^\uFEFF/, "").trim()
  const excelText = v.match(/^="(.*)"$/)
  if (excelText) v = excelText[1]
  if (v.startsWith("'")) v = v.slice(1)
  return v.trim()
}

function csvEscape(value: string | null | undefined) {
  const text = value ?? ""
  return `"${text.replaceAll('"', '""')}"`
}

function errorLabel(reason?: string) {
  const labels: Record<string, string> = {
    EMPTY_BARCODE: "الباركود فارغ",
    INVALID_GTIN: "GTIN/EAN غير صالح أو checksum خاطئ",
    DUPLICATE_IN_FILE: "الباركود مكرر داخل الملف",
    INVALID_PRODUCT_ID: "معرّف المنتج غير صالح",
    PRODUCT_NOT_FOUND: "المنتج غير موجود",
    SKU_NOT_FOUND: "SKU غير موجود",
    AMBIGUOUS_SKU: "SKU يطابق أكثر من منتج",
    PRODUCT_REFERENCE_REQUIRED: "يلزم product_id أو SKU",
    BARCODE_ALREADY_USED: "الباركود مستخدم لمنتج آخر",
  }
  return labels[reason ?? ""] ?? reason ?? "خطأ غير معروف"
}

export function BarcodeBulkImport({
  storeId,
  products,
}: {
  storeId: string
  products: ProductRef[]
}) {
  const router = useRouter()
  const supabase = useMemo(() => createClient(), [])
  const [rows, setRows] = useState<Record<string, string>[]>([])
  const [fileName, setFileName] = useState("")
  const [result, setResult] = useState<ImportResult | null>(null)
  const [busy, setBusy] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  function exportTemplate() {
    const header = "product_id,sku,name,barcode"
    const body = products.map((p) =>
      [
        csvEscape(p.id),
        csvEscape(p.sku),
        csvEscape(p.name),
        csvEscape(p.barcode),
      ].join(","),
    )
    const blob = new Blob(["\uFEFF", header, "\n", body.join("\n")], {
      type: "text/csv;charset=utf-8",
    })
    const url = URL.createObjectURL(blob)
    const a = document.createElement("a")
    a.href = url
    a.download = "altayebat-product-barcodes.csv"
    document.body.appendChild(a)
    a.click()
    a.remove()
    URL.revokeObjectURL(url)
  }

  async function validate(parsedRows: Record<string, string>[]) {
    setBusy(true)
    setMessage(null)
    setResult(null)
    try {
      const { data, error } = await supabase.rpc("admin_import_product_barcodes", {
        p_store_id: storeId,
        p_rows: parsedRows,
        p_dry_run: true,
      })
      if (error) throw error
      setResult(data as ImportResult)
    } catch {
      setMessage("تعذر فحص ملف الباركود. تأكد من الصيغة والصلاحيات.")
    } finally {
      setBusy(false)
    }
  }

  async function onFile(file: File | null) {
    setResult(null)
    setRows([])
    setMessage(null)
    setFileName(file?.name ?? "")
    if (!file) return

    try {
      const text = await file.text()
      const lines = text.split(/\r?\n/).filter((line) => line.trim().length > 0)
      if (lines.length < 2) throw new Error("EMPTY")

      const headers = parseCsvLine(lines[0]).map((h) => cleanCell(h).toLowerCase())
      const productIdIndex = headers.indexOf("product_id")
      const skuIndex = headers.indexOf("sku")
      let barcodeIndex = headers.indexOf("barcode")
      if (barcodeIndex < 0) barcodeIndex = headers.indexOf("gtin")
      if (barcodeIndex < 0) barcodeIndex = headers.indexOf("ean")
      if (barcodeIndex < 0 || (productIdIndex < 0 && skuIndex < 0)) {
        throw new Error("HEADERS")
      }

      const parsed = lines
        .slice(1)
        .map((line) => parseCsvLine(line))
        .map((cells) => ({
          product_id: productIdIndex >= 0 ? cleanCell(cells[productIdIndex] ?? "") : "",
          sku: skuIndex >= 0 ? cleanCell(cells[skuIndex] ?? "") : "",
          barcode: cleanCell(cells[barcodeIndex] ?? ""),
        }))
        .filter((row) => row.barcode.length > 0)

      if (!parsed.length) {
        setMessage("ما في أي باركود معبّى بالملف. عبّي عمود barcode ثم ارفعه.")
        return
      }
      if (parsed.length > 1000) {
        setMessage("الملف يحتوي أكثر من 1000 صف باركود. قسم الملف ثم أعد المحاولة.")
        return
      }

      setRows(parsed)
      await validate(parsed)
    } catch (error) {
      setMessage(
        error instanceof Error && error.message === "HEADERS"
          ? "الملف لازم يحتوي barcode أو gtin، ومعه product_id أو sku."
          : "تعذر قراءة CSV. نزّل القالب من هذه الصفحة واستخدم نفس الأعمدة.",
      )
    }
  }

  async function applyImport() {
    if (!rows.length || !result || result.errors.length > 0) return
    if (!window.confirm(`سيتم ربط ${result.valid} باركود حقيقي بالمنتجات. متابعة؟`)) return

    setBusy(true)
    setMessage(null)
    try {
      const { data, error } = await supabase.rpc("admin_import_product_barcodes", {
        p_store_id: storeId,
        p_rows: rows,
        p_dry_run: false,
      })
      if (error) throw error
      const applied = data as ImportResult
      setResult(applied)
      if (!applied.applied) {
        setMessage("لم يتم تعديل أي منتج لأن الملف يحتوي أخطاء. أصلحها ثم أعد الفحص.")
        return
      }
      setMessage(`تم ربط ${applied.updated} باركود بنجاح.`)
      router.refresh()
    } catch {
      setMessage("فشل تطبيق الملف ولم نعتمد الاستيراد. أعد الفحص وحاول مرة ثانية.")
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="rounded-xl border border-blue-200 bg-blue-50/40 p-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h2 className="font-bold text-gray-900">استيراد GTIN / EAN من POS أو المورد</h2>
          <p className="mt-1 max-w-2xl text-xs leading-6 text-gray-600">
            لا يتم اختراع باركودات. نزّل القائمة، عبّي barcode الحقيقي من العبوة أو
            نظام الـPOS، ثم ارفع CSV. النظام يفحص EAN-8 / UPC-A / EAN-13 / GTIN-14
            والـchecksum والتكرارات قبل أي تعديل.
          </p>
        </div>
        <button
          type="button"
          onClick={exportTemplate}
          className="rounded-lg border border-blue-300 bg-white px-3 py-2 text-sm font-bold text-blue-800"
        >
          تنزيل قالب المنتجات
        </button>
      </div>

      <div className="mt-4 flex flex-wrap items-center gap-3">
        <label className="cursor-pointer rounded-lg bg-gray-900 px-4 py-2 text-sm font-bold text-white">
          اختيار CSV
          <input
            type="file"
            accept=".csv,text/csv"
            className="hidden"
            disabled={busy}
            onChange={(e) => void onFile(e.target.files?.[0] ?? null)}
          />
        </label>
        {fileName && <span className="text-xs text-gray-600">{fileName}</span>}
        <span className="text-xs text-amber-700">
          في Excel اجعل عمود barcode من نوع Text حتى لا تضيع الأصفار في بداية GTIN.
        </span>
      </div>

      {busy && <p className="mt-3 text-sm text-gray-600">جاري الفحص...</p>}
      {message && <p className="mt-3 rounded-lg bg-white px-3 py-2 text-sm">{message}</p>}

      {result && (
        <div className="mt-4 space-y-3">
          <div className="flex flex-wrap gap-2 text-xs font-bold">
            <span className="rounded-full bg-white px-3 py-1">الصفوف: {result.total}</span>
            <span className="rounded-full bg-green-100 px-3 py-1 text-green-800">
              صالح: {result.valid}
            </span>
            <span className="rounded-full bg-red-100 px-3 py-1 text-red-800">
              أخطاء: {result.errors.length}
            </span>
          </div>

          {result.errors.length > 0 && (
            <div className="max-h-48 overflow-auto rounded-lg border border-red-200 bg-white p-3 text-xs">
              {result.errors.slice(0, 30).map((error, index) => (
                <div key={index} className="border-b py-1 last:border-0">
                  صف {error.row ?? "؟"}: {errorLabel(error.reason)}
                  {error.barcode ? ` — ${error.barcode}` : ""}
                  {error.existing_product_name ? ` — مستخدم في ${error.existing_product_name}` : ""}
                </div>
              ))}
              {result.errors.length > 30 && (
                <p className="mt-2 font-bold">يوجد أخطاء إضافية: {result.errors.length - 30}</p>
              )}
            </div>
          )}

          <button
            type="button"
            disabled={busy || result.valid === 0 || result.errors.length > 0 || result.applied}
            onClick={() => void applyImport()}
            className="rounded-lg bg-brand px-4 py-2 text-sm font-bold text-white disabled:opacity-40"
          >
            {result.applied ? "تم التطبيق" : `اعتماد ${result.valid} باركود`}
          </button>
          {result.errors.length > 0 && (
            <p className="text-xs text-red-700">
              الاستيراد Fail-Closed: لن يتم تعديل أي منتج حتى يصبح الملف كله صالحًا.
            </p>
          )}
        </div>
      )}
    </section>
  )
}
