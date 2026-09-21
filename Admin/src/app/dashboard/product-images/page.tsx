import { requireAdminStore } from "@/lib/store-context";
import ImageEnrichmentManager from "./ImageEnrichmentManager";

export default async function ProductImagesPage() {
  const { storeId } = await requireAdminStore();
  return <ImageEnrichmentManager storeId={storeId} />;
}
