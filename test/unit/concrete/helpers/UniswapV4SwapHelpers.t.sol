// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import { console } from "forge-std/console.sol";

import "../../../../src/helpers/UniswapV4SwapHelpers.sol";
import "../../../mocks/MockERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IAllowanceTransfer } from "@uniswap/permit2/src/interfaces/IAllowanceTransfer.sol";
import { ISignatureTransfer } from "@uniswap/permit2/src/interfaces/ISignatureTransfer.sol";
import { Commands } from "@uniswap/universal-router/contracts/libraries/Commands.sol";
import { IHooks } from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import { Currency } from "@uniswap/v4-core/src/types/Currency.sol";
import { PoolKey } from "@uniswap/v4-core/src/types/PoolKey.sol";

contract MockUniversalRouter is IUniversalRouter {
    // Mock router that does nothing - for gas profiling, we'll pre-seed output tokens
    function execute(bytes calldata, bytes[] calldata, uint256) external payable {
        // No-op: In a real scenario, this would execute the swap
        // For gas profiling, we pre-mint output tokens to simulate the swap result
    }

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
        payable {
        // No-op for testing
    }

    function signedRouteContext() external pure returns (address, bytes32, bytes32) {
        return (address(0), bytes32(0), bytes32(0));
    }
}

contract MockPermit2 is IPermit2 {
    // Minimal mock implementation for gas profiling - stub all interface methods with no-ops
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

contract UniswapV4SwapHelpersGasTest is Test {
    UniswapV4SwapHelpers public swapHelpers;
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
        swapHelpers = new UniswapV4SwapHelpers(IUniversalRouter(address(mockRouter)), IPermit2(address(mockPermit2)));

        token0 = new MockERC20("Token0", "TK0");
        token1 = new MockERC20("Token1", "TK1");

        // Mint tokens to this contract for testing
        token0.mint(address(this), AMOUNT_IN * 10);
        token1.mint(address(this), AMOUNT_IN * 10);
    }

    function getPoolKey(
        address currency0,
        address currency1,
        bool /* zeroForOne */
    )
        internal
        pure
        returns (PoolKey memory)
    {
        return PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
    }

    function testGasProfile_swapExactInSingle_ERC20ToERC20_zeroForOne() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1), true);

        token0.approve(address(swapHelpers), AMOUNT_IN);
        // Pre-mint output tokens to contract to simulate router swap result
        token1.mint(address(swapHelpers), MIN_AMOUNT_OUT);

        uint256 gasBefore = gasleft();
        swapHelpers.swapExactInSingle(
            poolKey,
            true, // zeroForOne
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            DEADLINE,
            RECEIVER,
            ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used (ERC20->ERC20, zeroForOne):", gasUsed);
        assertGt(gasUsed, 0);
        assertEq(token1.balanceOf(RECEIVER), MIN_AMOUNT_OUT);
    }

    function testGasProfile_swapExactInSingle_ERC20ToERC20_oneForZero() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1), false);

        token1.approve(address(swapHelpers), AMOUNT_IN);
        // Pre-mint output tokens to contract to simulate router swap result
        token0.mint(address(swapHelpers), MIN_AMOUNT_OUT);

        uint256 gasBefore = gasleft();
        swapHelpers.swapExactInSingle(
            poolKey,
            false, // oneForZero
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            DEADLINE,
            RECEIVER,
            ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used (ERC20->ERC20, oneForZero):", gasUsed);
        assertGt(gasUsed, 0);
        assertEq(token0.balanceOf(RECEIVER), MIN_AMOUNT_OUT);
    }

    function testGasProfile_swapExactInSingle_NativeToERC20() public {
        PoolKey memory poolKey = getPoolKey(address(0), address(token1), true);

        // Pre-mint output tokens to contract to simulate router swap result
        token1.mint(address(swapHelpers), MIN_AMOUNT_OUT);

        uint256 gasBefore = gasleft();
        swapHelpers.swapExactInSingle{ value: AMOUNT_IN }(
            poolKey,
            true, // zeroForOne
            AMOUNT_IN,
            MIN_AMOUNT_OUT,
            DEADLINE,
            RECEIVER,
            ""
        );
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used (Native->ERC20):", gasUsed);
        assertGt(gasUsed, 0);
        assertEq(token1.balanceOf(RECEIVER), MIN_AMOUNT_OUT);
    }

    // Note: ERC20->Native not tested as contract uses IERC20 for output which doesn't support native
    // Test with different amounts to profile gas scaling
    function testGasProfile_swapExactInSingle_DifferentAmounts() public {
        PoolKey memory poolKey = getPoolKey(address(token0), address(token1), true);

        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 500 * 10 ** 18;
        amounts[2] = 1000 * 10 ** 18;
        amounts[3] = 5000 * 10 ** 18;
        amounts[4] = 10_000 * 10 ** 18;

        // Mint enough tokens upfront for all test amounts
        uint256 maxAmount = amounts[amounts.length - 1];
        token0.mint(address(this), maxAmount * 2);
        token1.mint(address(swapHelpers), maxAmount * 2);

        for (uint256 i = 0; i < amounts.length; i++) {
            uint256 amountIn = amounts[i];
            uint256 minAmountOut = amountIn * 95 / 100;

            token0.approve(address(swapHelpers), amountIn);
            // Pre-mint output tokens to contract to simulate router swap result (if not already minted)
            if (token1.balanceOf(address(swapHelpers)) < minAmountOut) {
                token1.mint(address(swapHelpers), minAmountOut);
            }

            uint256 gasBefore = gasleft();
            swapHelpers.swapExactInSingle(poolKey, true, amountIn, minAmountOut, DEADLINE, RECEIVER, "");
            uint256 gasUsed = gasBefore - gasleft();

            console.log("Gas used for amount:", amountIn, gasUsed);
        }
    }

    receive() external payable { }
}
