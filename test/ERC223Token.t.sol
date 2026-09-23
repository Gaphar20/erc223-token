// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console} from "forge-std/Test.sol";
import {ERC223Token} from "../src/ERC223Token.sol";
import {IERC223Receiver} from "../src/IERC223Receiver.sol";

// ════════════════════════════════════════════════════════════════════════════
// Mock Contracts
// ════════════════════════════════════════════════════════════════════════════

/// @notice AcceptingReceiver - implements tokenReceived correctly.
///         Records the last call's parameters so tests can assert them.
contract AcceptingReceiver is IERC223Receiver {
    address public lastFrom;
    uint256 public lastValue;
    bytes public lastData;
    uint256 public callCount;

    function tokenReceived(address _from, uint256 _value, bytes calldata _data) external override returns (bytes4) {
        lastFrom = _from;
        lastValue = _value;
        lastData = _data;
        callCount += 1;
        return 0x8943ec02; // ERC-223 magic value
    }
}

/// @notice RejectingReceiver — implements tokenReceived but always reverts.
///         Simulates a contract that explicitly refuses the deposit.
contract RejectingReceiver is IERC223Receiver {
    function tokenReceived(address, uint256, bytes calldata) external pure override returns (bytes4) {
        revert("RejectingReceiver: transfer not accepted");
    }
}

/// @notice NonReceiver — a contract with NO tokenReceived function at all.
///         Simulates accidentally sending tokens to a contract (e.g. an exchange
///         contract, a DAO vault) that was never upgraded to understand ERC-223.
contract NonReceiver {
    // Intentionally empty - no tokenReceived
    function doNothing() external pure returns (bool) {
        return true;
    }
}

contract WrongMagicReceiver is IERC223Receiver {
    function tokenReceived(address, uint256, bytes calldata) external pure override returns (bytes4) {
        return 0x12345678;
    }
}

// ════════════════════════════════════════════════════════════════════════════
// Main Test Suite
// ════════════════════════════════════════════════════════════════════════════

contract ERC223TokenTest is Test {
    // Redeclare the Transfer event so vm.expectEmit can reference it locally.
    // (Solidity does not allow `emit ContractType.Event(...)` from outside.)
    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data);

    // ---- Fixtures -----------------------------------------------------------

    ERC223Token internal token;
    AcceptingReceiver internal accepting;
    RejectingReceiver internal rejecting;
    NonReceiver internal nonReceiver;
    WrongMagicReceiver internal wrongMagic;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 internal constant INITIAL_SUPPLY = 1_000_000e18;

    // ── Setup ────────────────────────────────────────────────────────────────

    function setUp() public {
        // Deploy token; msg.sender (this test contract) receives INITIAL_SUPPLY.
        token = new ERC223Token("Web3Bridge Token", "W3B", 18, INITIAL_SUPPLY);

        // Deploy mocks.
        accepting = new AcceptingReceiver();
        rejecting = new RejectingReceiver();
        nonReceiver = new NonReceiver();
        wrongMagic = new WrongMagicReceiver();

        // Fund alice with 10 000 tokens for transfer tests.
        token.transfer(alice, 10_000e18);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 1. Metadata / View Functions
    // ════════════════════════════════════════════════════════════════════════

    function test_metadata() public view {
        assertEq(token.name(), "Web3Bridge Token");
        assertEq(token.symbol(), "W3B");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), INITIAL_SUPPLY);
    }

    function test_initialBalances() public view {
        // setUp sent 10 000 to alice; the remainder stays with this contract.
        assertEq(token.balanceOf(alice), 10_000e18);
        assertEq(token.balanceOf(address(this)), INITIAL_SUPPLY - 10_000e18);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 2. Successful transfer to an EOA  (Requirement 1, 3)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToEOA_succeeds() public {
        uint256 amount = 100e18;
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 bobBefore = token.balanceOf(bob);

        vm.prank(alice);
        bool ok = token.transfer(bob, amount);

        assertTrue(ok, "transfer should return true");
        assertEq(token.balanceOf(alice), aliceBefore - amount, "alice balance decreased");
        assertEq(token.balanceOf(bob), bobBefore + amount, "bob balance increased");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 3. Transfer event is emitted correctly  (Requirement 9)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToEOA_emitsTransferEvent() public {
        uint256 amount = 50e18;
        bytes memory data = "";

        // Declare which topics to check: topic1 (from), topic2 (to), NO topic3,
        // and check the data field.
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, amount, data);

        vm.prank(alice);
        token.transfer(bob, amount);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 4. Successful transfer to an AcceptingReceiver  (Requirement 2, 8)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToAcceptingReceiver_succeeds() public {
        uint256 amount = 200e18;
        uint256 aliceBefore = token.balanceOf(alice);

        vm.prank(alice);
        bool ok = token.transfer(address(accepting), amount);

        assertTrue(ok);
        assertEq(token.balanceOf(alice), aliceBefore - amount, "alice balance decreased");
        assertEq(token.balanceOf(address(accepting)), amount, "accepting receiver balance increased");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 5. Receiver callback is invoked with correct parameters  (Requirement 10)
    // ════════════════════════════════════════════════════════════════════════

    function test_receiverCallbackParameters() public {
        uint256 amount = 300e18;
        bytes memory data = abi.encode("hello ERC-223");

        vm.prank(alice);
        token.transfer(address(accepting), amount, data);

        // Verify the callback received exactly what was sent.
        assertEq(accepting.lastFrom(), alice, "from should be alice");
        assertEq(accepting.lastValue(), amount, "value should match");
        assertEq(accepting.lastData(), data, "data should match");
        assertEq(accepting.callCount(), 1, "callback called exactly once");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 6. Transfer with arbitrary bytes data  (Requirement 3)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferWithArbitraryBytesData() public {
        bytes memory arbitraryData = hex"deadbeef0102030405060708090a0b0c0d0e0f";

        vm.prank(alice);
        bool ok = token.transfer(address(accepting), 1e18, arbitraryData);

        assertTrue(ok);
        assertEq(accepting.lastData(), arbitraryData, "arbitrary data passed through");
    }

    function test_transferWithEmptyData() public {
        bytes memory emptyData = "";

        vm.prank(alice);
        bool ok = token.transfer(address(accepting), 1e18, emptyData);

        assertTrue(ok);
        assertEq(accepting.lastData(), emptyData);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 7. Transfer event emitted for contract receiver  (Requirement 9)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToContract_emitsTransferEvent() public {
        uint256 amount = 50e18;
        bytes memory data = abi.encode("contract payload");

        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, address(accepting), amount, data);

        vm.prank(alice);
        token.transfer(address(accepting), amount, data);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 8. FAILURE: Transfer to NonReceiver must revert  (Requirement 4, 6, 8)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToNonReceiver_reverts() public {
        uint256 amount = 100e18;
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 nonReceiverBefore = token.balanceOf(address(nonReceiver));

        // The call reverts because NonReceiver has no tokenReceived function.
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(nonReceiver), amount);

        // ── Requirement 7 & 8: balances must be unchanged after failure ──────
        assertEq(token.balanceOf(alice), aliceBefore, "alice balance unchanged after revert");
        assertEq(token.balanceOf(address(nonReceiver)), nonReceiverBefore, "nonReceiver balance unchanged");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 9. FAILURE: Transfer to RejectingReceiver must revert  (Requirement 5, 7, 8)
    // ════════════════════════════════════════════════════════════════════════

    function test_transferToRejectingReceiver_reverts() public {
        uint256 amount = 100e18;
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 rejectorBefore = token.balanceOf(address(rejecting));

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(rejecting), amount);

        // Balances must roll back -- no tokens stuck in the rejecting contract.
        assertEq(token.balanceOf(alice), aliceBefore, "alice balance unchanged after revert");
        assertEq(token.balanceOf(address(rejecting)), rejectorBefore, "rejector balance unchanged - no stuck tokens");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 10. FAILURE: Insufficient balance must revert  (Requirement 6)
    // ════════════════════════════════════════════════════════════════════════

    function test_insufficientBalance_reverts() public {
        uint256 aliceBalance = token.balanceOf(alice);
        uint256 tooMuch = aliceBalance + 1;

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("InsufficientBalance(uint256,uint256)", aliceBalance, tooMuch));
        token.transfer(bob, tooMuch);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 11. Receiver callback NOT called for EOA transfers  (Requirement 3)
    // ════════════════════════════════════════════════════════════════════════

    function test_noCallbackForEOA() public {
        // AcceptingReceiver starts with callCount == 0.
        // Sending to bob (EOA) must not call the accepting receiver at all.
        vm.prank(alice);
        token.transfer(bob, 1e18);

        assertEq(accepting.callCount(), 0, "tokenReceived must NOT be called for EOA transfers");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 12. Balances unchanged after any failure  (Requirement 7)
    // ════════════════════════════════════════════════════════════════════════

    function test_failedTransfer_senderBalanceUnchanged() public {
        uint256 aliceBefore = token.balanceOf(alice);

        // This will revert (NonReceiver has no hook).
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(nonReceiver), 1e18);

        assertEq(token.balanceOf(alice), aliceBefore, "sender balance must be unchanged after failed transfer");
    }

    // ════════════════════════════════════════════════════════════════════════
    // 13. transfer(address, uint) overload also triggers receiver callback
    // ════════════════════════════════════════════════════════════════════════

    function test_simpleTransferOverload_callsReceiver() public {
        uint256 amount = 500e18;

        vm.prank(alice);
        // two-arg overload must still trigger tokenReceived for a contract
        bool ok = token.transfer(address(accepting), amount);

        assertTrue(ok);
        assertEq(accepting.callCount(), 1, "tokenReceived called via 2-arg overload");
        assertEq(accepting.lastValue(), amount);
    }

    // ════════════════════════════════════════════════════════════════════════
    // 14. Two-arg overload also reverts for NonReceiver
    // ════════════════════════════════════════════════════════════════════════

    function test_simpleTransferToNonReceiver_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(nonReceiver), 1e18);
    }

    function test_transferToWrongMagicReceiver_reverts() public {
        uint256 amount = 100e18;
        uint256 aliceBefore = token.balanceOf(alice);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("ReceiverRejected(address)", address(wrongMagic)));
        token.transfer(address(wrongMagic), amount);

        assertEq(token.balanceOf(alice), aliceBefore);
        assertEq(token.balanceOf(address(wrongMagic)), 0);
    }
}
