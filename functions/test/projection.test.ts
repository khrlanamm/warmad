import {describe, expect, it} from "vitest";

import {publicItemChanged, publicItemOf, publicWarungOf} from "../src/public/projection";

const product = {
  name: "Indomie Goreng", category: "Sembako", catalogId: "indomie-goreng", active: true,
  stock: 30, sellPrice: 3500, lastBuyPrice: 2900, manualRop: 24, barcode: "0899",
};

describe("publicItemOf", () => {
  it("exposes only name, category and a three-step status", () => {
    expect(publicItemOf(product)).toEqual(
      {name: "Indomie Goreng", category: "Sembako", status: "tersedia"});
  });

  it("never leaks stock counts, prices or barcodes", () => {
    const leaked = Object.keys(publicItemOf(product)!);
    for (const secret of ["stock", "sellPrice", "lastBuyPrice", "manualRop", "barcode", "computed"]) {
      expect(leaked).not.toContain(secret);
    }
  });

  it("maps stock to tersedia, terbatas and habis", () => {
    expect(publicItemOf({...product, stock: 25})?.status).toBe("tersedia");
    expect(publicItemOf({...product, stock: 24})?.status).toBe("terbatas");
    expect(publicItemOf({...product, stock: 1})?.status).toBe("terbatas");
    expect(publicItemOf({...product, stock: 0})?.status).toBe("habis");
    expect(publicItemOf({...product, stock: -3})?.status).toBe("habis");
  });

  it("hides retired products and products not yet in the catalog", () => {
    expect(publicItemOf({...product, active: false})).toBeNull();
    expect(publicItemOf({...product, catalogId: null})).toBeNull();
    expect(publicItemOf(undefined)).toBeNull();
  });
});

describe("publicItemChanged", () => {
  const item = publicItemOf(product)!;

  it("is false while the status stays in the same step", () => {
    // A sale that takes stock from 30 to 29 changes nothing buyers can see.
    expect(publicItemChanged(item, publicItemOf({...product, stock: 29}))).toBe(false);
  });

  it("is true when the status, the name or the visibility changes", () => {
    expect(publicItemChanged(item, publicItemOf({...product, stock: 10}))).toBe(true);
    expect(publicItemChanged(item, publicItemOf({...product, name: "Indomie Goreng Jumbo"})))
      .toBe(true);
    expect(publicItemChanged(item, null)).toBe(true);
    expect(publicItemChanged(null, item)).toBe(true);
    expect(publicItemChanged(null, null)).toBe(false);
  });
});

describe("publicWarungOf", () => {
  const warung = {
    name: "Warung Barokah", address: "Jl. Telang Raya No. 12, Kamal", geohash: "qw8nv1234",
    location: {latitude: -7.1289, longitude: 112.7243}, hours: {is24h: true},
    showOnMap: true, ownerUid: "owner", phone: "081234567890", cashReminderTime: "23:30",
  };

  it("is null unless the owner chose to appear on the map", () => {
    expect(publicWarungOf({...warung, showOnMap: false})).toBeNull();
    expect(publicWarungOf({...warung, showOnMap: undefined})).toBeNull();
    expect(publicWarungOf(undefined)).toBeNull();
  });

  it("exposes the place and opening hours only", () => {
    const face = publicWarungOf(warung)!;
    expect(Object.keys(face).sort()).toEqual(["address", "geohash", "hours", "location", "name"]);
    expect(face).not.toHaveProperty("ownerUid");
    expect(face).not.toHaveProperty("phone");
    expect(face).not.toHaveProperty("cashReminderTime");
  });
});
