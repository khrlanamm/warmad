// What buyers are allowed to see. Security Rules work per document, not per
// field, so buyers never read a warung's own documents. These helpers build
// the separate public copies, which hold nothing but what is listed here.

import {ProductState, stockStatus} from "../notifications/alerts";

export type Availability = "tersedia" | "terbatas" | "habis";

export interface PublicItem {
  name: string;
  category: string | null;
  status: Availability;
}

/**
 * The public face of a product, or null when it has none (retired, or not
 * yet linked to the catalog).
 *
 * Only a three-step status leaves the warung: never the stock count, the
 * prices, or who sold what.
 */
export function publicItemOf(
  product: (ProductState & {catalogId?: string | null; category?: string | null}) | undefined,
): PublicItem | null {
  if (!product || product.active === false || !product.catalogId || !product.name) return null;
  const status = stockStatus(product);
  return {
    name: product.name,
    category: product.category ?? null,
    status: status === "ok" ? "tersedia" : status === "low" ? "terbatas" : "habis",
  };
}

/** True when two public faces differ, so the public copy needs a write. */
export function publicItemChanged(a: PublicItem | null, b: PublicItem | null): boolean {
  if (a === null || b === null) return a !== b;
  return a.name !== b.name || a.category !== b.category || a.status !== b.status;
}

export interface WarungDoc {
  name?: string;
  address?: string;
  location?: unknown;
  geohash?: string;
  hours?: unknown;
  showOnMap?: boolean;
}

/** The public face of a warung, or null when the owner keeps it off the map. */
export function publicWarungOf(warung: WarungDoc | undefined): Record<string, unknown> | null {
  if (!warung || warung.showOnMap !== true || !warung.geohash) return null;
  return {
    name: warung.name ?? "",
    address: warung.address ?? "",
    location: warung.location ?? null,
    geohash: warung.geohash,
    hours: warung.hours ?? {is24h: true},
  };
}
