// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Why} from "../src/Why.sol";
import {TokenFactory} from "./helpers/TokenFactory.sol";

contract WhyTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant SPENDER = address(0x5EED);

    Why internal token;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new Why();
    }

    function test_MetadataAndEntireInitialSupply() public view {
        assertEq(token.name(), "Why");
        assertEq(token.symbol(), "WHY");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.allowance(address(this), SPENDER), 0);
    }

    function test_ConstructorEmitsSingleMintEvent() public {
        vm.recordLogs();
        Why fresh = new Why();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].emitter, address(fresh));
        assertEq(logs[0].topics.length, 3);
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(logs[0].topics[1], bytes32(0));
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY);
    }

    function testFuzz_ConstructorMintsToImmediateDeployer(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        Why fresh = new Why();
        assertEq(fresh.totalSupply(), SUPPLY);
        assertEq(fresh.balanceOf(deployer), SUPPLY);
    }

    function test_Create2FactoryReceivesSupplyAndLaunchTransfersArriveWhole() public {
        TokenFactory factory = new TokenFactory();
        bytes32 salt = keccak256("WHY launch");
        address predicted = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(bytes1(0xff), address(factory), salt, keccak256(type(Why).creationCode)))
                )
            )
        );
        Why launched = factory.deploy(salt);
        assertEq(address(launched), predicted);
        assertEq(launched.balanceOf(address(factory)), SUPPLY);
        assertEq(launched.balanceOf(address(this)), 0);

        address distributor = address(0xD157);
        address poolManager = address(0x9001);
        uint256 swarm = SUPPLY / 10;
        // A representative transfer flow; pool pricing and swaps belong to the launch harness.
        uint256 pool = SUPPLY * 3 / 10;
        vm.startPrank(address(factory));
        assertTrue(launched.transfer(distributor, swarm));
        assertTrue(launched.transfer(poolManager, pool));
        assertTrue(launched.transfer(ALICE, SUPPLY - swarm - pool));
        vm.stopPrank();
        assertEq(launched.balanceOf(distributor), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.balanceOf(ALICE), SUPPLY - swarm - pool);
        assertEq(launched.balanceOf(address(factory)), 0);

        vm.prank(distributor);
        assertTrue(launched.transfer(BOB, swarm));
        assertEq(launched.balanceOf(BOB), swarm);
        assertEq(launched.balanceOf(distributor), 0);
        vm.prank(poolManager);
        assertTrue(launched.transfer(BOB, 1 ether));
        vm.prank(BOB);
        assertTrue(launched.transfer(poolManager, 1 ether));
        assertEq(launched.balanceOf(BOB), swarm);
        assertEq(launched.balanceOf(poolManager), pool);
        assertEq(launched.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndMovesExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 12 ether);
        assertTrue(token.transfer(ALICE, 12 ether));
        assertEq(token.balanceOf(ALICE), 12 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 12 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanBeTransferred() public {
        assertTrue(token.transfer(ALICE, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(ALICE), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(ALICE, BOB, 0);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferPreservesBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToZeroRevertsIncludingZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(ALICE, 0);
    }

    function testFuzz_TransferAboveBalanceRevertsWithoutChanges(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(ALICE, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ApproveEmitsEventAndCanReplaceAndRevoke() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), SPENDER, 10 ether);
        assertTrue(token.approve(SPENDER, 10 ether));
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertTrue(token.approve(SPENDER, 3 ether));
        assertEq(token.allowance(address(this), SPENDER), 3 ether);
        assertTrue(token.approve(SPENDER, 0));
        assertEq(token.allowance(address(this), SPENDER), 0);
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 0, 1));
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApprovalDoesNotRequireBalance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, type(uint256).max));
        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_ApproveFromZeroOwnerReverts() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(SPENDER, 1);
    }

    function test_TransferFromConsumesExactAllowanceAndEmitsTransfer() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), ALICE, 10 ether);
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10 ether));
        assertEq(token.balanceOf(address(this)), SUPPLY - 10 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromPreservesInfiniteAllowance() public {
        assertTrue(token.approve(SPENDER, type(uint256).max));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(address(this), ALICE, 10 ether));
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.allowance(address(this), SPENDER), type(uint256).max);
    }

    function test_UnapprovedTransferFromRevertsEvenForDeployer() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1 ether)
        );
        token.transferFrom(ALICE, BOB, 1 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromAboveAllowanceRevertsWithoutChanges() public {
        assertTrue(token.approve(SPENDER, 1 ether));
        vm.prank(SPENDER);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, SPENDER, 1 ether, 2 ether)
        );
        token.transferFrom(address(this), ALICE, 2 ether);
        assertEq(token.allowance(address(this), SPENDER), 1 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(ALICE), 0);
    }

    function test_TransferFromAboveBalanceRestoresAllowance() public {
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 0, 1 ether));
        token.transferFrom(ALICE, BOB, 1 ether);
        assertEq(token.allowance(ALICE, SPENDER), 10 ether);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_TransferFromToZeroRestoresAllowance() public {
        assertTrue(token.approve(SPENDER, 10 ether));
        vm.prank(SPENDER);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(address(this), address(0), 1 ether);
        assertEq(token.allowance(address(this), SPENDER), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromNeedsNoAllowance() public {
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, 0));
        assertEq(token.allowance(ALICE, SPENDER), 0);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testFuzz_TransferAndTransferFromConserveSupply(uint256 allocation, uint256 approval, uint256 spent)
        public
    {
        allocation = bound(allocation, 0, SUPPLY);
        approval = bound(approval, 0, allocation);
        spent = bound(spent, 0, approval);
        assertTrue(token.transfer(ALICE, allocation));
        vm.prank(ALICE);
        assertTrue(token.approve(SPENDER, approval));
        vm.prank(SPENDER);
        assertTrue(token.transferFrom(ALICE, BOB, spent));
        assertEq(token.balanceOf(ALICE), allocation - spent);
        assertEq(token.balanceOf(BOB), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - allocation);
        assertEq(token.allowance(ALICE, SPENDER), approval - spent);
        assertEq(token.balanceOf(address(this)) + token.balanceOf(ALICE) + token.balanceOf(BOB), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_NoMintBurnFreezeOrUpgradeEntryPoints() public {
        assertTrue(token.transfer(ALICE, 10 ether));
        bytes[24] memory calls = [
            abi.encodeWithSignature("mint(address,uint256)", BOB, 1 ether),
            abi.encodeWithSignature("mint(uint256)", 1 ether),
            abi.encodeWithSignature("mint()"),
            abi.encodeWithSignature("issue(uint256)", 1 ether),
            abi.encodeWithSignature("setMinter(address)", BOB),
            abi.encodeWithSignature("initialize(address)", BOB),
            abi.encodeWithSignature("setOwner(address)", BOB),
            abi.encodeWithSignature("transferOwnership(address)", BOB),
            abi.encodeWithSignature("upgradeTo(address)", BOB),
            abi.encodeWithSignature("upgradeToAndCall(address,bytes)", BOB, bytes("")),
            abi.encodeWithSignature("pause()"),
            abi.encodeWithSignature("unpause()"),
            abi.encodeWithSignature("blacklist(address)", ALICE),
            abi.encodeWithSignature("blocklist(address)", ALICE),
            abi.encodeWithSignature("freeze(address)", ALICE),
            abi.encodeWithSignature("freezeAccount(address)", ALICE),
            abi.encodeWithSignature("setBlacklist(address,bool)", ALICE, true),
            abi.encodeWithSignature("setBlocked(address,bool)", ALICE, true),
            abi.encodeWithSignature("lock(address)", ALICE),
            abi.encodeWithSignature("disableTransfers()"),
            abi.encodeWithSignature("setTransfersEnabled(bool)", false),
            abi.encodeWithSignature("burn(uint256)", 1 ether),
            abi.encodeWithSignature("burnFrom(address,uint256)", ALICE, 1 ether),
            abi.encodeWithSignature("seize(address)", ALICE)
        ];
        for (uint256 i; i < calls.length; ++i) {
            (bool ok,) = address(token).call(calls[i]);
            assertFalse(ok, "deployer reached a forbidden entry point");
            vm.prank(BOB);
            (ok,) = address(token).call(calls[i]);
            assertFalse(ok, "stranger reached a forbidden entry point");
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(ALICE), 10 ether);
        }
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 10 ether));
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 10 ether);
    }

    function test_RejectsNativeCurrency() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(token).call{value: 1 wei}("");
        assertFalse(ok);
        assertEq(address(token).balance, 0);
    }

    function test_RuntimeContainsNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
