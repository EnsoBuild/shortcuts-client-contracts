// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { BridgeGuardian } from "../src/intent/BridgeGuardian.sol";
import { ChainId } from "../src/libraries/DataTypes.sol";
import { IntentDeployment } from "./IntentDeployment.sol";

interface ICctpMessenger {
    function localMessageTransmitter() external view returns (address);
    function localMinter() external view returns (address);
}

interface ICctpTransmitter {
    function localDomain() external view returns (uint32);
}

interface ICctpMinter {
    function burnLimitsPerMessage(address token) external view returns (uint256);
}

interface IAcrossChain {
    function chainId() external view returns (uint256);
}

interface ITokenDecimals {
    function decimals() external view returns (uint8);
}

/// BridgeGuardian's per-chain configuration: CCTP V2 and Across. The guardian has no admin, so this
/// table is fixed into each deployment: a new chain or bridge address means a new guardian, and new
/// leaves naming it. The constructor arguments differ per chain, and so does the guardian's address.
///
/// Addresses were checked on-chain before being written here (CCTP: the messenger's local domain
/// and a non-zero burn limit for the listed USDC; Across: the spoke pool's chainId and the 12-argument
/// bytes32 `deposit` in its implementation). `_checkLocal` checks the local ones again.
/// Sources: Circle's CCTP V2 contract and USDC address pages; the Across contracts npm package
/// (5.1.0), dist/broadcast/deployed-addresses.json; the Across available-routes list for the tokens.
abstract contract BridgeConfig is IntentDeployment {
    bytes32 internal constant GUARDIAN_SALT = "BridgeGuardian";

    uint8 private constant USDC = 0;
    uint8 private constant USDT = 1;

    /// CCTP V2 TokenMessengerV2: the same address on every CCTP V2 chain listed below.
    address internal constant TOKEN_MESSENGER = 0x28b5a0e9C621a5BadaA536219b3a228C8168cf5d;

    struct GuardianConfig {
        address tokenMessenger;
        address usdc;
        BridgeGuardian.CctpDestination[] destinations;
        address spokePool;
        BridgeGuardian.AcrossRoute[] routes;
    }

    /// A token Across carries between the chains below. Tokens of one family are delivered for
    /// each other.
    struct AcrossToken {
        uint256 chainId;
        uint8 family;
        address token;
        uint8 decimals;
    }

    /// This chain's guardian configuration. Both bridges are zero where neither runs here.
    function _guardianConfig() internal view returns (GuardianConfig memory config) {
        (config.tokenMessenger, config.usdc, config.destinations) = _cctp();
        config.spokePool = _spokePool(block.chainid);
        config.routes = _acrossRoutes();
    }

    function _guardianCreationCode(GuardianConfig memory config) internal pure returns (bytes memory) {
        bytes memory args =
            abi.encode(config.tokenMessenger, config.usdc, config.destinations, config.spokePool, config.routes);
        return abi.encodePacked(type(BridgeGuardian).creationCode, args);
    }

    /// This chain's CCTP messenger and USDC (zero when CCTP isn't here), and every other CCTP chain
    /// as a destination.
    function _cctp()
        internal
        view
        returns (address tokenMessenger, address usdc, BridgeGuardian.CctpDestination[] memory destinations)
    {
        BridgeGuardian.CctpDestination[] memory all = _cctpChains();
        uint256 local = type(uint256).max;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].chainId == block.chainid) {
                local = i;
            }
        }
        if (local == type(uint256).max) {
            return (address(0), address(0), new BridgeGuardian.CctpDestination[](0));
        }
        tokenMessenger = TOKEN_MESSENGER;
        usdc = all[local].usdc;
        destinations = new BridgeGuardian.CctpDestination[](all.length - 1);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (i != local) {
                destinations[n++] = all[i];
            }
        }
    }

    /// CCTP V2 chains among Enso's chains: chain id, Circle domain, native USDC.
    function _cctpChains() internal pure returns (BridgeGuardian.CctpDestination[] memory c) {
        c = new BridgeGuardian.CctpDestination[](17);
        c[0] = _d(ChainId.ETHEREUM, 0, 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        c[1] = _d(ChainId.AVALANCHE, 1, 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E);
        c[2] = _d(ChainId.OPTIMISM, 2, 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85);
        c[3] = _d(ChainId.ARBITRUM, 3, 0xaf88d065e77c8cC2239327C5EDb3A432268e5831);
        c[4] = _d(ChainId.BASE, 6, 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        c[5] = _d(ChainId.POLYGON, 7, 0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359);
        c[6] = _d(ChainId.UNICHAIN, 10, 0x078D782b760474a361dDA0AF3839290b0EF57AD6);
        c[7] = _d(ChainId.LINEA, 11, 0x176211869cA2b568f2A7D4EE941E073a821EE1ff);
        c[8] = _d(ChainId.SONIC, 13, 0x29219dd400f2Bf60E5a23d13Be72B486D4038894);
        c[9] = _d(ChainId.WORLD, 14, 0x79A02482A880bCE3F13e09Da970dC34db4CD24d1);
        c[10] = _d(ChainId.MONAD, 15, 0x754704Bc059F8C67012fEd69BC8A327a5aafb603);
        c[11] = _d(ChainId.SEI, 16, 0xe15fC38F6D8c56aF07bbCBe3BAf5708A2Bf42392);
        c[12] = _d(ChainId.HYPER, 19, 0xb88339CB7199b77E23DB6E890353E22632Ba630f);
        c[13] = _d(ChainId.INK, 21, 0x2D270e6886d130D724215A266106e6832161EAEd);
        c[14] = _d(ChainId.PLUME, 22, 0x222365EF19F7947e5484218551B56bb3965Aa7aF);
        c[15] = _d(ChainId.ARC, 26, 0x3600000000000000000000000000000000000000);
        c[16] = _d(ChainId.PLASMA, 33, 0x2d661C89D812261039AF9764eceaAee884f5F67F);
    }

    /// Across SpokePool on this chain; zero when Across isn't here.
    function _spokePool(uint256 chainId) internal pure returns (address spokePool) {
        if (chainId == ChainId.ETHEREUM) {
            spokePool = 0x5c7BCd6E7De5423a257D81B442095A1a6ced35C5;
        } else if (chainId == ChainId.OPTIMISM) {
            spokePool = 0x6f26Bf09B1C792e3228e5467807a900A503c0281;
        } else if (chainId == ChainId.BINANCE) {
            spokePool = 0x4e8E101924eDE233C13e2D8622DC8aED2872d505;
        } else if (chainId == ChainId.UNICHAIN) {
            spokePool = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
        } else if (chainId == ChainId.POLYGON) {
            spokePool = 0x9295ee1d8C5b022Be115A2AD3c30C72E34e7F096;
        } else if (chainId == ChainId.MONAD) {
            spokePool = 0xd2ecb3afe598b746F8123CaE365a598DA831A449;
        } else if (chainId == ChainId.WORLD) {
            spokePool = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
        } else if (chainId == ChainId.HYPER) {
            spokePool = 0x35E63eA3eb0fb7A3bc543C71FB66412e1F6B0E04;
        } else if (chainId == ChainId.SONEIUM) {
            spokePool = 0x3baD7AD0728f9917d1Bf08af5782dCbD516cDd96;
        } else if (chainId == ChainId.TEMPO) {
            spokePool = 0x2d4710F04Da90184255782d3715224A6C776955D;
        } else if (chainId == ChainId.MEGAETH) {
            spokePool = 0x3Db06DA8F0a24A525f314eeC954fC5c6a973d40E;
        } else if (chainId == ChainId.ROBINHOOD) {
            spokePool = 0xD29C85F15DF544bA632C9E25829fd29d767d7978;
        } else if (chainId == ChainId.ARC) {
            spokePool = 0x9b4A302A548c7e313c2b74C461db7b84d3074A84;
        } else if (chainId == ChainId.BASE) {
            spokePool = 0x09aea4b2242abC8bb4BB78D537A67a245A7bEC64;
        } else if (chainId == ChainId.PLASMA) {
            spokePool = 0x50039fAEfebef707cFD94D6d462fE6D10B39207a;
        } else if (chainId == ChainId.ARBITRUM) {
            spokePool = 0xe35e9842fceaCA96570B734083f4a58e8F7C5f2A;
        } else if (chainId == ChainId.AVALANCHE) {
            spokePool = 0xFE9D541c92E4e90437C7152A00244886dE37a658;
        } else if (chainId == ChainId.INK) {
            spokePool = 0xeF684C38F94F48775959ECf2012D7E864ffb9dd4;
        } else if (chainId == ChainId.LINEA) {
            spokePool = 0x7E63A5f1a8F0B4d0934B2f2327DAED3F6bb2ee75;
        }
    }

    /// This chain's Across routes: each local token to its family's token on every other chain.
    function _acrossRoutes() internal view returns (BridgeGuardian.AcrossRoute[] memory routes) {
        AcrossToken[] memory all = _acrossTokens();
        routes = new BridgeGuardian.AcrossRoute[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (all[i].chainId != block.chainid) {
                continue;
            }
            for (uint256 j; j < all.length; ++j) {
                if (all[j].family == all[i].family && all[j].chainId != block.chainid) {
                    routes[n++] = BridgeGuardian.AcrossRoute({
                        input: all[i].token,
                        chainId: all[j].chainId,
                        output: all[j].token,
                        // forge-lint: disable-next-line(unsafe-typecast)
                        decimals: int8(all[j].decimals) - int8(all[i].decimals)
                    });
                }
            }
        }
        assembly ("memory-safe") {
            mstore(routes, n)
        }
    }

    /// Stablecoins with an Across route between every pair of the chains listed: native USDC on the
    /// CCTP chains that have a spoke pool (Plasma has no USDC route), and USDT or USDT0.
    function _acrossTokens() internal pure returns (AcrossToken[] memory t) {
        BridgeGuardian.CctpDestination[] memory cctp = _cctpChains();
        t = new AcrossToken[](27);
        uint256 n;
        for (uint256 i; i < cctp.length; ++i) {
            if (cctp[i].chainId != ChainId.PLASMA && _spokePool(cctp[i].chainId) != address(0)) {
                t[n++] = _t(cctp[i].chainId, USDC, cctp[i].usdc, 6);
            }
        }
        t[n++] = _t(ChainId.ETHEREUM, USDT, 0xdAC17F958D2ee523a2206206994597C13D831ec7, 6);
        t[n++] = _t(ChainId.OPTIMISM, USDT, 0x94b008aA00579c1307B0EF2c499aD98a8ce58e58, 6);
        t[n++] = _t(ChainId.BINANCE, USDT, 0x55d398326f99059fF775485246999027B3197955, 18);
        t[n++] = _t(ChainId.UNICHAIN, USDT, 0x9151434b16b9763660705744891fA906F660EcC5, 6);
        t[n++] = _t(ChainId.POLYGON, USDT, 0xc2132D05D31c914a87C6611C10748AEb04B58e8F, 6);
        t[n++] = _t(ChainId.MONAD, USDT, 0xe7cd86e13AC4309349F30B3435a9d337750fC82D, 6);
        t[n++] = _t(ChainId.HYPER, USDT, 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, 6);
        t[n++] = _t(ChainId.MEGAETH, USDT, 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, 6);
        t[n++] = _t(ChainId.BASE, USDT, 0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2, 6);
        t[n++] = _t(ChainId.PLASMA, USDT, 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb, 6);
        t[n++] = _t(ChainId.ARBITRUM, USDT, 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9, 6);
        t[n++] = _t(ChainId.AVALANCHE, USDT, 0x9702230A8Ea53601f5cD2dc00fDBc13d4dF4A8c7, 6);
        t[n++] = _t(ChainId.INK, USDT, 0x0200C29006150606B650577BBE7B6248F58470c1, 6);
        t[n++] = _t(ChainId.LINEA, USDT, 0xA219439258ca9da29E9Cc4cE5596924745e12B93, 6);
        require(n == t.length, "across token count");
    }

    /// The guardian can't be reconfigured, so the local addresses are checked against the chain itself.
    function _checkLocal(GuardianConfig memory config) internal view {
        if (config.tokenMessenger != address(0)) {
            ICctpMessenger messenger = ICctpMessenger(config.tokenMessenger);
            uint32 domain = ICctpTransmitter(messenger.localMessageTransmitter()).localDomain();
            BridgeGuardian.CctpDestination[] memory all = _cctpChains();
            for (uint256 i; i < all.length; ++i) {
                if (all[i].chainId == block.chainid) {
                    require(all[i].domain == domain, "CCTP domain mismatch");
                }
            }
            require(ICctpMinter(messenger.localMinter()).burnLimitsPerMessage(config.usdc) != 0, "USDC not burnable");
        }
        if (config.spokePool != address(0)) {
            require(IAcrossChain(config.spokePool).chainId() == block.chainid, "spoke pool chain mismatch");
        }
        AcrossToken[] memory tokens = _acrossTokens();
        for (uint256 i; i < tokens.length; ++i) {
            if (tokens[i].chainId == block.chainid) {
                require(ITokenDecimals(tokens[i].token).decimals() == tokens[i].decimals, "token decimals mismatch");
            }
        }
    }

    function _t(uint256 chainId, uint8 family, address token, uint8 decimals)
        private
        pure
        returns (AcrossToken memory)
    {
        return AcrossToken({ chainId: chainId, family: family, token: token, decimals: decimals });
    }

    function _d(
        uint256 chainId,
        uint32 domain,
        address usdc
    )
        private
        pure
        returns (BridgeGuardian.CctpDestination memory)
    {
        return BridgeGuardian.CctpDestination({ chainId: chainId, domain: domain, usdc: usdc });
    }
}
