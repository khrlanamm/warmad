import {readFileSync} from "node:fs";
import {resolve} from "node:path";

import {describe, expect, it} from "vitest";

import {computeInventory, InventoryFigures, InventoryInput, MIN_DAYS} from "../src/inventory/formulas";

interface Vector {
  name: string;
  input: InventoryInput;
  expected: InventoryFigures | null;
}

// The Dart implementation is tested against this same file.
const vectors: Vector[] = JSON.parse(
  readFileSync(resolve(__dirname, "vectors/inventory.json"), "utf8"));

describe("computeInventory", () => {
  it.each(vectors)("$name", ({input, expected}) => {
    expect(computeInventory(input)).toEqual(expected);
  });

  it("reproduces the figures in the product detail design", () => {
    // 12 sold per day on average, peak of 24, one day of lead time.
    const figures = computeInventory(vectors[0].input)!;
    expect(figures.avgDailyTenths).toBe(120);
    expect(figures.safetyStock).toBe(12);
    expect(figures.rop).toBe(24);
    expect(figures.eoq).toBe(80); // 2 dus of 40
  });

  it("follows the textbook formulas", () => {
    const input = vectors[2].input;
    const figures = computeInventory(input)!;
    const total = input.dailyQty.reduce((a, b) => a + b, 0);
    const average = total / input.dailyQty.length;
    const max = Math.max(...input.dailyQty);
    expect(figures.safetyStock).toBe(Math.ceil((max - average) * input.leadTimeDays));
    expect(figures.rop).toBe(
      Math.ceil(average * input.leadTimeDays + (max - average) * input.leadTimeDays));
  });

  it("never suggests an order that is not a whole number of packs", () => {
    for (const {input, expected} of vectors) {
      if (expected?.eoq != null) expect(expected.eoq % Math.max(1, input.packSize)).toBe(0);
    }
  });

  it("needs at least two weeks of history", () => {
    expect(MIN_DAYS).toBe(14);
  });
});
