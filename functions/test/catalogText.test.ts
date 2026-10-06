import {describe, expect, it} from "vitest";

import {searchPrefixes, slugify} from "../src/catalog/text";

describe("slugify", () => {
  it("gives the same key for the same item written differently", () => {
    expect(slugify("Indomie Goreng")).toBe("indomie-goreng");
    expect(slugify("  indomie   GORENG! ")).toBe("indomie-goreng");
    expect(slugify("Indomie-Goreng")).toBe("indomie-goreng");
  });

  it("keeps sizes that tell items apart", () => {
    expect(slugify("Aqua 600ml")).toBe("aqua-600ml");
    expect(slugify("Aqua 1500ml")).not.toBe(slugify("Aqua 600ml"));
    expect(slugify("Telur ¼ kg")).toBe("telur-1-4-kg");
  });

  it("returns an empty key for a name without letters or digits", () => {
    expect(slugify(" -- ")).toBe("");
  });
});

describe("searchPrefixes", () => {
  it("lists the prefixes of every word from two letters up", () => {
    expect(searchPrefixes("Kopi Kapal")).toEqual(
      ["ko", "kop", "kopi", "ka", "kap", "kapa", "kapal"]);
  });

  it("skips one letter words and removes duplicates", () => {
    expect(searchPrefixes("Gula a Gula")).toEqual(["gu", "gul", "gula"]);
  });

  it("caps very long words", () => {
    const prefixes = searchPrefixes("supercalifragilistic", 5);
    expect(prefixes).toEqual(["su", "sup", "supe", "super"]);
  });
});
