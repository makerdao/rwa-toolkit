// Copyright (C) 2022 Dai Foundation
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

// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.6.12;

import "dss-interfaces/dss/DaiJoinAbstract.sol";
import "dss-interfaces/dss/DaiAbstract.sol";

/**
 * @author Henrique Barcelos <henrique@clio.finance>
 * @title RwaJar: Facility to allow stability fee payments into the Surplus Buffer.
 * @dev Users can either send Dai directly to this conract or approve it to pull Dai from their wallet.
 */
contract RwaJar {
    /// @notice The DaiJoin adapter from MCD.
    DaiJoinAbstract public immutable daiJoin;
    /// @notice The Dai token.
    DaiAbstract public immutable dai;
    /// @notice The Vow address from MCD.
    address public immutable vow;

    /**
     * @notice Emitted whenever Dai is sent to the `vow`.
     * @param amount The amount of Dai sent.
     */
    event Toss(uint256 amount);

    /**
     * @dev The Dai address is obtained from the DaiJoin contract.
     * @param daiJoin_ The DaiJoin adapter from MCD.
     * @param vow_ The vow from MCD.
     */
    constructor(address daiJoin_, address vow_) public {
        daiJoin = DaiJoinAbstract(daiJoin_);
        dai = DaiAbstract(DaiJoinAbstract(daiJoin_).dai());
        vow = vow_;

        DaiAbstract(DaiJoinAbstract(daiJoin_).dai()).approve(daiJoin_, type(uint256).max);
    }

    /**
     * @notice Transfers any outstanding Dai balance in this contract to the `vow`.
     * @dev Reverts if there Dai balance of this contract is zero.
     * @dev This effectively burns ERC-20 Dai and credits it to the internal Dai balance of the `vow` in the Vat.
     */
    function void() external {
        uint256 balance = dai.balanceOf(address(this));
        require(balance > 0, "RwaJar/already-empty");

        daiJoin.join(vow, balance);

        emit Toss(balance);
    }

    /**
     * @notice Pulls `wad` amount of Dai from the sender's wallet into the `vow`.
     * @dev Requires `msg.sender` to have previously `approve`d this contract to spend at least `wad` Dai.
     * @dev This effectively burns ERC-20 Dai and credits it to the internal Dai balance of the `vow` in the Vat.
     * @param wad The amount of Dai.
     */
    function toss(uint256 wad) external {
        dai.transferFrom(msg.sender, address(this), wad);
        daiJoin.join(vow, wad);

        emit Toss(wad);
    }
}
