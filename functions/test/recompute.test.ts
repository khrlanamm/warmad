import {describe, expect, it} from "vitest";

import {jakartaDayKey, previousDayKeys, seriesFor} from "../src/inventory/recompute";

describe("jakartaDayKey", () => {
  it("uses the Jakarta calendar day, seven hours ahead of UTC", () => {
    expect(jakartaDayKey(new Date("2026-10-06T16:59:00Z"))).toBe("2026-10-06");
    expect(jakartaDayKey(new Date("2026-10-06T17:00:00Z"))).toBe("2026-10-07");
  });
});

describe("previousDayKeys", () => {
  it("lists the days before today, oldest first, without today", () => {
    const keys = previousDayKeys(new Date("2026-10-06T05:00:00Z"), 3);
    expect(keys).toEqual(["2026-10-03", "2026-10-04", "2026-10-05"]);
  });

  it("crosses month boundaries", () => {
    const keys = previousDayKeys(new Date("2026-10-02T05:00:00Z"), 3);
    expect(keys).toEqual(["2026-09-29", "2026-09-30", "2026-10-01"]);
  });
});

describe("seriesFor", () => {
  const days = ["d1", "d2", "d3", "d4", "d5"];

  it("starts at the first sale and fills quiet days with zero", () => {
    const qty = new Map([["d2", 3], ["d4", 5]]);
    expect(seriesFor(days, qty)).toEqual([3, 0, 5, 0]);
  });

  it("is empty for a product that never sold", () => {
    expect(seriesFor(days, new Map())).toEqual([]);
    expect(seriesFor(days, new Map([["d3", 0]]))).toEqual([]);
  });

  it("treats a day pushed below zero by voids as zero", () => {
    expect(seriesFor(days, new Map([["d1", 2], ["d2", -1]]))).toEqual([2, 0, 0, 0, 0]);
  });

  it("ignores sales outside the window", () => {
    expect(seriesFor(days, new Map([["d0", 9], ["d5", 1]]))).toEqual([1]);
  });
});
