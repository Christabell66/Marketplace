import { describe, it, beforeEach, expect } from 'vitest';

// Mocking the Simple Marketplace contract for testing purposes
const mockMarketplace = {
  state: {
    items: {} as Record<number, { owner: string, price: number, title: string, isListed: boolean }>, // Maps item IDs to item details
    nextItemId: 1,  // Item ID counter starts at 1
  },

  listItem: (price: number, title: string, sender: string) => {
    const itemId = mockMarketplace.state.nextItemId;
    mockMarketplace.state.items[itemId] = {
      owner: sender,
      price: price,
      title: title,
      isListed: true,
    };
    mockMarketplace.state.nextItemId += 1;
    return { value: itemId };
  },

  purchaseItem: (itemId: number, sender: string, stxTransfer: (amount: number, to: string) => boolean) => {
    const item = mockMarketplace.state.items[itemId];
    if (!item) {
      return { error: 404 };  // Item not found
    }
    if (!item.isListed) {
      return { error: 404 };  // Item not listed
    }
    const price = item.price;
    const seller = item.owner;

    const transferSuccessful = stxTransfer(price, seller);
    if (!transferSuccessful) {
      return { error: 401 };  // Wrong price or failed transfer
    }

    mockMarketplace.state.items[itemId] = {
      owner: sender,
      price: price,
      title: item.title,
      isListed: false,
    };
    return { value: true };
  },

  getItem: (itemId: number) => {
    return mockMarketplace.state.items[itemId] || null;
  },
};

// Mocking the STX transfer function for testing purposes
const mockStxTransfer = (amount: number, to: string) => {
  return amount > 0 && to.length > 0; // Always return true if amount is positive and recipient exists
};

describe('Simple Marketplace Contract', () => {
  let user1: string, user2: string;

  beforeEach(() => {
    // Initialize mock state and user principals
    user1 = 'ST1234...';  // User 1 (potential seller)
    user2 = 'ST5678...';  // User 2 (potential buyer)

    mockMarketplace.state = {
      items: {},
      nextItemId: 1,
    };
  });

  it('should allow a user to list an item for sale', () => {
    const result = mockMarketplace.listItem(100, 'Cool Item', user1);
    expect(result).toEqual({ value: 1 });  // Item ID should be 1
    expect(mockMarketplace.state.items[1]).toEqual({
      owner: user1,
      price: 100,
      title: 'Cool Item',
      isListed: true,
    });
  });

  it('should not allow purchase of an unlisted item', () => {
    const result = mockMarketplace.purchaseItem(1, user2, mockStxTransfer);
    expect(result).toEqual({ error: 404 });  // Item not found or not listed
  });

  it('should allow a user to purchase a listed item', () => {
    // First, list an item
    mockMarketplace.listItem(100, 'Cool Item', user1);

    // Now, user2 attempts to purchase the item
    const result = mockMarketplace.purchaseItem(1, user2, mockStxTransfer);
    expect(result).toEqual({ value: true });

    // Verify item status after purchase
    expect(mockMarketplace.state.items[1]).toEqual({
      owner: user2,  // Ownership transferred to user2
      price: 100,
      title: 'Cool Item',
      isListed: false,  // Item is no longer listed
    });
  });

  it('should return the correct item details', () => {
    mockMarketplace.listItem(100, 'Cool Item', user1);

    const result = mockMarketplace.getItem(1);
    expect(result).toEqual({
      owner: user1,
      price: 100,
      title: 'Cool Item',
      isListed: true,
    });
  });

  it('should return null for a non-existent item', () => {
    const result = mockMarketplace.getItem(999);
    expect(result).toBeNull();
  });

  it('should reject a purchase if the price is wrong', () => {
    // List an item
    mockMarketplace.listItem(100, 'Cool Item', user1);

    // User2 attempts to purchase the item with incorrect STX amount
    const result = mockMarketplace.purchaseItem(1, user2, (amount: number, to: string) => amount !== 100);
    expect(result).toEqual({ error: 401 });  // Wrong price
  });

  it('should reject purchase if transfer fails', () => {
    // List an item
    mockMarketplace.listItem(100, 'Cool Item', user1);

    // User2 attempts to purchase the item, but STX transfer fails (mock failure)
    const result = mockMarketplace.purchaseItem(1, user2, (amount: number, to: string) => false);
    expect(result).toEqual({ error: 401 });  // STX transfer failed
  });
});
