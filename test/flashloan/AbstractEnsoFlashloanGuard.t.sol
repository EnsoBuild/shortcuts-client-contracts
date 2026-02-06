// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std-1.9.7/Test.sol";

import "../../src/flashloan/AbstractEnsoFlashloan.sol";
import "../../src/interfaces/IEnsoFlashloan.sol";
import "../mocks/MockERC20.sol";

interface IMorphoFlashloanCallbackReceiver {
    function onMorphoFlashLoan(uint256 amount, bytes calldata data) external;
}

interface IAaveFlashloanCallbackReceiverLike {
    function executeOperation(
        address token,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata data
    )
        external
        returns (bool);
}

contract MockMorphoForGuard is IMorpho {
    bool public triggerAaveCallback;
    bool public skipPrimaryCallback;

    function configureCallbackBehavior(bool triggerAaveCallback_, bool skipPrimaryCallback_) external {
        triggerAaveCallback = triggerAaveCallback_;
        skipPrimaryCallback = skipPrimaryCallback_;
    }

    function flashLoan(address token, uint256 assets, bytes calldata data) external {
        if (triggerAaveCallback) {
            IAaveFlashloanCallbackReceiverLike(msg.sender).executeOperation(token, assets, 0, address(this), "");
        }
        if (!skipPrimaryCallback) {
            IMorphoFlashloanCallbackReceiver(msg.sender).onMorphoFlashLoan(assets, data);
        }
    }
}

contract FlashloanGuardHarness is AbstractEnsoFlashloan {
    bool public triggerNestedFlashloan;
    bytes public nestedProtocolData;

    constructor(
        address[] memory lenders,
        LenderProtocol[] memory protocols,
        address owner_
    )
        AbstractEnsoFlashloan(lenders, protocols, owner_)
    { }

    function setNestedConfig(bytes calldata nestedProtocolData_, bool triggerNestedFlashloan_) external {
        nestedProtocolData = nestedProtocolData_;
        triggerNestedFlashloan = triggerNestedFlashloan_;
    }

    function executeShortcut(
        address,
        bytes32,
        bytes32,
        bytes32[] memory,
        bytes[] memory,
        address,
        uint256
    )
        internal
        override
        returns (uint256 balanceBefore)
    {
        if (triggerNestedFlashloan) {
            this.executeFlashloan(
                LenderProtocol.Morpho, nestedProtocolData, bytes32(0), bytes32(0), new bytes32[](0), new bytes[](0)
            );
        }
        balanceBefore = 0;
    }

    function executeShortcutMulti(
        address,
        bytes32,
        bytes32,
        bytes32[] memory,
        bytes[] memory,
        address[] memory tokens,
        uint256[] memory
    )
        internal
        override
        returns (uint256[] memory balancesBefore)
    {
        balancesBefore = new uint256[](tokens.length);
    }
}

contract AbstractEnsoFlashloanGuardTest is Test {
    FlashloanGuardHarness public adapter;
    MockMorphoForGuard public morphoPrimary;
    MockERC20 public token;

    function setUp() public {
        morphoPrimary = new MockMorphoForGuard();
        token = new MockERC20("Mock Token", "MOCK");

        address[] memory lenders = new address[](1);
        LenderProtocol[] memory protocols = new LenderProtocol[](1);
        lenders[0] = address(morphoPrimary);
        protocols[0] = LenderProtocol.Morpho;

        adapter = new FlashloanGuardHarness(lenders, protocols, address(this));
    }

    function testNestedExecuteFlashloanRevertsWithFlashloanInProgress() external {
        bytes memory protocolData = abi.encode(IMorpho(address(morphoPrimary)), address(token), 1 ether);
        adapter.setNestedConfig(protocolData, true);

        vm.expectRevert(AbstractEnsoFlashloan.FlashloanInProgress.selector);
        adapter.executeFlashloan(
            LenderProtocol.Morpho, protocolData, bytes32(0), bytes32(0), new bytes32[](0), new bytes[](0)
        );
    }

    function testProtocolMismatchCallbackRevertsWithNotAuthorized() external {
        bytes memory protocolData = abi.encode(IMorpho(address(morphoPrimary)), address(token), 1 ether);

        morphoPrimary.configureCallbackBehavior(true, true);

        vm.expectRevert(AbstractEnsoFlashloan.NotAuthorized.selector);
        adapter.executeFlashloan(
            LenderProtocol.Morpho, protocolData, bytes32(0), bytes32(0), new bytes32[](0), new bytes[](0)
        );
    }
}
