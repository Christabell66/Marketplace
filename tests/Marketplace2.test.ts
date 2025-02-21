import { describe, it, expect, beforeEach } from 'vitest';

// Mock contract state
let categories: Record<number, { categoryName: string }>;
let nextCategoryId: number;
let itemDiscounts: Record<number, number>;
let items: Record<number, { owner: string }>;
let reservations: Record<number, { reserver: string; expiry: number }>;

beforeEach(() => {
  // Reset state before each test
  categories = {};
  nextCategoryId = 1;
  itemDiscounts = {};
  items = {};
  reservations = {};
});

// Helper functions to simulate contract methods
function addCategory(categoryName: string) {
  const categoryId = nextCategoryId;
  categories[categoryId] = { categoryName };
  nextCategoryId += 1;
  return { ok: categoryId };
}

function setDiscount(itemId: number, discount: number, sender: string) {
  const item = items[itemId];
  if (!item) return { ok: false, error: 'ERR-NOT-FOUND' };
  if (item.owner !== sender) return { ok: false, error: 'ERR-NOT-OWNER' };
  if (discount > 100) return { ok: false, error: 401 }; // Discount exceeds 100%

  itemDiscounts[itemId] = discount;
  return { ok: true };
}

function reserveItem(itemId: number, sender: string, expiry: number) {
  const item = items[itemId];
  if (!item) return { ok: false, error: 'ERR-NOT-FOUND' };

  reservations[itemId] = { reserver: sender, expiry };
  return { ok: true };
}

// Tests
describe('Category Management Tests', () => {
  it('should add a new category', () => {
    const result = addCategory('Electronics');
    expect(result.ok).toBe(1);
    expect(categories[1]).toMatchObject({ categoryName: 'Electronics' });
  });

  it('should increment category ID on each addition', () => {
    addCategory('Electronics');
    const result = addCategory('Clothing');
    expect(result.ok).toBe(2);
    expect(categories[2]).toMatchObject({ categoryName: 'Clothing' });
  });
});

describe('Item Discount Tests', () => {
  beforeEach(() => {
    items[1] = { owner: 'owner_1' };
  });

  it('should set a discount for an item', () => {
    const result = setDiscount(1, 20, 'owner_1');
    expect(result.ok).toBe(true);
    expect(itemDiscounts[1]).toBe(20);
  });

  it('should reject setting discount if not the owner', () => {
    const result = setDiscount(1, 20, 'not_owner');
    expect(result.ok).toBe(false);
    expect(result.error).toBe('ERR-NOT-OWNER');
  });

  it('should reject discount greater than 100%', () => {
    const result = setDiscount(1, 120, 'owner_1');
    expect(result.ok).toBe(false);
    expect(result.error).toBe(401); // Discount exceeds 100%
  });

  it('should reject discount for non-existent item', () => {
    const result = setDiscount(999, 20, 'owner_1');
    expect(result.ok).toBe(false);
    expect(result.error).toBe('ERR-NOT-FOUND');
  });
});

describe('Item Reservation Tests', () => {
  beforeEach(() => {
    items[1] = { owner: 'owner_1' };
  });

  it('should reserve an item', () => {
    const result = reserveItem(1, 'user_1', 3600); // Expiry in seconds
    expect(result.ok).toBe(true);
    expect(reservations[1]).toMatchObject({ reserver: 'user_1', expiry: 3600 });
  });

  it('should reject reservation for non-existent item', () => {
    const result = reserveItem(999, 'user_1', 3600);
    expect(result.ok).toBe(false);
    expect(result.error).toBe('ERR-NOT-FOUND');
  });
});
