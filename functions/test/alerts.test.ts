import {describe, expect, it} from "vitest";

import {closingAlert, formatRupiah, reminderSlot, stockAlert, stockStatus} from "../src/notifications/alerts";

const indomie = {
  name: "Indomie Goreng", active: true, pack: {size: 40},
  computed: {rop: 24, eoq: 80},
};

describe("stockStatus", () => {
  it("prefers the calculated reorder point over the manual one", () => {
    expect(stockStatus({stock: 20, manualRop: 10, computed: {rop: 24}})).toBe("low");
    expect(stockStatus({stock: 20, manualRop: 10})).toBe("ok");
  });

  it("is out at zero and below", () => {
    expect(stockStatus({stock: 0, manualRop: 10})).toBe("out");
    expect(stockStatus({stock: -2})).toBe("out");
  });
});

describe("stockAlert", () => {
  it("says how many are left and how many to order when stock turns low", () => {
    // The first notification in the design.
    expect(stockAlert({...indomie, stock: 25}, {...indomie, stock: 18}, true)).toEqual({
      type: "lowStock",
      title: "Indomie Goreng tinggal 18 pcs",
      body: "Sudah di bawah batas pesan (24). Saran pesan 80 pcs.",
    });
  });

  it("fires once, not on every sale while the product stays low", () => {
    expect(stockAlert({...indomie, stock: 18}, {...indomie, stock: 17}, true)).toBeNull();
    expect(stockAlert({...indomie, stock: 30}, {...indomie, stock: 26}, true)).toBeNull();
  });

  it("tells a visible warung that buyers now see Habis", () => {
    const alert = stockAlert({...indomie, stock: 2}, {...indomie, stock: 0}, true);
    expect(alert?.type).toBe("outOfStock");
    expect(alert?.title).toBe("Indomie Goreng habis");
    expect(alert?.body).toMatch(/peta/);
  });

  it("does not mention the map to a warung that is not on it", () => {
    const alert = stockAlert({...indomie, stock: 2}, {...indomie, stock: 0}, false);
    expect(alert?.body).not.toMatch(/peta/);
  });

  it("goes straight to out of stock when a big sale skips the low range", () => {
    expect(stockAlert({...indomie, stock: 30}, {...indomie, stock: -1}, false)?.type)
      .toBe("outOfStock");
  });

  it("stays quiet when stock comes back", () => {
    expect(stockAlert({...indomie, stock: 0}, {...indomie, stock: 40}, true)).toBeNull();
    expect(stockAlert({...indomie, stock: 0}, {...indomie, stock: 10}, true)).toBeNull();
  });

  it("fires when a recalculated reorder point rises above the stock", () => {
    const before = {...indomie, stock: 30, computed: {rop: 24, eoq: 80}};
    const after = {...indomie, stock: 30, computed: {rop: 36, eoq: 80}};
    expect(stockAlert(before, after, false)?.type).toBe("lowStock");
  });

  it("stays quiet for new and for retired products", () => {
    expect(stockAlert(undefined, {...indomie, stock: 0}, true)).toBeNull();
    expect(stockAlert({...indomie, stock: 30}, {...indomie, stock: 1, active: false}, true))
      .toBeNull();
  });

  it("falls back to the manual order size, then to one pack", () => {
    const manual = {name: "Aqua", active: true, manualRop: 20, manualOrderQty: 48};
    expect(stockAlert({...manual, stock: 21}, {...manual, stock: 9}, false)?.body)
      .toBe("Sudah di bawah batas pesan (20). Saran pesan 48 pcs.");
    const packOnly = {name: "Aqua", active: true, manualRop: 20, pack: {size: 24}};
    expect(stockAlert({...packOnly, stock: 21}, {...packOnly, stock: 9}, false)?.body)
      .toMatch(/Saran pesan 24 pcs/);
  });
});

describe("closingAlert", () => {
  it("reports a shortfall closed by a cashier", () => {
    // "Kas kemarin selisih -Rp5.000, sudah ditutup oleh kasir Rudi" in the design.
    expect(closingAlert({difference: -5000, closedByUid: "rudi", closedByName: "Rudi"}, "owner"))
      .toEqual({
        type: "cashClosed",
        title: "Kas ditutup, selisih -Rp5.000",
        body: "Uang di laci kurang dari catatan. Ditutup oleh Rudi.",
      });
  });

  it("reports a surplus", () => {
    const alert = closingAlert({difference: 12500, closedByUid: "owner"}, "owner");
    expect(alert?.title).toBe("Kas ditutup, selisih Rp12.500");
    expect(alert?.body).toMatch(/lebih/);
  });

  it("tells the owner when a cashier closed without a difference", () => {
    const alert = closingAlert({difference: 0, closedByUid: "rudi", closedByName: "Rudi"}, "owner");
    expect(alert?.title).toBe("Kas ditutup, tidak ada selisih");
  });

  it("stays quiet when the owner closes with nothing missing", () => {
    expect(closingAlert({difference: 0, closedByUid: "owner"}, "owner")).toBeNull();
  });
});

describe("formatRupiah", () => {
  it("groups thousands with dots", () => {
    expect(formatRupiah(1245000)).toBe("Rp1.245.000");
    expect(formatRupiah(500)).toBe("Rp500");
    expect(formatRupiah(-5000)).toBe("-Rp5.000");
  });
});

describe("reminderSlot", () => {
  it("is the Jakarta time rounded down to a quarter hour", () => {
    expect(reminderSlot(new Date("2026-10-06T16:30:00Z"))).toBe("23:30");
    expect(reminderSlot(new Date("2026-10-06T16:44:59Z"))).toBe("23:30");
    expect(reminderSlot(new Date("2026-10-06T16:45:00Z"))).toBe("23:45");
    expect(reminderSlot(new Date("2026-10-06T17:00:00Z"))).toBe("00:00");
  });
});
