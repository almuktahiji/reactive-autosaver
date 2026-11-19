// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { SaveToken } from "../src/SaveToken.sol";
import { AutoSaverReactive } from "../src/AutoSaverReactive.sol";
import { AutoSaverVault } from "../src/AutoSaverVault.sol";

/// @notice Stand-in for the Reactive system contract (0x8888...8888).
/// Records subscriptions and callback requests so tests can assert on them.
contract MockSystem is ISystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddr;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    Subscription public lastSubscription;
    uint256 public subscriptionCount;
    CallbackConfiguration_V_1_0 public lastCallback;
    uint256 public callbackCount;

    receive() external payable {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external {
        lastSubscription = Subscription(chainId_, contract_, topic0_, topic1_, topic2_, topic3_);
        subscriptionCount++;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {}

    function requestCallback(CallbackVersion, bytes memory) external {}

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external {
        lastCallback = config_;
        callbackCount++;
    }
}

/// @notice Stand-in for a destination-chain callback proxy (IPayable).
contract MockProxy is IPayable {
    receive() external payable {}

    function debt(address) external pure returns (uint256) {
        return 0;
    }
}

contract AutoSaverTest is Test {
    address internal constant SYSTEM_ADDR = 0x8888888888888888888888888888888888888888;
    uint256 internal constant BASE_SEPOLIA = 84532;
    uint256 internal constant TRANSFER_TOPIC0 =
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    address internal owner = address(0xA11CE);
    address internal alice = address(0xA11C3);
    address internal bob = address(0xB0B);

    MockSystem internal mockSystem;
    MockProxy internal mockProxy;
    SaveToken internal token;
    AutoSaverReactive internal rsc;
    AutoSaverVault internal vault;

    function setUp() public {
        // Etch the mock system contract at the real SYSTEM address so the
        // RSC's subscribe()/requestCallbackV_1_0() calls land in the mock.
        mockSystem = new MockSystem();
        vm.etch(SYSTEM_ADDR, address(mockSystem).code);
        mockProxy = new MockProxy();

        vm.startPrank(owner);
        token = new SaveToken(owner);
        rsc = new AutoSaverReactive(address(token), owner);
        vault = new AutoSaverVault(address(token), IPayable(payable(address(mockProxy))), address(rsc));
        vm.stopPrank();

        // Demo setup: Alice holds SAVE and approved the vault.
        vm.prank(owner);
        token.mint(alice, 1_000_000 ether);
        vm.prank(alice);
        token.approve(address(vault), type(uint256).max);
    }

    // -- helpers ---------------------------------------------------------

    function _transferLog(address from, address to, uint256 amount)
        internal
        view
        returns (IReactive.LogRecord memory)
    {
        return
            IReactive.LogRecord({
                chainId: BASE_SEPOLIA,
                contractAddress: address(token),
                topic0: TRANSFER_TOPIC0,
                topic1: uint256(uint160(from)),
                topic2: uint256(uint160(to)),
                topic3: 0,
                data: abi.encode(amount),
                blockNumber: 1,
                opCode: 3,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function _reactAsSystem(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM_ADDR);
        rsc.react(log_);
    }

    function _expectedPayload(address user, uint256 sweepAmount) internal pure returns (bytes memory) {
        return abi.encodeWithSignature("sweep(address,address,uint256)", address(0), user, sweepAmount);
    }

    // -- subscription ----------------------------------------------------

    function testConstructorSubscribesToSaveTokenTransfers() public view {
        MockSystem sys = MockSystem(payable(SYSTEM_ADDR));
        (uint256 chainId, address contractAddr, uint256 topic0, uint256 topic1, uint256 topic2, uint256 topic3) = sys
            .lastSubscription();
        assertEq(chainId, BASE_SEPOLIA);
        assertEq(contractAddr, address(token));
        assertEq(topic0, TRANSFER_TOPIC0);
        uint256 ignore = 0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad; // REACTIVE_IGNORE
        assertEq(topic1, ignore);
        assertEq(topic2, ignore);
        assertEq(topic3, ignore);
        assertEq(sys.subscriptionCount(), 1);
    }

    // -- sweep math ------------------------------------------------------

    function testSweepMath10PercentOf1000() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        _reactAsSystem(_transferLog(bob, alice, 1000 ether));

        MockSystem sys = MockSystem(payable(SYSTEM_ADDR));
        assertEq(sys.callbackCount(), 1);
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) = sys.lastCallback();
        assertEq(chainId, BASE_SEPOLIA);
        assertEq(recipient, address(vault));
        assertEq(gasLimit, 400_000);
        assertEq(payload, _expectedPayload(alice, 100 ether));
        assertEq(rsc.totalSweepRequested(alice), 100 ether);
    }

    function testSweepMathRoundingDown() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        // 999 wei * 10 / 100 = 99.9 -> 99 wei (integer division rounds down).
        _reactAsSystem(_transferLog(bob, alice, 999));

        MockSystem sys = MockSystem(payable(SYSTEM_ADDR));
        assertEq(sys.callbackCount(), 1);
        (, , , bytes memory payload) = sys.lastCallback();
        assertEq(payload, _expectedPayload(alice, 99));
    }

    function testSweepMath100Percent() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 100);
        vm.prank(owner);
        rsc.setVault(address(vault));

        _reactAsSystem(_transferLog(bob, alice, 250 ether));

        MockSystem sys = MockSystem(payable(SYSTEM_ADDR));
        assertEq(sys.callbackCount(), 1);
        (, , , bytes memory payload) = sys.lastCallback();
        assertEq(payload, _expectedPayload(alice, 250 ether));
    }

    function testZeroPctNoCallback() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 0);
        vm.prank(owner);
        rsc.setVault(address(vault));

        _reactAsSystem(_transferLog(bob, alice, 1000 ether));

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testUnregisteredUserNoCallback() public {
        vm.prank(owner);
        rsc.setVault(address(vault));
        // Alice never registered: savingsPct == 0.
        assertEq(rsc.savingsPct(alice), 0);

        _reactAsSystem(_transferLog(bob, alice, 1000 ether));

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testNoVaultSetNoCallback() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        // Vault never set: react() must not request a callback to address(0).
        assertEq(rsc.vault(), address(0));

        _reactAsSystem(_transferLog(bob, alice, 1000 ether));

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    // -- react() routing: non-matching logs fall through, never revert ---

    function testReactIgnoresWrongTopic0() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        IReactive.LogRecord memory log_ = _transferLog(bob, alice, 1000 ether);
        log_.topic0 = uint256(keccak256("Approval(address,address,uint256)"));
        _reactAsSystem(log_);

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testReactIgnoresWrongOpCode() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        IReactive.LogRecord memory log_ = _transferLog(bob, alice, 1000 ether);
        log_.opCode = 1; // not a LOG3
        _reactAsSystem(log_);

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testReactIgnoresWrongContract() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        IReactive.LogRecord memory log_ = _transferLog(bob, alice, 1000 ether);
        log_.contractAddress = address(0xDEAD);
        _reactAsSystem(log_);

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testReactIgnoresWrongChain() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        IReactive.LogRecord memory log_ = _transferLog(bob, alice, 1000 ether);
        log_.chainId = 1;
        _reactAsSystem(log_);

        assertEq(MockSystem(payable(SYSTEM_ADDR)).callbackCount(), 0);
    }

    function testReactOnlySystem() public {
        vm.prank(alice);
        vm.expectRevert();
        rsc.react(_transferLog(bob, alice, 1000 ether));
    }

    // -- access control --------------------------------------------------

    function testOnlyOwnerCanSetSavingsPct() public {
        vm.prank(alice);
        vm.expectRevert();
        rsc.setSavingsPct(alice, 10);

        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        assertEq(rsc.savingsPct(alice), 10);
    }

    function testOnlyOwnerCanSetVault() public {
        vm.prank(alice);
        vm.expectRevert();
        rsc.setVault(address(vault));

        vm.prank(owner);
        rsc.setVault(address(vault));
        assertEq(rsc.vault(), address(vault));
    }

    function testSetSavingsPctAbove100Reverts() public {
        vm.prank(owner);
        vm.expectRevert("AutoSaverReactive: pct > 100");
        rsc.setSavingsPct(alice, 101);
    }

    function testSetSavingsPctZeroAddressReverts() public {
        vm.prank(owner);
        vm.expectRevert("AutoSaverReactive: zero user");
        rsc.setSavingsPct(address(0), 10);
    }

    // -- vault callback auth ---------------------------------------------

    function testVaultSweepHappyPath() public {
        uint256 aliceBefore = token.balanceOf(alice);
        uint256 vaultBefore = token.balanceOf(address(vault));

        vm.prank(address(mockProxy));
        vault.sweep(address(rsc), alice, 100 ether);

        assertEq(token.balanceOf(alice), aliceBefore - 100 ether);
        assertEq(token.balanceOf(address(vault)), vaultBefore + 100 ether);
        assertEq(vault.saved(alice), 100 ether);
        assertEq(vault.totalSaved(), 100 ether);
    }

    function testVaultRejectsNonProxyCaller() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.sweep(address(rsc), alice, 100 ether);
    }

    function testVaultRejectsWrongCallbackSender() public {
        vm.prank(address(mockProxy));
        vm.expectRevert();
        vault.sweep(address(0xDEAD), alice, 100 ether);
    }

    function testVaultRejectsZeroAmount() public {
        vm.prank(address(mockProxy));
        vm.expectRevert("AutoSaverVault: zero amount");
        vault.sweep(address(rsc), alice, 0);
    }

    function testVaultSweepWithoutApprovalReverts() public {
        // Bob never approved the vault: transferFrom must fail.
        vm.prank(owner);
        token.mint(bob, 1000 ether);

        vm.prank(address(mockProxy));
        vm.expectRevert();
        vault.sweep(address(rsc), bob, 100 ether);
    }

    // -- full loop: react() -> callback payload -> vault sweep -----------

    function testFullLoopEndToEnd() public {
        vm.prank(owner);
        rsc.setSavingsPct(alice, 10);
        vm.prank(owner);
        rsc.setVault(address(vault));

        // 1. A Transfer of 1000 SAVE to Alice arrives at the RSC.
        _reactAsSystem(_transferLog(bob, alice, 1000 ether));

        // 2. The RSC requested a callback with the right payload.
        MockSystem sys = MockSystem(payable(SYSTEM_ADDR));
        assertEq(sys.callbackCount(), 1);
        (, address recipient, , bytes memory payload) = sys.lastCallback();
        assertEq(recipient, address(vault));

        // 3. The callback proxy delivers it: it overwrites the first arg
        //    with the RSC address, then the vault pulls 100 SAVE from Alice.
        (address placeholder, address user, uint256 amount) = abi.decode(
            _stripSelector(payload),
            (address, address, uint256)
        );
        assertEq(placeholder, address(0)); // placeholder the proxy replaces
        assertEq(user, alice);
        assertEq(amount, 100 ether);

        vm.prank(address(mockProxy));
        vault.sweep(address(rsc), user, amount);
        assertEq(vault.saved(alice), 100 ether);
    }

    function _stripSelector(bytes memory payload) internal pure returns (bytes memory) {
        require(payload.length >= 4, "short payload");
        bytes memory args = new bytes(payload.length - 4);
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = payload[i + 4];
        }
        return args;
    }

    // -- token ------------------------------------------------------------

    function testFaucetMints10000() public {
        vm.prank(bob);
        token.faucet();
        assertEq(token.balanceOf(bob), 10_000 ether);
    }

    function testOnlyOwnerCanMint() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1 ether);

        vm.prank(owner);
        token.mint(alice, 1 ether);
    }
}
