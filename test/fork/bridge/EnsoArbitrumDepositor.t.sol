// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { EnsoArbitrumDepositorDeployer } from "../../../script/EnsoArbitrumDepositorDeployer.s.sol";
import { EnsoArbitrumDepositor } from "../../../src/bridge/EnsoArbitrumDepositor.sol";
import { IL1GatewayRouter } from "../../../src/bridge/interfaces/arbitrum/IL1GatewayRouter.sol";
import { IEnsoRouter, Token, TokenType } from "../../../src/interfaces/IEnsoRouter.sol";
import { MockERC20 } from "../../mocks/MockERC20.sol";
import { WeirollPlanner } from "../../utils/WeirollPlanner.sol";
import { Test, Vm } from "forge-std/Test.sol";
import { IERC20Errors } from "openzeppelin-contracts/interfaces/draft-IERC6093.sol";
import { IERC20, SafeERC20 } from "openzeppelin-contracts/token/ERC20/utils/SafeERC20.sol";

interface IEnsoShortcuts {
    function executeShortcut(
        bytes32 accountId,
        bytes32 requestId,
        bytes32[] calldata commands,
        bytes[] calldata state
    )
        external
        payable
        returns (bytes[] memory);
}

contract FeeOnTransferToken is MockERC20 {
    constructor() MockERC20("Fee", "FEE") { }

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            return;
        }
        super._update(from, address(0xdead), 1);
        super._update(from, to, value - 1);
    }
}

contract NoAllowanceDecrementToken is MockERC20 {
    constructor() MockERC20("NoDecrement", "NODEC") { }

    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        uint256 currentAllowance = allowance(from, msg.sender);
        if (currentAllowance < value) {
            revert ERC20InsufficientAllowance(msg.sender, currentAllowance, value);
        }
        _transfer(from, to, value);
        return true;
    }
}

contract GreedyGatewayRouter {
    uint256 public immutable extra;

    constructor(uint256 extra_) {
        extra = extra_;
    }

    function getGateway(address) external view returns (address) {
        return address(this);
    }

    function outboundTransferCustomRefund(
        address token,
        address,
        address,
        uint256 amount,
        uint256,
        uint256,
        bytes calldata
    )
        external
        payable
        returns (bytes memory)
    {
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        if (extra != 0) {
            IERC20(token).transferFrom(msg.sender, address(this), extra);
        }
        return "";
    }
}

contract EnsoArbitrumDepositorForkTest is Test {
    using SafeERC20 for IERC20;

    uint256 constant BLOCK_NUMBER = 26_141_400;

    address constant ARBITRUM_ROUTER = 0x72Ce9c846789fdB6fC1f34aC4AD25Dd9ef7031ef;
    address constant ARBITRUM_INBOX = 0x4Dbd4fc535Ac27206064B68FfCf827b0A60BAB3f;
    address constant ARBITRUM_STANDARD_GATEWAY = 0xa3A7B6F88361F48403514059F1F16C8E78d60EeC;
    address constant ARBITRUM_CUSTOM_GATEWAY = 0xcEe284F754E854890e311e3280b767F80797180d;
    address constant ROBINHOOD_ROUTER = 0x6a2E3a1e16FC29f27Ce61429746D558d656975bB;
    address constant ROBINHOOD_INBOX = 0x1A07cc4BD17E0118BdB54D70990D2158AbAD7a2D;

    address constant ENSO_ROUTER = 0xF75584eF6673aD213a685a1B58Cc0330B8eA22Cf;
    address constant ENSO_SHORTCUTS = 0x4Fe93ebC4Ce6Ae4f81601cC7Ce7139023919E003;

    address constant LINK = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address constant UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address constant ARB = 0xB50721BCf8d664c30412Cfbc6cf7a15145234ad1;
    address constant BNB = 0xB8c77482e45F1F44dE1745F52C74426C631bDD52;

    uint160 constant ALIAS_OFFSET = uint160(0x1111000000000000000000000000000000001111);
    bytes32 constant INBOX_MESSAGE_DELIVERED = keccak256("InboxMessageDelivered(uint256,bytes)");
    bytes32 constant DEPOSIT_INITIATED = keccak256("DepositInitiated(address,address,address,uint256,uint256)");

    uint256 constant MAX_GAS = 300_000;
    uint256 constant GAS_PRICE_BID = 1 gwei;
    uint256 constant MAX_SUBMISSION_COST = 0.005 ether;
    uint256 constant FEE = MAX_SUBMISSION_COST + MAX_GAS * GAS_PRICE_BID;

    EnsoArbitrumDepositor depositor;
    address owner;
    address caller = ENSO_SHORTCUTS;
    address receiver = makeAddr("receiver");
    address refunder = makeAddr("refunder");

    function setUp() public {
        vm.createSelectFork(vm.envString("ETHEREUM_RPC_URL"), BLOCK_NUMBER);
        EnsoArbitrumDepositorDeployer deployer = new EnsoArbitrumDepositorDeployer();
        (address deployed, address owner_) = deployer.run();
        depositor = EnsoArbitrumDepositor(deployed);
        owner = owner_;
        vm.deal(caller, 10 ether);
    }

    function test_deposit_standardGatewayToArbitrum() public {
        vm.recordLogs();
        _deposit(ARBITRUM_ROUTER, LINK, 100e18);
        _assertDeposit(ARBITRUM_INBOX, ARBITRUM_ROUTER, LINK);
    }

    function test_deposit_customGatewayToArbitrum() public {
        vm.recordLogs();
        _deposit(ARBITRUM_ROUTER, USDC, 1000e6);
        _assertDeposit(ARBITRUM_INBOX, ARBITRUM_ROUTER, USDC);
    }

    function test_deposit_reverseGatewayBurnsArb() public {
        uint256 amount = 100e18;
        uint256 supplyBefore = IERC20(ARB).totalSupply();

        vm.recordLogs();
        _deposit(ARBITRUM_ROUTER, ARB, amount);

        _assertDeposit(ARBITRUM_INBOX, ARBITRUM_ROUTER, ARB);
        assertEq(IERC20(ARB).totalSupply(), supplyBefore - amount, "arb not burned");
    }

    function test_deposit_usdtToRobinhoodTwice() public {
        vm.recordLogs();
        _deposit(ROBINHOOD_ROUTER, USDT, 1000e6);
        _assertDeposit(ROBINHOOD_INBOX, ROBINHOOD_ROUTER, USDT);

        vm.recordLogs();
        _deposit(ROBINHOOD_ROUTER, USDT, 500e6);
        _assertDeposit(ROBINHOOD_INBOX, ROBINHOOD_ROUTER, USDT);
    }

    function test_deposit_uniToRobinhood() public {
        vm.recordLogs();
        _deposit(ROBINHOOD_ROUTER, UNI, 50e18);
        _assertDeposit(ROBINHOOD_INBOX, ROBINHOOD_ROUTER, UNI);
    }

    function test_deposit_throughEnsoRouter() public {
        uint256 amount = 100e18;
        address user = makeAddr("user");
        deal(LINK, user, amount);
        vm.deal(user, FEE);

        bytes32[] memory commands = new bytes32[](2);
        bytes[] memory state = new bytes[](4);
        commands[0] = WeirollPlanner.buildCommand(IERC20.approve.selector, 0x01, 0x0001ffffffff, 0xff, LINK);
        commands[1] = WeirollPlanner.buildCommand(bytes4(0), 0x23, 0x0203ffffffff, 0xff, address(depositor));
        state[0] = abi.encode(address(depositor));
        state[1] = abi.encode(amount);
        state[2] = abi.encode(FEE);
        state[3] = abi.encodeCall(
            EnsoArbitrumDepositor.deposit,
            (
                IL1GatewayRouter(ARBITRUM_ROUTER),
                ARBITRUM_STANDARD_GATEWAY,
                IERC20(LINK),
                amount,
                receiver,
                refunder,
                MAX_GAS,
                GAS_PRICE_BID,
                MAX_SUBMISSION_COST
            )
        );

        Token[] memory tokensIn = new Token[](2);
        tokensIn[0] = Token(TokenType.ERC20, abi.encode(LINK, amount));
        tokensIn[1] = Token(TokenType.Native, abi.encode(FEE));
        bytes memory data = abi.encodeCall(IEnsoShortcuts.executeShortcut, (bytes32(0), bytes32(0), commands, state));

        vm.startPrank(user);
        IERC20(LINK).forceApprove(ENSO_ROUTER, amount);
        vm.recordLogs();
        IEnsoRouter(ENSO_ROUTER).routeMulti{ value: FEE }(tokensIn, data);
        vm.stopPrank();

        _assertDeposit(ARBITRUM_INBOX, ARBITRUM_ROUTER, LINK);
        assertEq(IERC20(LINK).balanceOf(ENSO_SHORTCUTS), 0, "shortcuts kept link");
    }

    function test_deposit_revertsForWrongMsgValue() public {
        vm.prank(caller);
        vm.expectRevert(abi.encodeWithSelector(EnsoArbitrumDepositor.WrongMsgValue.selector, FEE, FEE + 1));
        depositor.deposit{ value: FEE + 1 }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_STANDARD_GATEWAY,
            IERC20(LINK),
            1e18,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
    }

    function test_deposit_revertsWhenRouterHasNoGateway() public {
        uint256 amount = 1000e6;
        assertEq(IL1GatewayRouter(ARBITRUM_ROUTER).getGateway(USDT), address(0), "usdt gateway");
        deal(USDT, caller, amount);

        vm.startPrank(caller);
        IERC20(USDT).forceApprove(address(depositor), amount);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnsoArbitrumDepositor.UnexpectedGateway.selector, ARBITRUM_STANDARD_GATEWAY, address(0)
            )
        );
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_STANDARD_GATEWAY,
            IERC20(USDT),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();
    }

    function test_deposit_revertsForFeeOnTransferToken() public {
        uint256 amount = 100e18;
        FeeOnTransferToken token = new FeeOnTransferToken();
        token.mint(caller, amount);

        vm.startPrank(caller);
        token.approve(address(depositor), amount);
        vm.expectRevert(abi.encodeWithSelector(EnsoArbitrumDepositor.AmountMismatch.selector, amount, amount - 1));
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_STANDARD_GATEWAY,
            IERC20(address(token)),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();
    }

    function test_deposit_routerCannotTakeHeldTokens() public {
        uint256 held = 7e18;
        uint256 amount = 100e18;
        MockERC20 token = new MockERC20("Token", "TKN");
        token.mint(address(depositor), held);
        token.mint(caller, amount * 2);

        GreedyGatewayRouter greedyRouter = new GreedyGatewayRouter(held);
        vm.startPrank(caller);
        token.approve(address(depositor), amount);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(greedyRouter), 0, held)
        );
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(address(greedyRouter)),
            address(greedyRouter),
            IERC20(address(token)),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();

        GreedyGatewayRouter honestRouter = new GreedyGatewayRouter(0);
        vm.startPrank(caller);
        token.approve(address(depositor), amount);
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(address(honestRouter)),
            address(honestRouter),
            IERC20(address(token)),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();

        assertEq(token.balanceOf(address(depositor)), held, "held tokens moved");
        assertEq(token.allowance(address(depositor), address(honestRouter)), 0, "allowance left");
    }

    function test_withdraw_sendsHeldTokensToReceiver() public {
        uint256 held = 7e18;
        deal(LINK, address(depositor), held);

        _deposit(ARBITRUM_ROUTER, LINK, 100e18);
        assertEq(IERC20(LINK).balanceOf(address(depositor)), held, "held tokens moved");

        vm.prank(receiver);
        vm.expectRevert();
        depositor.withdraw(IERC20(LINK), receiver, held);

        vm.prank(owner);
        depositor.withdraw(IERC20(LINK), receiver, held);
        assertEq(IERC20(LINK).balanceOf(receiver), held, "not withdrawn");
        assertEq(IERC20(LINK).balanceOf(address(depositor)), 0, "depositor balance");
    }

    function test_deposit_tokenThatRejectsZeroApproval() public {
        vm.recordLogs();
        _deposit(ARBITRUM_ROUTER, BNB, 10e18);
        _assertDeposit(ARBITRUM_INBOX, ARBITRUM_ROUTER, BNB);
    }

    function test_deposit_revertsForUnexpectedGateway() public {
        vm.prank(caller);
        vm.expectRevert(
            abi.encodeWithSelector(
                EnsoArbitrumDepositor.UnexpectedGateway.selector, ARBITRUM_CUSTOM_GATEWAY, ARBITRUM_STANDARD_GATEWAY
            )
        );
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_CUSTOM_GATEWAY,
            IERC20(LINK),
            1e18,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
    }

    function test_deposit_revertsForZeroAddresses() public {
        vm.startPrank(caller);

        vm.expectRevert(EnsoArbitrumDepositor.ZeroAddress.selector);
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_STANDARD_GATEWAY,
            IERC20(LINK),
            1e18,
            address(0),
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );

        vm.expectRevert(EnsoArbitrumDepositor.ZeroAddress.selector);
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(ARBITRUM_ROUTER),
            ARBITRUM_STANDARD_GATEWAY,
            IERC20(LINK),
            1e18,
            receiver,
            address(0),
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );

        vm.stopPrank();
    }

    function test_deposit_revertsWhenHeldBalanceChanges() public {
        uint256 held = 7e18;
        uint256 amount = 100e18;
        NoAllowanceDecrementToken token = new NoAllowanceDecrementToken();
        token.mint(address(depositor), held);
        token.mint(caller, amount);

        GreedyGatewayRouter greedyRouter = new GreedyGatewayRouter(held);
        vm.startPrank(caller);
        token.approve(address(depositor), amount);
        vm.expectRevert(abi.encodeWithSelector(EnsoArbitrumDepositor.BalanceChanged.selector, held, 0));
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(address(greedyRouter)),
            address(greedyRouter),
            IERC20(address(token)),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();
    }

    function test_renounceOwnership_reverts() public {
        vm.prank(owner);
        vm.expectRevert(EnsoArbitrumDepositor.RenounceOwnershipDisabled.selector);
        depositor.renounceOwnership();
        assertEq(depositor.owner(), owner, "owner changed");
    }

    function _deposit(address router, address token, uint256 amount) private {
        address gateway = IL1GatewayRouter(router).getGateway(token);
        deal(token, caller, amount);

        vm.startPrank(caller);
        IERC20(token).forceApprove(address(depositor), amount);
        depositor.deposit{ value: FEE }(
            IL1GatewayRouter(router),
            gateway,
            IERC20(token),
            amount,
            receiver,
            refunder,
            MAX_GAS,
            GAS_PRICE_BID,
            MAX_SUBMISSION_COST
        );
        vm.stopPrank();
    }

    function _assertDeposit(address inbox, address router, address token) private {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        address gateway = IL1GatewayRouter(router).getGateway(token);
        uint256 retryables;
        uint256 deposits;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == gateway && logs[i].topics[0] == DEPOSIT_INITIATED) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), address(depositor), "deposit from");
                assertEq(address(uint160(uint256(logs[i].topics[2]))), receiver, "deposit to");
                ++deposits;
                continue;
            }
            if (logs[i].emitter != inbox || logs[i].topics[0] != INBOX_MESSAGE_DELIVERED) {
                continue;
            }
            bytes memory message = abi.decode(logs[i].data, (bytes));
            (
                ,
                uint256 l2CallValue,
                uint256 deposited,
                uint256 maxSubmissionCost,
                uint256 excessFeeRefund,
                uint256 beneficiary
            ) = abi.decode(message, (uint256, uint256, uint256, uint256, uint256, uint256));

            assertEq(l2CallValue, 0, "l2 call value");
            assertEq(deposited, FEE, "retryable deposit");
            assertEq(maxSubmissionCost, MAX_SUBMISSION_COST, "max submission cost");
            assertEq(address(uint160(excessFeeRefund)), refunder, "excess fee refund");
            assertEq(address(uint160(beneficiary)), _alias(address(depositor)), "beneficiary");
            ++retryables;
        }
        assertEq(retryables, 1, "retryables");
        assertEq(deposits, 1, "deposits");

        assertEq(IERC20(token).allowance(address(depositor), gateway), 0, "gateway allowance");
        assertEq(IERC20(token).balanceOf(address(depositor)), 0, "depositor balance");
    }

    function _alias(address account) private pure returns (address) {
        unchecked {
            return address(uint160(account) + ALIAS_OFFSET);
        }
    }
}
