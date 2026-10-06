// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Why} from "../src/Why.sol";

/// @dev Closed holder set with ghost balances and allowances. Rejected calls must not update the model.
contract WhyHandler is Test {
    Why public immutable token;
    address[4] public actors = [address(0xA11CE), address(0xB0B), address(0xCA11), address(0xD00D)];
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(Why token_) {
        token = token_;
        expectedBalance[actors[0]] = 1_000_000_000 ether;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 allowed = expectedAllowance[from][spender];
        uint256 available = expectedBalance[from];
        amount = bound(amount, 0, allowed < available ? allowed : available);
        vm.prank(spender);
        assertTrue(token.transferFrom(from, to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        if (allowed != type(uint256).max) {
            expectedAllowance[from][spender] -= amount;
        }
    }

    // Explicitly reach revocation, finite near-max, and infinite approval states during sequences.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint256 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256[4] memory amounts = [uint256(0), expectedBalance[owner], type(uint256).max - 1, type(uint256).max];
        _approve(owner, spender, amounts[mode % amounts.length]);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _expectRejected(
            from,
            abi.encodeCall(token.transfer, (to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectAllowanceOverspend(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 approval,
        uint256 amount
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        approval = bound(approval, 0, expectedBalance[from]);
        amount = bound(amount, approval + 1, type(uint256).max);
        _approve(from, spender, approval);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (from, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approval, amount)
        );
    }

    // Approval is sufficient, so this reaches the balance check after allowance spending.
    function rejectBalanceOverspend(
        uint256 fromSeed,
        uint256 toSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool infinite
    ) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 balance = expectedBalance[from];
        amount = bound(amount, balance + 1, type(uint256).max);
        _approve(from, spender, infinite ? type(uint256).max : amount);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (from, to, amount)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
        );
    }

    function rejectZeroReceiver(uint256 fromSeed, uint256 spenderSeed, uint256 amount, bool delegated) external {
        address from = actors[fromSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        bytes memory error = abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0));
        if (delegated) {
            _approve(from, spender, amount);
            _expectRejected(spender, abi.encodeCall(token.transferFrom, (from, address(0), amount)), error);
        } else {
            _expectRejected(from, abi.encodeCall(token.transfer, (address(0), amount)), error);
        }
    }

    function revokeAndAttemptSpend(uint256 fromSeed, uint256 toSeed, uint256 spenderSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(from, spender, 0);
        _expectRejected(
            spender,
            abi.encodeCall(token.transferFrom, (from, to, 1)),
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function _expectRejected(address caller, bytes memory data, bytes memory expectedError) internal {
        vm.prank(caller);
        (bool ok, bytes memory result) = address(token).call(data);
        assertFalse(ok, "invalid call succeeded");
        assertEq(result, expectedError, "unexpected rejection reason");
        // The invariant checks every actor and allowance against the unchanged ghost state.
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract WhyInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    Why internal token;
    WhyHandler internal handler;

    function setUp() public {
        token = new Why();
        handler = new WhyHandler(token);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = WhyHandler.transfer.selector;
        selectors[1] = WhyHandler.approve.selector;
        selectors[2] = WhyHandler.transferFrom.selector;
        selectors[3] = WhyHandler.approveBoundary.selector;
        selectors[4] = WhyHandler.rejectTransferAboveBalance.selector;
        selectors[5] = WhyHandler.rejectAllowanceOverspend.selector;
        selectors[6] = WhyHandler.rejectBalanceOverspend.selector;
        selectors[7] = WhyHandler.rejectZeroReceiver.selector;
        selectors[8] = WhyHandler.revokeAndAttemptSpend.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));
    }

    // Pin a useful sequence as well as fuzzing it, so every new action is exercised on every run.
    function test_HandlerRejectionsInterleavedWithSuccessfulSpending() public {
        handler.transfer(0, 1, 100);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.approve(1, 2, 50);
        handler.transferFrom(1, 3, 2, 20);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectTransferAboveBalance(1, 3, 81);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectAllowanceOverspend(1, 3, 2, 30, 31);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectBalanceOverspend(1, 3, 2, 81, false);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectBalanceOverspend(1, 3, 2, type(uint256).max, true);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectZeroReceiver(1, 2, 1, true);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.rejectZeroReceiver(1, 2, 0, false);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        for (uint256 mode; mode < 4; ++mode) {
            handler.approveBoundary(1, 2, mode);
            invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        }
        handler.revokeAndAttemptSpend(1, 3, 2);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        handler.approve(1, 2, 80);
        handler.transferFrom(1, 3, 2, 80);
        invariant_FixedSupplyBalancesAndAllowancesMatchModel();
        assertEq(token.balanceOf(handler.actors(1)), 0);
        assertEq(token.balanceOf(handler.actors(3)), 100);
    }

    function invariant_FixedSupplyBalancesAndAllowancesMatchModel() public view {
        assertEq(token.totalSupply(), SUPPLY);
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }
}
