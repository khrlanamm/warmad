const BASE32 = "0123456789bcdefghjkmnpqrstuvwxyz";

/**
 * Encodes a coordinate as a geohash. Nearby places share a prefix, which is
 * what makes "warung near me" a range query in Firestore.
 */
export function encodeGeohash(lat: number, lng: number, precision = 9): string {
  let latRange: [number, number] = [-90, 90];
  let lngRange: [number, number] = [-180, 180];
  let hash = "";
  let bits = 0;
  let value = 0;
  let evenBit = true;

  while (hash.length < precision) {
    const range = evenBit ? lngRange : latRange;
    const coordinate = evenBit ? lng : lat;
    const mid = (range[0] + range[1]) / 2;
    if (coordinate >= mid) {
      value = (value << 1) | 1;
      range[0] = mid;
    } else {
      value = value << 1;
      range[1] = mid;
    }
    if (evenBit) lngRange = range;
    else latRange = range;
    evenBit = !evenBit;

    bits++;
    if (bits === 5) {
      hash += BASE32[value];
      bits = 0;
      value = 0;
    }
  }
  return hash;
}
