# DESIGN NOTE — ERC-223 Token Implementation

---

## 1. Standard Selected

**ERC-223** — Token with transaction handling model  
Specification: https://eips.ethereum.org/EIPS/eip-223  
Status: Final (as of 2023)

---

## 2. Scope Implemented

This implementation covers all parts required by the Web3Bridge Eviction Test Part 2:

| Requirement | Implemented |
|-------------|-------------|
| Fungible token with `name`, `symbol`, `decimals`, `totalSupply`, `balanceOf` | Yes |
| `transfer(address, uint256)` — simple transfer | Yes |
| `transfer(address, uint256, bytes)` — transfer with data payload | Yes |
| Transfer to EOA: update balances, emit event, succeed | Yes |
| Transfer to contract: call `tokenReceived`, revert on failure | Yes |
| `tokenReceived(address, uint256, bytes)` receiver hook | Yes |
| Transfer to non-implementing contract must revert | Yes |
| Transfer to rejecting receiver must revert | Yes |
| Balance atomicity: revert rolls back balance changes | Yes |
| `Transfer` event with `(address indexed, address indexed, uint256, bytes)` | Yes |
| Custom errors for insufficient balance, zero address, rejected receiver | Yes |
| Foundry tests with mock contracts | Yes |
| Deploy script with no hardcoded secrets | Yes |

**What was NOT implemented** (deliberately out of scope):
- `approve` / `allowance` / `transferFrom` (these are ERC-20 patterns; ERC-223 replaces them)
- `mint` / `burn` after deployment
- Any inscription or metadata storage beyond the `data` bytes parameter

---

## 3. Specification Mapping

### Functions

| Function | ERC-223 Spec Section | Notes |
|----------|----------------------|-------|
| `totalSupply()` | Token Methods → `totalSupply` | Identical to ERC-20 |
| `name()` | Token Methods → `name` | OPTIONAL per spec |
| `symbol()` | Token Methods → `symbol` | OPTIONAL per spec |
| `decimals()` | Token Methods → `decimals` | OPTIONAL per spec |
| `balanceOf(address)` | Token Methods → `balanceOf` | Identical to ERC-20 |
| `transfer(address, uint)` | Token Methods → `transfer(address, uint)` | Must call `tokenReceived` for contracts |
| `transfer(address, uint, bytes)` | Token Methods → `transfer(address, uint, bytes)` | Must call `tokenReceived` for contracts |

### Events

| Event | Spec Signature | Our Signature |
|-------|---------------|---------------|
| `Transfer` | `event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data)` | Identical |

### Receiver Interface

| Item | Spec | Implementation |
|------|------|----------------|
| Function name | `tokenReceived` | `tokenReceived` |
| Parameters | `(address _from, uint _value, bytes calldata _data)` | `(address _from, uint256 _value, bytes calldata _data)` |
| Return type | `bytes4` | `bytes4` |
| Magic value | `0x8943ec02` | Validated on every contract transfer |
| On rejection | Transaction must revert | `revert ReceiverRejected(_to)` if wrong return or revert |

---

## 4. Hardest Design Decisions

### Decision 1: EOA vs Contract Detection — `address.code.length > 0`

**The challenge:** We need to know whether the transfer recipient is a plain wallet (EOA) or a smart contract, to decide whether to call `tokenReceived`.

**The approach:** `_to.code.length > 0` — if deployed code exists at the address, it is a contract.  

**Known limitation:** During a contract's constructor, `extcodesize` is 0 even though the address is a contract-in-creation. This is documented explicitly in the ERC-223 spec:  
> *"It is unsafe to assume that an address for which this function returns false is an externally-owned account (EOA) and not a contract."*

We accept this limitation because it matches the spec's reference implementation exactly. Attempting to solve it would require more complexity than the scoped task allows.

---

### Decision 2: Order of Operations — Balance Update BEFORE Hook Call (CEI)

**The challenge:** When should we update balances relative to calling the receiver hook?

**The approach:** We follow **Checks-Effects-Interactions (CEI)**:
1. CHECK: validate sender balance, destination address
2. EFFECT: deduct from sender, credit recipient
3. INTERACT: call `tokenReceived` if recipient is a contract
4. EMIT: `Transfer` event

The spec explicitly states:  
> *"The tokenReceived function of _to MUST be called after all other operations to avoid re-entrancy attacks."*

**Why this is safe despite looking wrong:** If `tokenReceived` reverts, the EVM atomically rolls back the **entire transaction** — including the balance changes made in step 2. There is no way for tokens to be "stuck" in a partially-updated state. Solidity's state model guarantees this.

---

### Decision 3: Magic Return Value Validation

**The challenge:** How strictly should we enforce that the receiver returned the correct magic value `0x8943ec02`?

**The approach:** We call `tokenReceived` using the `IERC223Receiver` interface, which means:
- If the function **doesn't exist** → the call will revert with an EVM-level low-level error (bubbled up)
- If the function **exists but returns wrong value** → we check the return value and `revert ReceiverRejected(_to)`
- If the function **reverts deliberately** → the revert propagates up

This strict checking is required by the spec:  
> *"The tokenReceived function must return `0x8943ec02` after handling an incoming token transfer."*

The spec also says transfers to contracts without `tokenReceived` MUST revert. By using the typed interface (not a low-level `call`), we get automatic revert-on-missing-function behaviour from the ABI layer.

---

## 5. Why ERC-223 Prevents the Scoped ERC-20 Failure Mode

The ERC-20 `transfer(address, uint256)` function updates balances in the token contract but **never notifies the recipient contract**. If you send tokens to a contract that does not know to expect them, the contract's state does not reflect the deposit — and since the tokens are already debited from your balance in the token contract, **they are permanently lost**.

As of May 2023, the ERC-223 spec documents that **$201M worth of tokens have been lost** on Ethereum mainnet this way.

ERC-223 solves this by making the token transfer **actively call the recipient** via `tokenReceived`. If the recipient has no such function, the entire transfer reverts. The sender's balance is never reduced unless the recipient explicitly acknowledged and accepted the tokens. This mirrors how native ETH transfers work: a contract that doesn't accept ETH (e.g. no `receive()`) will cause the send to revert.

---

## 6. AI Usage Disclosure

This implementation was produced with the assistance of **Google Antigravity (AI coding assistant)**, which generated the initial code for:
- `src/IERC223Receiver.sol`
- `src/ERC223Token.sol`
- `test/ERC223Token.t.sol`
- `script/Deploy.s.sol`
- `README.md`
- `DESIGN_NOTE.md`

The student:
- Defined all requirements and design constraints
- Reviewed every generated file before accepting it
- Verified the generated code against the published ERC-223 specification
- Ran `forge build` and `forge test -vv` to confirm correctness
- Corrected compilation errors (unicode literals, event reference syntax, lint config)
- Made the final decision on every design choice described in Section 4

**AI did not write this code independently.** The student directed, reviewed, corrected, and validated all generated output.

---

*Standard reference: ERC-223 by Dexaran, created 2017-05-03, status Final.*  
*Source: https://eips.ethereum.org/EIPS/eip-223*
