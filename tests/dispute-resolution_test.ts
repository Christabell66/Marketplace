import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.0.0/index.ts';
import { assertEquals } from 'https://deno.land/std@0.90.0/testing/asserts.ts';

Clarinet.test({
    name: "Can file a dispute successfully",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;
        const buyer = accounts.get('wallet_1')!;
        const seller = accounts.get('wallet_2')!;

        let block = chain.mineBlock([
            Tx.contractCall('dispute-resolution', 'file-dispute', [
                types.uint(1), // item-id
                types.principal(seller.address), // seller
                types.ascii("quality-issue"), // dispute-type
                types.ascii("Item not as described"), // dispute-reason
                types.uint(1000) // transaction-amount
            ], buyer.address)
        ]);

        // Should return dispute ID 1
        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectOk(), types.uint(1));
        
        // Check dispute was created properly
        let disputeResult = chain.callReadOnlyFn('dispute-resolution', 'get-dispute', [
            types.uint(1)
        ], deployer.address);
        
        let dispute = disputeResult.result.expectSome().expectTuple();
        assertEquals(dispute['item-id'], types.uint(1));
        assertEquals(dispute['buyer'], types.principal(buyer.address));
        assertEquals(dispute['seller'], types.principal(seller.address));
        assertEquals(dispute['status'], types.ascii("filed"));
    },
});

Clarinet.test({
    name: "Can register as mediator with sufficient stake",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const mediator = accounts.get('wallet_3')!;

        let block = chain.mineBlock([
            Tx.contractCall('dispute-resolution', 'register-mediator', [
                types.uint(1000), // stake-amount (minimum required)
                types.list([types.ascii("general"), types.ascii("tech")]) // specialties
            ], mediator.address)
        ]);

        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectOk(), types.bool(true));
        
        // Check mediator was registered properly
        let mediatorResult = chain.callReadOnlyFn('dispute-resolution', 'get-mediator-info', [
            types.principal(mediator.address)
        ], mediator.address);
        
        let mediatorInfo = mediatorResult.result.expectSome().expectTuple();
        assertEquals(mediatorInfo['stake-amount'], types.uint(1000));
        assertEquals(mediatorInfo['active'], types.bool(true));
        assertEquals(mediatorInfo['reputation-score'], types.uint(100));
    },
});

Clarinet.test({
    name: "Cannot register as mediator with insufficient stake",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const mediator = accounts.get('wallet_3')!;

        let block = chain.mineBlock([
            Tx.contractCall('dispute-resolution', 'register-mediator', [
                types.uint(500), // insufficient stake (minimum is 1000)
                types.list([types.ascii("general")]) // specialties
            ], mediator.address)
        ]);

        assertEquals(block.receipts.length, 1);
        assertEquals(block.receipts[0].result.expectErr(), types.uint(425)); // ERR-INSUFFICIENT-STAKE
    },
});

Clarinet.test({
    name: "Can calculate dispute fee correctly",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const deployer = accounts.get('deployer')!;

        // Test with small transaction (should use base fee)
        let smallFeeResult = chain.callReadOnlyFn('dispute-resolution', 'calculate-dispute-fee-preview', [
            types.uint(100)
        ], deployer.address);
        assertEquals(smallFeeResult.result.expectUint(), 50); // base fee of 50 STX

        // Test with large transaction (should use percentage)
        let largeFeeResult = chain.callReadOnlyFn('dispute-resolution', 'calculate-dispute-fee-preview', [
            types.uint(2000)
        ], deployer.address);
        assertEquals(largeFeeResult.result.expectUint(), 100); // 5% of 2000 = 100 STX
    },
});

Clarinet.test({
    name: "Can submit evidence for a dispute",
    async fn(chain: Chain, accounts: Map<string, Account>) {
        const buyer = accounts.get('wallet_1')!;
        const seller = accounts.get('wallet_2')!;

        // First file a dispute
        let disputeBlock = chain.mineBlock([
            Tx.contractCall('dispute-resolution', 'file-dispute', [
                types.uint(1),
                types.principal(seller.address),
                types.ascii("quality-issue"),
                types.ascii("Item not as described"),
                types.uint(1000)
            ], buyer.address)
        ]);

        // Then submit evidence
        let evidenceBlock = chain.mineBlock([
            Tx.contractCall('dispute-resolution', 'submit-evidence', [
                types.uint(1), // dispute-id
                types.ascii("photo"), // evidence-type
                types.ascii("abc123hash"), // evidence-hash
                types.ascii("Photo showing damage") // description
            ], buyer.address)
        ]);

        assertEquals(evidenceBlock.receipts.length, 1);
        assertEquals(evidenceBlock.receipts[0].result.expectOk(), types.uint(1)); // evidence-id

        // Check evidence was submitted
        let evidenceResult = chain.callReadOnlyFn('dispute-resolution', 'get-dispute-evidence', [
            types.uint(1), // dispute-id
            types.uint(1)  // evidence-id
        ], buyer.address);
        
        let evidence = evidenceResult.result.expectSome().expectTuple();
        assertEquals(evidence['submitter'], types.principal(buyer.address));
        assertEquals(evidence['evidence-type'], types.ascii("photo"));
    },
});
