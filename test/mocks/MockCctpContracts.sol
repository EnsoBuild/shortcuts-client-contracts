/*
 * Copyright 2025 Circle Internet Group, Inc. All rights reserved.
 *
 * SPDX-License-Identifier: Apache-2.0
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * source: https://github.com/circlefin/hyperevm-circle-contracts/blob/ffcc978810fa88884c150ad2d6418aa02c576670/test/mocks/MockCctpContracts.sol
 * modified for solidity 0.8.28 and project-local interfaces and token mocks.
 */
pragma solidity ^0.8.28;

import { ITokenMinterV2 } from "../../src/interfaces/ITokenMessengerV2.sol";
import { MockERC20 } from "./MockERC20.sol";

contract MockMessageTransmitterV2 {
    MockERC20 public immutable localToken;

    constructor(address localToken_) {
        localToken = MockERC20(localToken_);
    }

    function receiveMessage(bytes calldata message, bytes calldata signature) external returns (bool) {
        require(keccak256(signature) != keccak256(bytes("revert")), "mock revert");

        if (keccak256(signature) == keccak256(bytes("return false"))) {
            return false;
        }

        uint256 amountIndex = 148 + 68;
        uint256 feeIndex = amountIndex + 96;
        uint256 amount;
        uint256 feeExecuted;
        assembly ("memory-safe") {
            amount := calldataload(add(message.offset, amountIndex))
            feeExecuted := calldataload(add(message.offset, feeIndex))
        }
        localToken.mint(msg.sender, amount - feeExecuted);

        return true;
    }
}

contract MockTokenMessengerV2 {
    ITokenMinterV2 public immutable localMinter;

    constructor(address localMinter_) {
        localMinter = ITokenMinterV2(localMinter_);
    }
}

contract MockTokenMinterV2 {
    address public immutable localToken;

    constructor(address localToken_) {
        localToken = localToken_;
    }

    function getLocalToken(uint32, bytes32) external view returns (address) {
        return localToken;
    }
}
