// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RwaCageSettlement.sol -- Facility to allow RWA deals to be fulfilled even
// if Emergency Shutdown is issued by the MakerDAO governance.
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.
pragma solidity 0.6.12;

import {DSTokenAbstract} from "dss-interfaces/dapp/DSTokenAbstract.sol";

/**
 * @title An RWA settlement facility to allow Dai holders to redeem RWA tokens
 * if MakerDAO Governance ever issues an Emergency Shutdown.
 * @dev This contract is completely permissionless and immutable because MakerDAO
 * governance would no longer exist, so it will not be able to make ammendments.
 */
contract RwaCageSettlement {
    /// @notice The max supported gem price, in Dai with 10**18 precision.
    /// @dev Set to 10**15 (1 quatrillion) Dai. Values larger than this will cause math overflow issues.
    ///                                     1 quatrillion ────┐    ┌──── 18 decimals
    ///                                                       ▼    ▼
    uint256 public constant MAX_SUPPORTED_PRICE = 10**uint256(15 + 18);
    /// @notice The min supported decimal places for gems and coins.
    uint256 public constant MIN_SUPPORTED_DECIMALS = 2;
    /// @notice The max supported decimal places for gems and coins.
    uint256 public constant MAX_SUPPORTED_DECIMALS = 27;

    /// @notice The token in which the redemption will be made, usually a stablecoin.
    DSTokenAbstract public immutable coin;
    /// @notice The collateral token that will need redemption, usually an `RwaToken`.
    DSTokenAbstract public immutable gem;
    /// @notice The price in Dai for each unit of `_gem`, with 10**18 precision.
    uint256 public immutable price;

    /// @dev The decimal conversion factor from gem to coin units.
    uint256 internal immutable conversionFactor;

    /**
     * @param sender The `msg.sender`.
     * @param coinAmt The amount of gems redeemed.
     * @param coinAmt The amount of coins sent back to the sender.
     */
    event Redeem(address indexed sender, uint256 gemAmt, uint256 coinAmt);

    /**
     * @param sender The `msg.sender`.
     * @param coinAmt The amount of coins deposited.
     */
    event Deposit(address indexed sender, uint256 coinAmt);

    /**
     * @param _coin The token in which the redemption will be made, usually a stablecoin.
     * @param _gem The collateral token that will need redemption, usually an `RwaToken`.
     * @param _price The price in Dai for each unit of `_gem`, with 10**18 precision.
     */
    constructor(
        address _coin,
        address _gem,
        uint256 _price
    ) public {
        require(_price > 0 && _price <= MAX_SUPPORTED_PRICE, "RwaCageSettlement/price-out-of-bounds");

        uint256 gemDecimals = DSTokenAbstract(_gem).decimals();
        require(
            gemDecimals >= MIN_SUPPORTED_DECIMALS && gemDecimals <= MAX_SUPPORTED_DECIMALS,
            "RwaCageSettlement/gem-decimals-out-of-bounds"
        );

        uint256 coinDecimals = DSTokenAbstract(_coin).decimals();
        require(
            coinDecimals >= MIN_SUPPORTED_DECIMALS && coinDecimals <= gemDecimals,
            "RwaCageSettlement/coin-decimals-out-of-bounds"
        );

        coin = DSTokenAbstract(_coin);
        gem = DSTokenAbstract(_gem);
        price = _price;

        // gemDecimals >= coinDecimals at this point.
        conversionFactor = 10**(gemDecimals - coinDecimals);
    }

    /**
     * @notice Redeem gems for coins, which are sent back to the sender.
     * @dev Precision conversion rounding issues may prevent redeeming very small amounts of gem.
     * Check `minRedeemable()` to know the smallest amount that can be redeemed.
     * @param gemAmt The amount of gems to redeem.
     */
    function redeem(uint256 gemAmt) external {
        uint256 coinAmt = gemToCoin(gemAmt);
        // Prevents a very small amount of gems to be redeemed, as this would essentially
        // burn the gem tokens without giving the caller anything back.
        require(coinAmt > 0, "RwaCageSettlement/too-few-gems");

        require(gem.transferFrom(msg.sender, address(this), gemAmt), "RwaCageSettlement/gem-transfer-failed");
        require(coin.transfer(msg.sender, coinAmt), "RwaCageSettlement/coin-transfer-failed");

        emit Redeem(msg.sender, gemAmt, coinAmt);
    }

    /**
     * @notice Deposits coins into this contract.
     * @dev Meant to be used by integrations. Regular users will just transfer coin to this contract.
     * @param coinAmt The amount of coins to deposit.
     */
    function deposit(uint256 coinAmt) external {
        require(coin.transferFrom(msg.sender, address(this), coinAmt), "RwaCageSettlement/coin-transfer-failed");

        emit Deposit(msg.sender, coinAmt);
    }

    /*//////////////////////////////////////
             Helper view functions
    //////////////////////////////////////*/

    /**
     * @notice Returns the amount of coins currently deposited in this contract.
     * @return coinAmt The coin balance of this contract.
     */
    function currentlyDeposited() public view returns (uint256 coinAmt) {
        return coin.balanceOf(address(this));
    }

    /**
     * @notice Returns the minimum amount of gems that can be redeemed by this contract.
     * @dev Because of rounding errors, sending a smaller amount of gems will lead to a coin transfer o value `0`.
     * @return gemAmt The min amount of gems required for redemption.
     */
    function minRedeemable() public view returns (uint256 gemAmt) {
        return coinToGem(1);
    }

    /**
     * @notice Returns the amount of gems that can currently be redeemed by this contract.
     * @return gemAmt The amount of gems currently available for redemption.
     */
    function currentlyRedeemable() public view returns (uint256 gemAmt) {
        return coinToGem(currentlyDeposited());
    }

    /**
     * @notice Returns the amount of gems already reedeemed by this contract.
     * @return gemAmt The amount of gems redeemed.
     */
    function totalRedeemed() public view returns (uint256 gemAmt) {
        return gem.balanceOf(address(this));
    }

    /*//////////////////////////////////////
                Unit Conversion
    //////////////////////////////////////*/

    /**
     * @notice Converts gems into coins with the required precision conversion.
     * @param gemAmt The amount of gems.
     * @return coinAmt The amount coins.
     */
    function gemToCoin(uint256 gemAmt) public view returns (uint256 coinAmt) {
        return mul(gemAmt, price) / conversionFactor / WAD;
    }

    /**
     * @notice Converts coins into gems with the required precision conversion.
     * @param coinAmt The amount coins.
     * @return gemAmt The amount of gems.
     */
    function coinToGem(uint256 coinAmt) public view returns (uint256 gemAmt) {
        return divup(mul(mul(coinAmt, WAD), conversionFactor), price);
    }

    /*//////////////////////////////////////
                      Math
    //////////////////////////////////////*/

    /// @dev The default 18 decimals precision.
    uint256 internal constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Math/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-overflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }

    /**
     * @dev Divides x/y, but rounds it up.
     */
    function divup(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = add(x, sub(y, 1)) / y;
    }
}
