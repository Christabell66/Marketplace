# Marketplace
 
# Simple Marketplace Smart Contract

Welcome to the **Simple Marketplace Smart Contract**, a decentralized platform where users can list, browse, and purchase items securely and transparently on the blockchain. This project provides the core functionality for listing items, handling purchases, and querying item details. It's an excellent foundation for building fully decentralized e-commerce solutions.

## Features

### 1. **List an Item**
Users can list an item for sale by specifying the price (in STX) and a title (up to 50 ASCII characters). Each item is uniquely identified with an ID.  
**Function:** `list-item (price uint) (title (string-ascii 50))`  
**Returns:** The unique ID of the newly listed item.

### 2. **Purchase an Item**
Buyers can purchase listed items. Upon successful STX transfer to the seller, ownership of the item is updated, and the item is marked as unlisted.  
**Function:** `purchase-item (item-id uint)`  
**Returns:** Confirmation of purchase (`true`) or relevant error codes.  

### 3. **Query Item Details**
Retrieve all details of an item by its unique ID, including the owner, price, title, and listing status.  
**Function:** `get-item (item-id uint)`  
**Returns:** The item's details or `null` if the item doesn't exist.

---

## Error Handling
- **ERR-NOT-FOUND (`404`)**: Item not found or no longer listed.  
- **ERR-WRONG-PRICE (`401`)**: Purchase failed due to incorrect STX transfer amount.  
- **ERR-NOT-OWNER (`403`)**: Unauthorized modification attempt by a non-owner.

---

## Unit Tests

The project includes a comprehensive suite of unit tests to ensure robust functionality:
1. **Listing Items:** Verifies that items can be listed with correct attributes.  
2. **Purchasing Items:** Ensures successful purchases update ownership and status.  
3. **Preventing Invalid Purchases:** Tests scenarios for incorrect prices or failed STX transfers.  
4. **Querying Items:** Confirms retrieval of correct item details and handles non-existent items gracefully.  
5. **Ownership Transfer:** Validates accurate ownership updates post-purchase.

---

## Usage

### Prerequisites
- A working Stacks blockchain development environment.  
- Testing framework (e.g., Vitest) for running unit tests.  

### Deployment
1. Deploy the contract using a Stacks-compatible wallet or development environment.  
2. Use the provided functions to interact with the contract for listing and purchasing items.

### Running Tests
Execute unit tests to validate the functionality using the provided mock implementation.  

---

## Potential Enhancements
- **Item Categories:** Add tags or categories for better item discovery.  
- **Dynamic Pricing:** Allow sellers to update item prices.  
- **Purchase Histories:** Maintain transaction histories for buyers and sellers.  
- **Batch Operations:** Enable bulk listing or purchases for efficiency.  

---

## Pull Request Description

**Title:** 🛒 Marketplace Magic: Build a Simple Decentralized Marketplace  

**Description:**  
Introducing the **Simple Marketplace Smart Contract**, a decentralized app for secure and transparent e-commerce on the blockchain. This PR adds:  
- **Core Features**: Listing, purchasing, and querying items.  
- **Error Handling**: Robust error codes for graceful failure management.  
- **Unit Tests**: Thorough tests covering core functionality and edge cases.  

This project lays the foundation for decentralized e-commerce. Looking forward to ideas for future enhancements and feedback from the community. 🌟