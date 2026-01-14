// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Test } from "forge-std-1.9.7/Test.sol"; // THIS

import "../src/delegate/DelegateEnsoShortcuts.sol";
import "../src/flashloan/AbstractEnsoFlashloan.sol";
import "../src/flashloan/EnsoSafeFlashloanAdapter.sol";
import "../src/interfaces/IEnsoFlashloan.sol";

import "./utils/WeirollPlanner.sol";

import { SafeInstance, SafeTestLib, SafeTestTools } from "safe-tools/SafeTestTools.sol";

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface IERC20Minimal {
    function transfer(address to, uint256 value) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

contract EnsoSafeFlashloanAdapterTest is Test, SafeTestTools {
    using SafeTestLib for SafeInstance;

    EnsoSafeFlashloanAdapter public adapter;
    DelegateEnsoShortcuts public shortcuts;
    SafeInstance public safeInstance;

    address user_bob = makeAddr("bob");
    address receiver = makeAddr("receiver");

    // Mainnet addresses
    address morpho = address(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address aaveV3Pool = address(0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2);
    address balancerV3Vault = address(0xbA1333333333a1BA1108E8412f11850A5C319bA9);
    address dolomiteMargin = address(0x003Ca23Fd5F0ca87D01F6eC6CD14A8AE60c2b97D);
    address uniswapV3Factory = address(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    address weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address usdc = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);

    string _rpcURL = vm.envString("ETHEREUM_RPC_URL");
    uint256 _ethereumFork;

    function setUp() public {
        _ethereumFork = vm.createFork(_rpcURL);
        vm.selectFork(_ethereumFork);

        // Initialize safe tools (deploys singleton, proxy factory, handler)
        _initializeSafeTools();

        // Deploy shortcuts executor for delegatecall
        shortcuts = new DelegateEnsoShortcuts();

        // Deploy adapter with trusted lenders
        address[] memory lenders = new address[](5);
        LenderProtocol[] memory protocols = new LenderProtocol[](5);

        lenders[0] = morpho;
        protocols[0] = LenderProtocol.Morpho;

        lenders[1] = aaveV3Pool;
        protocols[1] = LenderProtocol.AaveV3;

        lenders[2] = balancerV3Vault;
        protocols[2] = LenderProtocol.BalancerV3;

        lenders[3] = dolomiteMargin;
        protocols[3] = LenderProtocol.Dolomite;

        lenders[4] = uniswapV3Factory;
        protocols[4] = LenderProtocol.UniswapV3;

        adapter = new EnsoSafeFlashloanAdapter(lenders, protocols, address(shortcuts), address(this));

        // Setup Safe wallet with single owner (user_bob)
        uint256[] memory ownerPKs = new uint256[](1);
        ownerPKs[0] = uint256(keccak256("bob"));
        safeInstance = _setupSafe(ownerPKs, 1, 0);

        // Enable the adapter as a module on the Safe
        safeInstance.enableModule(address(adapter));
    }

    // Morpho test:
    // - flashloan asset: WETH
    // - WETH.withdraw -> WETH.deposit -> transfer back to adapter
    function testMorphoFlashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        // Build weiroll commands:
        // 1. Unwrap WETH to ETH
        // 2. Wrap ETH back to WETH
        // 3. Transfer WETH back to adapter for repayment
        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](2);

        // Command 0: WETH.withdraw(amount) - unwrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // input from state[0]
            0xff, // no output
            address(token)
        );

        // Command 1: WETH.deposit{value: amount}() - wrap
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // value from state[0]
            0xff, // no output
            address(token)
        );

        // Command 2: WETH.transfer(adapter, amount) - send back for repayment
        commands[2] = WeirollPlanner.buildCommand(
            token.transfer.selector,
            0x01, // call
            0x0100ffffffff, // inputs from state[1], state[0]
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(adapter));

        bytes memory morphoData = abi.encode(morpho, token, amount);

        // Safe must be the msg.sender when calling executeFlashloan
        // Execute via Safe transaction
        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.Morpho,
            morphoData,
            bytes32(0), // accountId
            bytes32(0), // requestId
            commands,
            state
        );

        safeInstance.execTransaction(address(adapter), 0, callData);
    }

    // Aave V3 test:
    // - flashloan asset: WETH
    // - WETH.withdraw -> WETH.deposit -> transfer back to adapter (amount + premium)
    function testAaveV3Flashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        // Calculate Aave premium
        uint256 BPS = 10_000;
        uint256 totalFee = IAaveV3Pool(aaveV3Pool).FLASHLOAN_PREMIUM_TOTAL();
        uint256 premium = (amount * totalFee) / BPS;
        uint256 repayAmount = amount + premium;

        // Fund the Safe with premium amount
        vm.deal(address(this), premium);
        token.deposit{ value: premium }();
        token.transfer(address(safeInstance.safe), premium);

        // Build weiroll commands:
        // 1. Unwrap flashloaned WETH to ETH
        // 2. Wrap ETH back to WETH
        // 3. Transfer WETH back to adapter for repayment (amount + premium)
        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        // Command 0: WETH.withdraw(amount) - unwrap only flashloaned amount
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // input from state[0]
            0xff, // no output
            address(token)
        );

        // Command 1: WETH.deposit{value: amount}() - wrap
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // value from state[0]
            0xff, // no output
            address(token)
        );

        // Command 2: WETH.transfer(adapter, repayAmount) - send back for repayment
        commands[2] = WeirollPlanner.buildCommand(
            token.transfer.selector,
            0x01, // call
            0x0102ffffffff, // inputs from state[1], state[2]
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(adapter));
        state[2] = abi.encode(repayAmount);

        bytes memory aaveData = abi.encode(aaveV3Pool, token, amount);

        // Execute via Safe transaction
        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.AaveV3,
            aaveData,
            bytes32(0), // accountId
            bytes32(0), // requestId
            commands,
            state
        );

        safeInstance.execTransaction(address(adapter), 0, callData);
    }

    // BalancerV3 test:
    // - flashloan asset: WETH
    // - WETH.withdraw -> WETH.deposit -> transfer back to adapter
    function testBalancerV3Flashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        // Build weiroll commands:
        // 1. Unwrap WETH to ETH
        // 2. Wrap ETH back to WETH
        // 3. Transfer WETH back to adapter for repayment
        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](2);

        // Command 0: WETH.withdraw(amount) - unwrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // input from state[0]
            0xff, // no output
            address(token)
        );

        // Command 1: WETH.deposit{value: amount}() - wrap
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // value from state[0]
            0xff, // no output
            address(token)
        );

        // Command 2: WETH.transfer(adapter, amount) - send back for repayment
        commands[2] = WeirollPlanner.buildCommand(
            token.transfer.selector,
            0x01, // call
            0x0100ffffffff, // inputs from state[1], state[0]
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(adapter));

        address[] memory tokens = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        tokens[0] = address(token);
        amounts[0] = amount;

        bytes memory balancerData = abi.encode(balancerV3Vault, tokens, amounts);

        // Execute via Safe transaction
        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.BalancerV3,
            balancerData,
            bytes32(0), // accountId
            bytes32(0), // requestId
            commands,
            state
        );

        safeInstance.execTransaction(address(adapter), 0, callData);
    }

    // Dolomite test:
    // - flashloan asset: WETH
    // - WETH.withdraw -> WETH.deposit -> transfer back to adapter
    // - No fees for Dolomite flashloans
    function testDolomiteFlashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        // Build weiroll commands:
        // 1. Unwrap WETH to ETH
        // 2. Wrap ETH back to WETH
        // 3. Transfer WETH back to adapter for repayment
        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](2);

        // Command 0: WETH.withdraw(amount) - unwrap
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // input from state[0]
            0xff, // no output
            address(token)
        );

        // Command 1: WETH.deposit{value: amount}() - wrap
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // value from state[0]
            0xff, // no output
            address(token)
        );

        // Command 2: WETH.transfer(adapter, amount) - send back for repayment
        commands[2] = WeirollPlanner.buildCommand(
            token.transfer.selector,
            0x01, // call
            0x0100ffffffff, // inputs from state[1], state[0]
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(adapter));

        bytes memory dolomiteData = abi.encode(dolomiteMargin, token, amount);

        // Execute via Safe transaction
        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.Dolomite,
            dolomiteData,
            bytes32(0), // accountId
            bytes32(0), // requestId
            commands,
            state
        );

        safeInstance.execTransaction(address(adapter), 0, callData);
    }

    // UniswapV3 test:
    // - flashloan from WETH/USDC 0.05% pool
    // - borrow only WETH (amount1 = 0)
    // - WETH.withdraw -> WETH.deposit -> transfer back to adapter (amount + fee)
    function testUniswapV3Flashloan() public {
        vm.selectFork(_ethereumFork);

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        // Get the WETH/USDC 0.05% pool
        address pool = IUniswapV3Factory(uniswapV3Factory).getPool(weth, usdc, 500);
        require(pool != address(0), "Pool not found");

        // Calculate fee: 0.05% = 500/1e6 = 0.0005
        uint256 fee = (amount * 500) / 1e6;
        if (fee == 0) fee = 1; // minimum 1 wei
        uint256 repayAmount = amount + fee;

        // Fund the Safe with fee amount
        vm.deal(address(this), fee);
        token.deposit{ value: fee }();
        token.transfer(address(safeInstance.safe), fee);

        // Build weiroll commands:
        // 1. Unwrap WETH to ETH
        // 2. Wrap ETH back to WETH
        // 3. Transfer WETH back to adapter for repayment (amount + fee)
        bytes32[] memory commands = new bytes32[](3);
        bytes[] memory state = new bytes[](3);

        // Command 0: WETH.withdraw(amount) - unwrap only flashloaned amount
        commands[0] = WeirollPlanner.buildCommand(
            token.withdraw.selector,
            0x01, // call
            0x00ffffffffff, // input from state[0]
            0xff, // no output
            address(token)
        );

        // Command 1: WETH.deposit{value: amount}() - wrap
        commands[1] = WeirollPlanner.buildCommand(
            token.deposit.selector,
            0x03, // call with value
            0x00ffffffffff, // value from state[0]
            0xff, // no output
            address(token)
        );

        // Command 2: WETH.transfer(adapter, repayAmount) - send back for repayment
        commands[2] = WeirollPlanner.buildCommand(
            token.transfer.selector,
            0x01, // call
            0x0102ffffffff, // inputs from state[1], state[2]
            0xff, // no output
            address(token)
        );

        state[0] = abi.encode(amount);
        state[1] = abi.encode(address(adapter));
        state[2] = abi.encode(repayAmount);

        // UniswapV3 data: pool address, token0, token1, amount0, amount1
        // Note: In WETH/USDC pool, USDC (lower address) is token0, WETH is token1
        // We're borrowing WETH so amount0=0, amount1=amount
        (address token0, address token1) = usdc < weth ? (usdc, weth) : (weth, usdc);
        (uint256 amount0, uint256 amount1) = usdc < weth ? (uint256(0), amount) : (amount, uint256(0));
        bytes memory uniswapData = abi.encode(pool, token0, token1, amount0, amount1);

        // Execute via Safe transaction
        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.UniswapV3,
            uniswapData,
            bytes32(0), // accountId
            bytes32(0), // requestId
            commands,
            state
        );

        safeInstance.execTransaction(address(adapter), 0, callData);
    }

    // Test that unauthorized lender cannot call callbacks
    function testUnauthorizedLenderReverts() public {
        vm.selectFork(_ethereumFork);

        address unauthorizedLender = makeAddr("unauthorized");

        vm.prank(unauthorizedLender);
        vm.expectRevert(AbstractEnsoFlashloan.UnknownLender.selector);
        adapter.onMorphoFlashLoan(1 ether, "");
    }

    // Test that non-module cannot trigger shortcut execution
    function testNonModuleCannotExecute() public {
        vm.selectFork(_ethereumFork);

        // Disable the adapter module
        safeInstance.disableModule(address(adapter));

        IWETH token = IWETH(weth);
        uint256 amount = 1 ether;

        bytes32[] memory commands = new bytes32[](0);
        bytes[] memory state = new bytes[](0);

        bytes memory morphoData = abi.encode(morpho, token, amount);

        bytes memory callData = abi.encodeWithSelector(
            adapter.executeFlashloan.selector,
            LenderProtocol.Morpho,
            morphoData,
            bytes32(0),
            bytes32(0),
            commands,
            state
        );

        // This should fail because adapter is no longer a module
        vm.expectRevert();
        safeInstance.execTransaction(address(adapter), 0, callData);
    }
}
