// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.28;

import { IIntentOracle } from "../../src/interfaces/IIntentOracle.sol";

contract MockIntentOracle is IIntentOracle {
    mapping(address base => mapping(address quote => uint256 price)) public prices;
    uint64 public asOf;

    function set(address base, address quote, uint256 price, uint64 asOf_) external {
        prices[base][quote] = price;
        asOf = asOf_;
    }

    function read(bytes32, address base, address quote, bytes calldata) external view returns (uint256, uint64) {
        return (prices[base][quote], asOf);
    }
}
