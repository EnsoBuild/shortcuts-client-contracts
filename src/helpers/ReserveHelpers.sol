// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IFolio {
    function totalAssets() external view returns (address[] memory _assets, uint256[] memory _amounts);
    function totalSupply() external view returns (uint256);
}

/**
 * @notice Helper contract for Reserve Protocol Folio (Index DTF) integration.
 * Computes the maximum mintable shares given input amounts by finding the
 * minimum ratio across all basket tokens.
 *
 * Formula: shares = min(amountIn[i] * totalSupply / balance[i]) for all i
 */
contract ReserveHelpers {
    uint256 public constant VERSION = 1;

    error ReserveHelpers__InvalidAmountsLength();
    error ReserveHelpers__NoValidShares();

    /// @notice Calculate the minimum number of shares mintable given input amounts
    /// @param folio The Folio token address
    /// @param amounts The amounts of each underlying token to deposit (must match basket order and length)
    /// @return shares The minimum shares mintable across all input tokens
    function getMinShares(address folio, uint256[] calldata amounts) external view returns (uint256 shares) {
        (, uint256[] memory balances) = IFolio(folio).totalAssets();
        uint256 totalSupply = IFolio(folio).totalSupply();

        require(amounts.length == balances.length, ReserveHelpers__InvalidAmountsLength());

        shares = type(uint256).max;
        for (uint256 i = 0; i < balances.length; i++) {
            if (balances[i] == 0) {
                continue;
            }
            uint256 sharesForToken = (amounts[i] * totalSupply) / balances[i];
            if (sharesForToken < shares) {
                shares = sharesForToken;
            }
        }

        require(shares != type(uint256).max, ReserveHelpers__NoValidShares());
    }
}
