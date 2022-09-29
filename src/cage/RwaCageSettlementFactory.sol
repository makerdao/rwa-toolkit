// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RwaCageSettlementFactory.sol -- On-chain factory for RwaCageSettlement.
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

import {IlkRegistryAbstract} from "dss-interfaces/dss/IlkRegistryAbstract.sol";
import {VatAbstract} from "dss-interfaces/dss/VatAbstract.sol";
import {EndAbstract} from "dss-interfaces/dss/EndAbstract.sol";

import {RwaCageSettlement} from "./RwaCageSettlement.sol";

/**
 * @author Henrique Barcelos <henrique@clio.finance>
 * @title An `RwaCageSettlement` factory.
 * @dev This contract allows anyone to easily deploy settlement contracts for
 * RWA deals if MakerDAO Governance ever issues an Emergency Shutdown.
 */
contract RwaCageSettlementFactory {
    /// @notice The main accounting module Vat from MCD.
    VatAbstract public immutable vat;
    /// @notice The post-emergency shutdown facility End from MCD.
    EndAbstract public immutable end;
    /// @notice The Ilk Registry from MCD.
    IlkRegistryAbstract public immutable registry;

    /**
     * @param cageSettlement The contract created by the factory.
     * @param ilk The RWA ilk.
     * @param coin The address of the token to be used as currency after emergency shutdown.
     * @param gem The address of the collateral token.
     * @param price The price in Dai for each unit of `gem`, with 10**18 precision.
     */
    event RwaCageSettlementCreated(
        address indexed cageSettlement,
        bytes32 indexed ilk,
        address coin,
        address gem,
        uint256 price
    );

    /**
     * @param _vat The main accounting module.
     * @param _end The post-emergency shutdown facility.
     * @param _registry The Ilk registry.
     */
    constructor(
        address _vat,
        address _end,
        address _registry
    ) public {
        vat = VatAbstract(_vat);
        end = EndAbstract(_end);
        registry = IlkRegistryAbstract(_registry);
    }

    /**
     * @notice Deploys a new instance of `RwaCageSettlement` for the RWA deal identified by `ilk`,
     * using `coin` as currency.
     * @dev This function can be called before or after `cage()`.
     * When called before, it will get the live price for the gem from the Vat.
     * When called after, it will get the latest valid price for the gem from the End.
     * @param ilk The ilk name.
     * @param coin The address of the currency to be used in the settlement.
     * @return The deployed `RwaCageSettlement` contract address.
     */
    function createRwaCageSettlement(bytes32 ilk, address coin) external returns (RwaCageSettlement) {
        address gem = registry.gem(ilk);
        require(gem != address(0), "RwaCageSettlementFactory/gem-does-not-exist");

        uint256 spot;
        if (vat.live() == 1) {
            // Get the live price from the Vat.
            (, , spot, , ) = vat.ilks(ilk);
        } else {
            // Get the latest valid price from the End.
            // `end.tag` is the amount of GEM per unit of DAI with RAY precision.
            // To get the `spot` value, we need `1 / tag` with RAY precision.
            spot = rdiv(RAY, end.tag(ilk));
        }
        // Spot is a RAY (10**27 precision), so we need to convert it to WAD (10**18 precision).
        uint256 price = mul(spot, WAD) / RAY;

        RwaCageSettlement rcs = new RwaCageSettlement(coin, gem, price);

        emit RwaCageSettlementCreated(address(rcs), ilk, coin, gem, price);
        return rcs;
    }

    /*//////////////////////////////////////
                      Math
    //////////////////////////////////////*/

    /// @dev The default 18 decimals precision.
    uint256 internal constant WAD = 10**18;
    /// @dev 27 decimals precision.
    uint256 internal constant RAY = 10**27;

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
     * @dev Divides 2 nubmers with RAY precision. Rounds to zero if `x*y < RAY / 2`.
     */
    function rdiv(uint256 x, uint256 y) public pure returns (uint256 z) {
        z = add(mul(x, RAY), y / 2) / y;
    }
}
