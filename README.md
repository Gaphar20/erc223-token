# ERC-223 Token — Web3Bridge Eviction Test Part 2

## What Was Implemented

A minimal, spec-faithful ERC-223 fungible token built with **Solidity `^0.8.20`** and **Foundry only**.

| File | Purpose |
|------|---------|
| `src/IERC223Receiver.sol` | Interface contracts must implement to accept ERC-223 tokens |
| `src/ERC223Token.sol` | The ERC-223 token contract |
| `test/ERC223Token.t.sol` | Foundry test suite (16 tests) |
| `script/Deploy.s.sol` | Deployment script (no hardcoded secrets) |

### Implemented Features

- `name()`, `symbol()`, `decimals()`, `totalSupply()`, `balanceOf(address)`
- `transfer(address, uint256)` — two-argument overload with empty data
- `transfer(address, uint256, bytes)` — three-argument overload with arbitrary bytes payload
- `Transfer` event: `event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data)` (exact spec signature)
- ERC-223 receiver detection: uses `address.code.length > 0` to distinguish contracts from EOAs
- `tokenReceived(address, uint256, bytes)` callback enforcement — reverts if not present or if it rejects
- Magic return value validation: `0x8943ec02` (`bytes4(keccak256("tokenReceived(address,uint256,bytes)"))`)
- Custom errors: `InsufficientBalance`, `ReceiverRejected`, `TransferToZeroAddress`
- Atomic revert behaviour: balance changes roll back if the receiver hook fails

### What Was Intentionally Left Out

| Feature | Reason |
|---------|--------|
| `approve` / `allowance` / `transferFrom` | Not part of ERC-223; this standard uses a single `transfer` path |
| `mint` / `burn` after construction | Out of scope — initial supply allocated to deployer in constructor |
| OpenZeppelin imports | Educational test; self-contained implementation is required |
| Frontend / scripts with hardcoded keys | Explicitly forbidden by task requirements |
| ERC-20 backwards compatibility shims | ERC-223 is intentionally different; compatibility was not required |

---

## How to Run

```bash
# Build
forge build

# Run tests (verbose)
forge test -vv

# Format
forge fmt
```

> **Note:** `forge` must be in your PATH, or use the full path: `~/.foundry/bin/forge`

### Deploy (testnet only — never hardcode keys)

```bash
export PRIVATE_KEY=<your-private-key>
forge script script/Deploy.s.sol --rpc-url <RPC_URL> --broadcast
```

---

## Test Results

```
Ran 16 tests for test/ERC223Token.t.sol:ERC223TokenTest
[PASS] test_failedTransfer_senderBalanceUnchanged()
[PASS] test_initialBalances()
[PASS] test_insufficientBalance_reverts()
[PASS] test_metadata()
[PASS] test_noCallbackForEOA()
[PASS] test_receiverCallbackParameters()
[PASS] test_simpleTransferOverload_callsReceiver()
[PASS] test_simpleTransferToNonReceiver_reverts()
[PASS] test_transferToAcceptingReceiver_succeeds()
[PASS] test_transferToContract_emitsTransferEvent()
[PASS] test_transferToEOA_emitsTransferEvent()
[PASS] test_transferToEOA_succeeds()
[PASS] test_transferToNonReceiver_reverts()
[PASS] test_transferToRejectingReceiver_reverts()
[PASS] test_transferWithArbitraryBytesData()
[PASS] test_transferWithEmptyData()
Suite result: ok. 16 passed; 0 failed; 0 skipped
```

---

## Specification Reference

[ERC-223 (Final)](https://eips.ethereum.org/EIPS/eip-223) by Dexaran, 2017-05-03.
