import type { SupabaseClient } from '@supabase/supabase-js'

export type BarcodeStatus = {
  valid: boolean
  available: boolean
  reason: 'EMPTY_BARCODE' | 'BARCODE_TOO_LONG' | 'DUPLICATE' | 'AVAILABLE' | string
  barcode?: string
  product_id?: string
  product_name?: string
}

export async function validateAdminBarcode(
  supabase: SupabaseClient,
  params: {
    storeId: string
    barcode: string
    excludeProductId?: string | null
  },
): Promise<BarcodeStatus> {
  const barcode = params.barcode.trim()

  if (!barcode) {
    return { valid: false, available: false, reason: 'EMPTY_BARCODE' }
  }

  const { data, error } = await supabase.rpc('admin_barcode_status', {
    p_store_id: params.storeId,
    p_barcode: barcode,
    p_exclude_product_id: params.excludeProductId ?? null,
  })

  if (error) throw error

  return (data ?? {
    valid: false,
    available: false,
    reason: 'UNKNOWN',
  }) as BarcodeStatus
}

export async function lookupProductByBarcode(
  supabase: SupabaseClient,
  params: { storeId: string; barcode: string },
) {
  const barcode = params.barcode.trim()
  if (!barcode) return null

  const { data, error } = await supabase.rpc('lookup_product_by_barcode', {
    p_store_id: params.storeId,
    p_barcode: barcode,
  })

  if (error) throw error
  return data ?? null
}
