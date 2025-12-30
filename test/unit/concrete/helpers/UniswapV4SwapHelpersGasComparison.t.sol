// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../../../mocks/MockERC20.sol";
import "./UniswapV4SwapHelpersComparison.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { IPermit2 } from "@uniswap/permit2/src/interfaces/IPermit2.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { IUniversalRouter } from "@uniswap/universal-router/contracts/interfaces/IUniversalRouter.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

contract MockUniversalRouter is IUniversalRouter {
    function execute(bytes calldata, bytes[] calldata, uint256) external payable { }
    function executeSigned(
        bytes calldata,
        bytes[] calldata,
        bytes32,
        bytes32,
        bool,
        bytes32,
        bytes calldata,
        uint256
    )
        external
        payable { }

    function signedRouteContext() external pure returns (address, bytes32, bytes32) {
        return (address(0), bytes32(0), bytes32(0));
    }
}

contract MockPermit2 is IPermit2 {
    function approve(address, address, uint160, uint48) external pure { }
    function permit(address, IAllowanceTransfer.PermitSingle memory, bytes calldata) external pure { }
    function permit(address, IAllowanceTransfer.PermitBatch memory, bytes calldata) external pure { }
    function transferFrom(address, address, uint160, address) external pure { }
    function transferFrom(IAllowanceTransfer.AllowanceTransferDetails[] calldata) external pure { }
    function lockdown(IAllowanceTransfer.TokenSpenderPair[] calldata) external pure { }
    function invalidateNonces(address, address, uint48) external pure { }

    function allowance(address, address, address) external pure returns (uint160, uint48, uint48) {
        return (0, 0, 0);
    }
    function permitTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory,
        ISignatureTransfer.SignatureTransferDetails calldata,
        address,
        bytes calldata
    )
        external
        pure { }
    function permitTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory,
        ISignatureTransfer.SignatureTransferDetails[] calldata,
        address,
        bytes calldata
    )
        external
        pure { }
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitTransferFrom memory,
        ISignatureTransfer.SignatureTransferDetails calldata,
        address,
        bytes32,
        string calldata,
        bytes calldata
    )
        external
        pure { }
    function permitWitnessTransferFrom(
        ISignatureTransfer.PermitBatchTransferFrom memory,
        ISignatureTransfer.SignatureTransferDetails[] calldata,
        address,
        bytes32,
        string calldata,
        bytes calldata
    )
        external
        pure { }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return bytes32(0);
    }

    function nonceBitmap(address, uint256) external pure returns (uint256) {
        return 0;
    }
    function invalidateUnorderedNonces(uint256, uint256) external pure { }
}

contract UniswapV4SwapHelpersGasComparisonTest is Test {
    UniswapV4SwapHelpersOriginal public originalContract;
    UniswapV4SwapHelpersRefactored public refactoredContract;
    MockUniversalRouter public mockRouter;
    MockPermit2 public mockPermit2;
    MockERC20 public token0;
    MockERC20 public token1;

    address public constant RECEIVER = address(0x1234);
    uint256 public constant AMOUNT_IN = 1000 * 10 ** 18;
    uint256 public constant MIN_AMOUNT_OUT = 950 * 10 ** 18;
    uint256 public constant DEADLINE = type(uint256).max;

    function setUp() public {
        mockRouter = new MockUniversalRouter();
        mockPermit2 = new MockPermit2();

        originalContract =
            new UniswapV4SwapHelpersOriginal(IUniversalRouter(address(mockRouter)), IPermit2(address(mockPermit2)));
        refactoredContract =
            new UniswapV4SwapHelpersRefactored(IUniversalRouter(address(mockRouter)), IPermit2(address(mockPermit2)));

        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");

        // Mint tokens to this contract for testing
        token0.mint(address(this), AMOUNT_IN * 10);
        token1.mint(address(this), AMOUNT_IN * 10);
    }

    function getPoolKey(address currency0, address currency1) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function testGasComparison_ERC20ToERC20_zeroForOne() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1));
        address receiver1 = address(0x1111);
        address receiver2 = address(0x2222);

        // Test ORIGINAL version
        token0.approve(address(originalContract), AMOUNT_IN);
        token1.mint(address(originalContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeOriginal = gasleft();
        originalContract.swapExactInSingle(poolKey, true, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver1, "");
        uint256 gasUsedOriginal = gasBeforeOriginal - gasleft();

        // Test REFACTORED version
        token0.approve(address(refactoredContract), AMOUNT_IN);
        token1.mint(address(refactoredContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeRefactored = gasleft();
        refactoredContract.swapExactInSingle(poolKey, true, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver2, "");
        uint256 gasUsedRefactored = gasBeforeRefactored - gasleft();

        // Log comparison
        console.log("=== Gas Comparison: ERC20->ERC20 (zeroForOne) ===");
        console.log("Original (BEFORE refactor):", gasUsedOriginal);
        console.log("Refactored (AFTER refactor):", gasUsedRefactored);
        console.log("Gas saved:", gasUsedOriginal - gasUsedRefactored);
        console.log("Gas saved (%):", ((gasUsedOriginal - gasUsedRefactored) * 100) / gasUsedOriginal);

        assertEq(token1.balanceOf(receiver1), MIN_AMOUNT_OUT);
        assertEq(token1.balanceOf(receiver2), MIN_AMOUNT_OUT);
        assertLt(gasUsedRefactored, gasUsedOriginal); // Refactored should use less gas
    }

    function testGasComparison_ERC20ToERC20_oneForZero() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1));
        address receiver1 = address(0x1111);
        address receiver2 = address(0x2222);

        // Test ORIGINAL version
        token1.approve(address(originalContract), AMOUNT_IN);
        token0.mint(address(originalContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeOriginal = gasleft();
        originalContract.swapExactInSingle(poolKey, false, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver1, "");
        uint256 gasUsedOriginal = gasBeforeOriginal - gasleft();

        // Test REFACTORED version
        token1.approve(address(refactoredContract), AMOUNT_IN);
        token0.mint(address(refactoredContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeRefactored = gasleft();
        refactoredContract.swapExactInSingle(poolKey, false, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver2, "");
        uint256 gasUsedRefactored = gasBeforeRefactored - gasleft();

        // Log comparison
        console.log("=== Gas Comparison: ERC20->ERC20 (oneForZero) ===");
        console.log("Original (BEFORE refactor):", gasUsedOriginal);
        console.log("Refactored (AFTER refactor):", gasUsedRefactored);
        console.log("Gas saved:", gasUsedOriginal - gasUsedRefactored);
        console.log("Gas saved (%):", ((gasUsedOriginal - gasUsedRefactored) * 100) / gasUsedOriginal);

        assertEq(token0.balanceOf(receiver1), MIN_AMOUNT_OUT);
        assertEq(token0.balanceOf(receiver2), MIN_AMOUNT_OUT);
        assertLt(gasUsedRefactored, gasUsedOriginal);
    }

    function testGasComparison_NativeToERC20() public {
        PoolKey memory poolKey = getPoolKey(address(0), address(token1));
        address receiver1 = address(0x1111);
        address receiver2 = address(0x2222);

        // Test ORIGINAL version
        token1.mint(address(originalContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeOriginal = gasleft();
        originalContract.swapExactInSingle{ value: AMOUNT_IN }(
            poolKey, true, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver1, ""
        );
        uint256 gasUsedOriginal = gasBeforeOriginal - gasleft();

        // Test REFACTORED version
        token1.mint(address(refactoredContract), MIN_AMOUNT_OUT);

        uint256 gasBeforeRefactored = gasleft();
        refactoredContract.swapExactInSingle{ value: AMOUNT_IN }(
            poolKey, true, AMOUNT_IN, MIN_AMOUNT_OUT, DEADLINE, receiver2, ""
        );
        uint256 gasUsedRefactored = gasBeforeRefactored - gasleft();

        // Log comparison
        console.log("=== Gas Comparison: Native->ERC20 ===");
        console.log("Original (BEFORE refactor):", gasUsedOriginal);
        console.log("Refactored (AFTER refactor):", gasUsedRefactored);
        console.log("Gas saved:", gasUsedOriginal - gasUsedRefactored);
        console.log("Gas saved (%):", ((gasUsedOriginal - gasUsedRefactored) * 100) / gasUsedOriginal);

        assertEq(token1.balanceOf(receiver1), MIN_AMOUNT_OUT);
        assertEq(token1.balanceOf(receiver2), MIN_AMOUNT_OUT);
        assertLt(gasUsedRefactored, gasUsedOriginal);
    }

    function testGasComparison_DifferentAmounts() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1));

        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 1000 * 10 ** 18;
        amounts[2] = 10_000 * 10 ** 18;

        // Mint enough tokens upfront
        uint256 maxAmount = amounts[amounts.length - 1];
        token0.mint(address(this), maxAmount * 4);

        console.log("=== Gas Comparison: Different Amounts ===");

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amountIn = amounts[i];
            uint256 minAmountOut = amountIn * 95 / 100;
            address receiver1 = address(uint160(0x1111 + i));
            address receiver2 = address(uint160(0x2222 + i));

            // Test ORIGINAL
            token0.approve(address(originalContract), amountIn);
            token1.mint(address(originalContract), minAmountOut);

            uint256 gasBeforeOriginal = gasleft();
            originalContract.swapExactInSingle(poolKey, true, amountIn, minAmountOut, DEADLINE, receiver1, "");
            uint256 gasUsedOriginal = gasBeforeOriginal - gasleft();

            // Test REFACTORED
            token0.approve(address(refactoredContract), amountIn);
            token1.mint(address(refactoredContract), minAmountOut);

            uint256 gasBeforeRefactored = gasleft();
            refactoredContract.swapExactInSingle(poolKey, true, amountIn, minAmountOut, DEADLINE, receiver2, "");
            uint256 gasUsedRefactored = gasBeforeRefactored - gasleft();

            console.log("");
            console.log("Amount:", amountIn);
            console.log("  Original:", gasUsedOriginal);
            console.log("  Refactored:", gasUsedRefactored);
            console.log("  Gas saved:", gasUsedOriginal - gasUsedRefactored);
            console.log("  Gas saved (%):", ((gasUsedOriginal - gasUsedRefactored) * 100) / gasUsedOriginal);
        }
    }

    function testGasComparison_DeploymentCost() public {
        console.log("=== Deployment Cost Comparison ===");

        // Measure ORIGINAL contract deployment
        uint256 gasBeforeOriginal = gasleft();
        UniswapV4SwapHelpersOriginal original =
            new UniswapV4SwapHelpersOriginal(IUniversalRouter(address(mockRouter)), IPermit2(address(mockPermit2)));
        uint256 gasUsedOriginal = gasBeforeOriginal - gasleft();

        // Measure REFACTORED contract deployment
        uint256 gasBeforeRefactored = gasleft();
        UniswapV4SwapHelpersRefactored refactored =
            new UniswapV4SwapHelpersRefactored(IUniversalRouter(address(mockRouter)), IPermit2(address(mockPermit2)));
        uint256 gasUsedRefactored = gasBeforeRefactored - gasleft();

        // Log comparison
        console.log("Original (BEFORE refactor) deployment cost:", gasUsedOriginal);
        console.log("Refactored (AFTER refactor) deployment cost:", gasUsedRefactored);
        console.log(
            "Deployment cost difference:",
            gasUsedRefactored > gasUsedOriginal
                ? gasUsedRefactored - gasUsedOriginal
                : gasUsedOriginal - gasUsedRefactored
        );
        if (gasUsedRefactored < gasUsedOriginal) {
            console.log("Deployment cost saved:", gasUsedOriginal - gasUsedRefactored);
            console.log("Deployment cost saved (%):", ((gasUsedOriginal - gasUsedRefactored) * 100) / gasUsedOriginal);
        } else {
            console.log("Deployment cost increased:", gasUsedRefactored - gasUsedOriginal);
            console.log(
                "Deployment cost increased (%):", ((gasUsedRefactored - gasUsedOriginal) * 100) / gasUsedOriginal
            );
        }

        // Ensure contracts are deployed (use them to avoid optimization)
        assertEq(address(original.UNIVERSAL_ROUTER()), address(mockRouter));
        assertEq(address(refactored.UNIVERSAL_ROUTER()), address(mockRouter));
    }

    receive() external payable { }
}
