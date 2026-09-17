import { requireAdminStore } from "@/lib/store-context";
import StoreSettingsManager from "./StoreSettingsManager";

export default async function StoreSettingsPage() {
  const { storeId, storeName } = await requireAdminStore();

  return <StoreSettingsManager storeId={storeId} storeName={storeName} />;
}
