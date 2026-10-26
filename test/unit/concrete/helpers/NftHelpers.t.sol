// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { NftHelpers } from "../../../../src/helpers/NftHelpers.sol";
import { MockERC721 } from "../../../mocks/MockERC721.sol";
import { Test } from "forge-std/Test.sol";
import { IERC721Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import { IERC721 } from "openzeppelin-contracts/token/ERC721/IERC721.sol";

contract NftHelpersTest is Test {
    NftHelpers internal helpers;
    MockERC721 internal nft;

    address internal constant OWNER = address(0xA11CE);
    address internal constant OTHER = address(0xB0B);
    uint256 internal constant TOKEN_ID = 42;

    function setUp() public {
        helpers = new NftHelpers();
        nft = new MockERC721("Position", "POS");
        nft.mint(OWNER, TOKEN_ID);
    }

    function test_checkOwner_passesForOwner() public view {
        helpers.checkOwner(IERC721(address(nft)), TOKEN_ID, OWNER);
    }

    function test_checkOwner_revertsForOtherAccount() public {
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.OwnerMismatch.selector, address(nft), TOKEN_ID, OTHER, OWNER));
        helpers.checkOwner(IERC721(address(nft)), TOKEN_ID, OTHER);
    }

    function test_checkOwner_revertsAfterTransfer() public {
        vm.prank(OWNER);
        nft.transferFrom(OWNER, OTHER, TOKEN_ID);

        vm.expectRevert(abi.encodeWithSelector(NftHelpers.OwnerMismatch.selector, address(nft), TOKEN_ID, OWNER, OTHER));
        helpers.checkOwner(IERC721(address(nft)), TOKEN_ID, OWNER);
    }

    function test_checkOwner_revertsForNonexistentToken() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, TOKEN_ID + 1));
        helpers.checkOwner(IERC721(address(nft)), TOKEN_ID + 1, OWNER);
    }

    function testFuzz_checkOwner_matchesOwnerOf(address expected) public {
        if (expected == OWNER) {
            helpers.checkOwner(IERC721(address(nft)), TOKEN_ID, expected);
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(NftHelpers.OwnerMismatch.selector, address(nft), TOKEN_ID, expected, OWNER)
            );
            helpers.checkOwner(IERC721(address(nft)), TOKEN_ID, expected);
        }
    }

    bytes32 internal constant KEY = keccak256("mint");

    // isolate = true: each top-level call here is its own transaction, so stash and load go through one executor call

    function test_stash_loadReturnsValueInSameTransaction() public {
        assertEq(new Executor(helpers).stashThenLoad(KEY, 861, KEY), 861);
    }

    function test_stash_zeroIsAValue() public {
        assertEq(new Executor(helpers).stashThenLoad(KEY, 0, KEY), 0);
    }

    function test_stash_refusesOverwrite() public {
        Executor executor = new Executor(helpers);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.AlreadyStashed.selector, address(executor), KEY));
        executor.stashTwiceThenLoad(KEY, 1, 2);
    }

    function test_stash_refusesOverwriteWithSameValue() public {
        Executor executor = new Executor(helpers);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.AlreadyStashed.selector, address(executor), KEY));
        executor.stashTwiceThenLoad(KEY, 861, 861);
    }

    // a re-entrant frame of the shared executor cannot replace what the callback stashed for its parent
    function test_stash_reentrantFrameCannotReplaceCallbackValue() public {
        Executor executor = new Executor(helpers);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.AlreadyStashed.selector, address(executor), KEY));
        executor.stashInCallbackThenOverwrite(KEY, 861, 1);
    }

    function test_stash_otherKeysStayWritable() public {
        assertEq(new Executor(helpers).stashTwoKeysThenLoad(KEY, 1, bytes32(0), 2), 3);
    }

    function test_stash_otherCallersUseTheirOwnSlots() public {
        Executor executor = new Executor(helpers);
        Executor other = new Executor(helpers);
        assertEq(executor.stashThenLetOtherStashAndLoad(other, KEY, 861, 1), 861);
    }

    function test_stash_laterTransactionStartsEmpty() public {
        Executor executor = new Executor(helpers);
        executor.stash(KEY, 1);
        assertEq(executor.stashThenLoad(KEY, 2, KEY), 2);
    }

    function test_load_revertsWhenNothingStashed() public {
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.NotStashed.selector, address(this), KEY));
        // forge-lint: disable-next-line(unused-return)
        helpers.load(KEY);
    }

    function test_load_keysAreIndependent() public {
        Executor executor = new Executor(helpers);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.NotStashed.selector, address(executor), bytes32(0)));
        // forge-lint: disable-next-line(unused-return)
        executor.stashThenLoad(KEY, 861, bytes32(0));
    }

    function test_load_revertsForOtherCaller() public {
        Executor executor = new Executor(helpers);
        Executor other = new Executor(helpers);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.NotStashed.selector, address(other), KEY));
        // forge-lint: disable-next-line(unused-return)
        executor.stashThenCallOther(other, KEY, 861);
    }

    function test_load_revertsInLaterTransaction() public {
        Executor executor = new Executor(helpers);
        executor.stash(KEY, 861);
        vm.expectRevert(abi.encodeWithSelector(NftHelpers.NotStashed.selector, address(executor), KEY));
        // forge-lint: disable-next-line(unused-return)
        executor.load(KEY);
    }

    // the flashloan callback is a nested frame of the same executor: it stashes, the outer frame loads
    function test_stash_nestedFrameHandsValueToParent() public {
        assertEq(new Executor(helpers).stashInCallbackThenLoad(KEY, 861), 861);
    }

    function testFuzz_stash_roundTrips(bytes32 key, uint256 value) public {
        assertEq(new Executor(helpers).stashThenLoad(key, value, key), value);
    }
}

contract Executor {
    NftHelpers internal immutable helpers;

    constructor(NftHelpers helpers_) {
        helpers = helpers_;
    }

    function stash(bytes32 key, uint256 value) external {
        helpers.stash(key, value);
    }

    function load(bytes32 key) external view returns (uint256) {
        return helpers.load(key);
    }

    function stashThenLoad(bytes32 key, uint256 value, bytes32 loadKey) external returns (uint256) {
        helpers.stash(key, value);
        return helpers.load(loadKey);
    }

    function stashTwiceThenLoad(bytes32 key, uint256 first, uint256 second) external returns (uint256) {
        helpers.stash(key, first);
        helpers.stash(key, second);
        return helpers.load(key);
    }

    function stashThenCallOther(Executor other, bytes32 key, uint256 value) external returns (uint256) {
        helpers.stash(key, value);
        return other.load(key);
    }

    function stashTwoKeysThenLoad(bytes32 a, uint256 first, bytes32 b, uint256 second) external returns (uint256) {
        helpers.stash(a, first);
        helpers.stash(b, second);
        return helpers.load(a) + helpers.load(b);
    }

    function stashThenLetOtherStashAndLoad(
        Executor other,
        bytes32 key,
        uint256 value,
        uint256 otherValue
    )
        external
        returns (uint256)
    {
        helpers.stash(key, value);
        other.stash(key, otherValue);
        return helpers.load(key);
    }

    function stashInCallbackThenOverwrite(bytes32 key, uint256 value, uint256 replacement) external {
        this.callback(key, value);
        helpers.stash(key, replacement);
    }

    function stashInCallbackThenLoad(bytes32 key, uint256 value) external returns (uint256) {
        this.callback(key, value);
        return helpers.load(key);
    }

    function callback(bytes32 key, uint256 value) external {
        helpers.stash(key, value);
    }
}
