import { Clarinet, Tx, Chain, Account, types } from 'https://deno.land/x/clarinet@v1.5.0/index.ts';
import { assertEquals, assertObjectMatch } from 'https://deno.land/std@0.170.0/testing/asserts.ts';

Clarinet.test({
  name: "Verify P2P Penalty contract core scenarios",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const alice = accounts.get('wallet_1')!;
    const bob = accounts.get('wallet_2')!;
    const carol = accounts.get('wallet_3')!;

    // Create a penalty agreement
    let block = chain.mineBlock([
      Tx.contractCall('p2p-penalty-contract', 'create-penalty-agreement', [
        types.principal(bob.address),
        types.uint(1000000),
        types.utf8('Late project delivery')
      ], alice.address)
    ]);

    assertEquals(block.height, 2);
    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectUint(1);

    // Bob accepts the penalty
    block = chain.mineBlock([
      Tx.contractCall('p2p-penalty-contract', 'accept-penalty', [
        types.uint(1)
      ], bob.address)
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectBool(true);

    // File a dispute scenario
    block = chain.mineBlock([
      Tx.contractCall('p2p-penalty-contract', 'create-penalty-agreement', [
        types.principal(carol.address),
        types.uint(2000000),
        types.utf8('Breach of contract terms')
      ], alice.address),
      Tx.contractCall('p2p-penalty-contract', 'file-dispute', [
        types.uint(2),
        types.utf8('Disagreement on contract interpretation'),
        types.utf8('Supporting evidence attached')
      ], carol.address)
    ]);

    assertEquals(block.receipts.length, 2);
    block.receipts[1].result.expectOk().expectBool(true);
  }
});

Clarinet.test({
  name: "Test p2p-penalty contract administrative functions",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get('deployer')!;
    const alice = accounts.get('wallet_1')!;

    // Add a mediator
    let block = chain.mineBlock([
      Tx.contractCall('p2p-penalty-contract', 'add-mediator', [
        types.principal(alice.address)
      ], deployer.address)
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectBool(true);

    // Update mediation fee
    block = chain.mineBlock([
      Tx.contractCall('p2p-penalty-contract', 'update-mediation-fee', [
        types.uint(300) // 3%
      ], deployer.address)
    ]);

    assertEquals(block.receipts.length, 1);
    block.receipts[0].result.expectOk().expectBool(true);
  }
});