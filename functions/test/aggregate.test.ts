import {describe, expect, it} from "vitest";

import {
  auditSale, isLateSync, productDeltaForSale, summaryDeltaForMove, summaryDeltaForSale,
} from "../src/reports/aggregate";

const sale = {
  items: [
    {productId: "indomie", qty: 2, price: 3500, subtotal: 7000},
    {productId: "aqua", qty: 1, price: 4000, subtotal: 4000},
    {productId: "kopi", qty: 3, price: 1500, subtotal: 4500},
  ],
  total: 15500,
  payment: "cash",
  dayKey: "2026-09-29",
};

describe("summaryDeltaForSale", () => {
  it("adds a cash sale to cash sales", () => {
    expect(summaryDeltaForSale(sale).fields).toEqual(
      {salesCash: 15500, salesCount: 1, itemsSold: 6});
  });

  it("keeps kasbon sales out of cash", () => {
    expect(summaryDeltaForSale({...sale, payment: "credit"}).fields).toEqual(
      {salesCredit: 15500, salesCount: 1, itemsSold: 6});
  });
});

describe("summaryDeltaForMove", () => {
  it("separates stock paid in cash from stock bought on debt", () => {
    expect(summaryDeltaForMove({kind: "purchase", amount: 134400, paidFrom: "cash"}).fields)
      .toEqual({purchasesCash: 134400});
    expect(summaryDeltaForMove({kind: "purchase", amount: 134400, paidFrom: "debt"}).fields)
      .toEqual({purchasesDebt: 134400});
  });

  it("keeps prive apart from business expenses", () => {
    const expense = summaryDeltaForMove({kind: "expense", amount: 25000, category: "Listrik"});
    expect(expense.fields).toEqual({expenses: 25000});
    expect(expense.expenseCategory).toEqual({name: "Listrik", amount: 25000});

    const prive = summaryDeltaForMove({kind: "prive", amount: 50000, category: "Pribadi"});
    expect(prive.fields).toEqual({prive: 50000});
    expect(prive.expenseCategory).toBeUndefined();
  });

  it("files an expense without a category under Lainnya", () => {
    expect(summaryDeltaForMove({kind: "expense", amount: 1000}).expenseCategory)
      .toEqual({name: "Lainnya", amount: 1000});
  });

  it("counts kasbon paid back and supplier debt paid off", () => {
    expect(summaryDeltaForMove({kind: "debtPayment", amount: 30000}).fields)
      .toEqual({debtCollected: 30000});
    expect(summaryDeltaForMove({kind: "supplierPayment", amount: 150000}).fields)
      .toEqual({supplierPayments: 150000});
  });

  it("counts a refund as cash out only when the sale was paid in cash", () => {
    expect(summaryDeltaForMove({kind: "refund", amount: 8000, salePayment: "cash"}).fields)
      .toEqual({refunds: 8000, voidedCount: 1});
    expect(summaryDeltaForMove({kind: "refund", amount: 8000, salePayment: "credit"}).fields)
      .toEqual({refundsCredit: 8000, voidedCount: 1});
  });

  it("ignores unknown kinds", () => {
    expect(summaryDeltaForMove({kind: "bonus", amount: 1}).fields).toEqual({});
  });
});

describe("productDeltaForSale", () => {
  it("lists pieces and revenue per product", () => {
    expect(productDeltaForSale(sale)).toEqual({
      indomie: {qty: 2, revenue: 7000},
      aqua: {qty: 1, revenue: 4000},
      kopi: {qty: 3, revenue: 4500},
    });
  });

  it("takes them back out for a void", () => {
    expect(productDeltaForSale(sale, -1).indomie).toEqual({qty: -2, revenue: -7000});
  });

  it("adds up a product that appears twice", () => {
    const twice = {items: [
      {productId: "aqua", qty: 1, price: 4000, subtotal: 4000},
      {productId: "aqua", qty: 2, price: 4000, subtotal: 8000},
    ]};
    expect(productDeltaForSale(twice)).toEqual({aqua: {qty: 3, revenue: 12000}});
  });
});

describe("auditSale", () => {
  it("passes a sale whose numbers add up", () => {
    expect(auditSale(sale)).toBeNull();
  });

  it("catches a total that is not the sum of the items", () => {
    expect(auditSale({...sale, total: 15000})).toMatch(/total/i);
  });

  it("catches a subtotal that is not quantity times price", () => {
    const items = [{productId: "aqua", qty: 2, price: 4000, subtotal: 4000}];
    expect(auditSale({items, total: 4000})).toMatch(/subtotal/i);
  });

  it("catches invalid quantities and prices", () => {
    const item = {productId: "aqua", qty: 1, price: 4000, subtotal: 4000};
    expect(auditSale({items: [{...item, qty: 0, subtotal: 0}], total: 0})).toMatch(/quantity/i);
    expect(auditSale({items: [{...item, qty: 1.5, subtotal: 6000}], total: 6000})).toMatch(/quantity/i);
    expect(auditSale({items: [{...item, price: -1, subtotal: -1}], total: -1})).toMatch(/price/i);
  });

  it("catches a sale with no items", () => {
    expect(auditSale({items: [], total: 0})).toMatch(/no items/i);
  });
});

describe("isLateSync", () => {
  const openedAt = Date.parse("2026-10-06T16:30:00Z");

  it("flags a record made before the open period started", () => {
    expect(isLateSync(openedAt - 60_000, openedAt)).toBe(true);
  });

  it("does not flag a record made in the open period", () => {
    expect(isLateSync(openedAt, openedAt)).toBe(false);
    expect(isLateSync(openedAt + 1, openedAt)).toBe(false);
  });

  it("does not flag anything when a time is missing", () => {
    expect(isLateSync(undefined, openedAt)).toBe(false);
    expect(isLateSync(openedAt - 1, undefined)).toBe(false);
  });
});
