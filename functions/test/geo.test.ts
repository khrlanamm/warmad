import {describe, expect, it} from "vitest";

import {encodeGeohash} from "../src/geo";

describe("encodeGeohash", () => {
  it("matches known reference hashes", () => {
    // Reference values from the original geohash.org examples.
    expect(encodeGeohash(57.64911, 10.40744, 11)).toBe("u4pruydqqvj");
    expect(encodeGeohash(-25.382708, -49.265506, 9)).toBe("6gkzwgjzn");
  });

  it("defaults to 9 characters", () => {
    expect(encodeGeohash(-7.1289, 112.7243)).toHaveLength(9);
  });

  it("gives nearby places a shared prefix", () => {
    const a = encodeGeohash(-7.12890, 112.72430);
    const b = encodeGeohash(-7.12895, 112.72436);
    expect(a.slice(0, 7)).toBe(b.slice(0, 7));
  });
});
