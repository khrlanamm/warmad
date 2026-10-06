import {HttpsError} from "firebase-functions/v2/https";

export interface OpeningHours {
  is24h: boolean;
  /** "HH:mm", only when not open 24 hours. */
  open?: string;
  close?: string;
}

export interface CreateWarungInput {
  name: string;
  phone: string;
  address: string;
  lat: number;
  lng: number;
  hours: OpeningHours;
  showOnMap: boolean;
  /** Cash in the drawer when the warung starts using the app, in Rupiah. */
  openingBalance: number;
}

const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function text(value: unknown, label: string, max: number): string {
  if (typeof value !== "string") invalid(`${label} wajib diisi.`);
  const trimmed = value.trim();
  if (trimmed.length === 0) invalid(`${label} wajib diisi.`);
  if (trimmed.length > max) invalid(`${label} terlalu panjang.`);
  return trimmed;
}

/** Whole, non-negative Rupiah. Money is never a fraction. */
export function rupiah(value: unknown, label: string): number {
  if (typeof value !== "number" || !Number.isSafeInteger(value) || value < 0) {
    invalid(`${label} harus angka bulat dan tidak boleh minus.`);
  }
  return value;
}

function hours(value: unknown): OpeningHours {
  if (typeof value !== "object" || value === null) invalid("Jam buka wajib diisi.");
  const raw = value as Record<string, unknown>;
  if (typeof raw.is24h !== "boolean") invalid("Jam buka wajib diisi.");
  if (raw.is24h) return {is24h: true};
  if (typeof raw.open !== "string" || !TIME.test(raw.open) ||
      typeof raw.close !== "string" || !TIME.test(raw.close)) {
    invalid("Jam buka dan jam tutup harus diisi.");
  }
  return {is24h: false, open: raw.open, close: raw.close};
}

export function parseCreateWarungInput(data: unknown): CreateWarungInput {
  if (typeof data !== "object" || data === null) invalid("Data warung tidak lengkap.");
  const raw = data as Record<string, unknown>;

  const phone = text(raw.phone, "Nomor HP", 20).replace(/[\s-]/g, "");
  if (!/^\+?\d{8,15}$/.test(phone)) invalid("Nomor HP tidak valid.");

  const {lat, lng} = raw;
  if (typeof lat !== "number" || typeof lng !== "number" ||
      !(lat >= -90 && lat <= 90) || !(lng >= -180 && lng <= 180)) {
    invalid("Lokasi warung belum dipilih.");
  }
  if (typeof raw.showOnMap !== "boolean") invalid("Pilihan tampil di peta belum diisi.");

  return {
    name: text(raw.name, "Nama warung", 60),
    phone,
    address: text(raw.address, "Alamat", 200),
    lat,
    lng,
    hours: hours(raw.hours),
    showOnMap: raw.showOnMap,
    openingBalance: rupiah(raw.openingBalance, "Saldo awal kas"),
  };
}
