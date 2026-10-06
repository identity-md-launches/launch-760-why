// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Why} from "../src/Why.sol";

/// @dev Complements the existing deployment tests with repeated calls and failure recovery.
/// forge-config: default.fuzz.runs = 1000
contract WhyAllowanceTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);
    address internal constant OTHER_SPENDER = address(0xBAD);

    Why internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        token = new Why();
    }

    function test_OneWeiApprovalCannotBeSpentTwice() public {
        assertTrue(token.approve(SPENDER, 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteApprovalIsConsumedUnlikeInfiniteApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max - 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max - 2);

        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 1));
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_MaximumTransferFromRevertsDespiteInfiniteApproval() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transferFrom(address(this), ALICE, type(uint256).max);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_FullSupplyDelegatedTransferThenEmptyOwnerCannotSpendAgain() public {
        assertTrue(token.approve(SPENDER, SUPPLY + 1));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, SUPPLY));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
        assertEq(token.allowance(address(this), SPENDER), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferStillRequiresSufficientBalance() public {
        assertTrue(token.transfer(ALICE, 1));
        vm.prank(ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1, 2));
        token.transfer(ALICE, 2);
        assertEq(token.balanceOf(ALICE), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_RevokingInfiniteApprovalBlocksTheNextSpendAndCanBeReapproved() public {
        assertTrue(token.transfer(ALICE, 3));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 1));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 0));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(ALICE, BOB, 1);
        assertEq(token.balanceOf(ALICE), 2);
        assertEq(token.balanceOf(BOB), 1);
        assertEq(token.allowance(ALICE, SPENDER), 0);

        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 2));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 2));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 3);
        assertEq(token.allowance(ALICE, SPENDER), 0);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesExistingApproval() public {
        assertTrue(token.approve(SPENDER, 7));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 0);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 0));
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ZeroDelegatedTransferToZeroStillReverts() public {
        assertTrue(token.approve(SPENDER, 7));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 0);
        assertEq(token.allowance(address(this), SPENDER), 7);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DelegatedSelfTransferConsumesPermissionWithoutCreatingValue(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY);
        assertTrue(token.transfer(ALICE, amount));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.allowance(ALICE, SPENDER), 0);

        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(ALICE, ALICE, 1);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_BalanceFailurePreservesApprovalForRetry(uint256 balance, uint256 amount, uint256 approval)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        approval = bound(approval, amount, type(uint256).max);
        assertTrue(token.transfer(ALICE, balance));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, balance, amount));
        token.transferFrom(ALICE, BOB, amount);
        assertEq(token.allowance(ALICE, SPENDER), approval);
        assertEq(token.balanceOf(ALICE), balance);
        assertEq(token.balanceOf(BOB), 0);

        // Funding the shortfall must make the same call succeed, without another approval.
        assertTrue(token.transfer(ALICE, amount - balance));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, amount));
        assertEq(token.allowance(ALICE, SPENDER), approval == type(uint256).max ? approval : approval - amount);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalIsSpecificToOwnerAndSpender(uint256 amount) public {
        amount = bound(amount, 1, SUPPLY / 2);
        assertTrue(token.transfer(ALICE, amount));
        assertTrue(token.transfer(BOB, amount));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, amount));

        vm.prank(OTHER_SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OTHER_SPENDER, 0, amount)
        );
        token.transferFrom(ALICE, OTHER_SPENDER, amount);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, amount));
        token.transferFrom(BOB, SPENDER, amount);
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.balanceOf(SPENDER), 0);
        assertEq(token.balanceOf(OTHER_SPENDER), 0);
        assertEq(token.allowance(ALICE, SPENDER), amount);
        assertEq(token.allowance(ALICE, OTHER_SPENDER), 0);
        assertEq(token.allowance(BOB, SPENDER), 0);

        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, SPENDER, amount));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(SPENDER), amount);
        assertEq(token.balanceOf(BOB), amount);
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferRoundTripRestoresBalancesAndLeavesApprovalUntouched(uint256 amount, uint256 approval)
        public
    {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.approve(SPENDER, approval));
        assertTrue(token.transfer(ALICE, amount));
        assertEq(token.balanceOf(ALICE), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        vm.prank(ALICE);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), approval);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
