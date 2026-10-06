import {describe, expect, it} from "vitest";

import {parseCreateWarungInput} from "../src/warung/input";

const valid = {
  name: "  Warung Barokah ",
  phone: "0812 3456 7890",
  address: "Jl. Telang Raya No. 12, Kamal",
  lat: -7.1289,
  lng: 112.7243,
  hours: {is24h: true},
  showOnMap: false,
  openingBalance: 500000,
};

describe("parseCreateWarungInput", () => {
  it("accepts a complete form and trims text", () => {
    const input = parseCreateWarungInput(valid);
    expect(input.name).toBe("Warung Barokah");
    expect(input.phone).toBe("081234567890");
    expect(input.hours).toEqual({is24h: true});
    expect(input.openingBalance).toBe(500000);
  });

  it("keeps custom opening hours", () => {
    const input = parseCreateWarungInput({
      ...valid,
      hours: {is24h: false, open: "06:00", close: "23:30"},
    });
    expect(input.hours).toEqual({is24h: false, open: "06:00", close: "23:30"});
  });

  it.each([
    ["missing name", {...valid, name: " "}],
    ["bad phone", {...valid, phone: "12ab"}],
    ["missing address", {...valid, address: ""}],
    ["latitude out of range", {...valid, lat: 91}],
    ["location not a number", {...valid, lng: "112"}],
    ["custom hours without times", {...valid, hours: {is24h: false}}],
    ["malformed time", {...valid, hours: {is24h: false, open: "6:00", close: "25:00"}}],
    ["showOnMap missing", {...valid, showOnMap: undefined}],
    ["negative balance", {...valid, openingBalance: -1}],
    ["fractional balance", {...valid, openingBalance: 1000.5}],
    ["balance as text", {...valid, openingBalance: "500000"}],
    ["not an object", null],
  ])("rejects %s", (_label, data) => {
    expect(() => parseCreateWarungInput(data)).toThrowError();
  });
});
