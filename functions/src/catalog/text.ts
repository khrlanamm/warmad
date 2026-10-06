/**
 * Turns a product name into the key used to recognise the same item across
 * warungs: "Indomie  Goreng!" and "indomie goreng" both give "indomie-goreng".
 */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[̀-ͯ]/g, "")
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
}

/**
 * Prefixes of every word in a name, used for type-ahead search with a single
 * `array-contains` filter. "Kopi Kapal" gives ko, kop, kopi, ka, kap, kapa,
 * kapal.
 */
export function searchPrefixes(name: string, maxLength = 12): string[] {
  const prefixes = new Set<string>();
  for (const word of slugify(name).split("-")) {
    for (let end = 2; end <= Math.min(word.length, maxLength); end++) {
      prefixes.add(word.slice(0, end));
    }
  }
  return [...prefixes];
}
