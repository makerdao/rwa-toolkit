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
import {DSValueAbstract} from "dss-interfaces/dapp/DSValueAbstract.sol";
import {RwaCageSettlement} from "./RwaCageSettlement.sol";

/**
 * @author Henrique Barcelos <henrique@clio.finance>
 * @title An `RwaCageSettlement` factory.
 * @dev This contract allows anyone to easily deploy settlement contracts for
 * RWA deals if MakerDAO Governance ever issues an Emergency Shutdown.
 */
contract RwaCageSettlementFactory {
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
     * @dev The vat and ilk registry addresses are obtained from the chainlog.
     * @param _registry The Ilk registry.
     */
    constructor(address _registry) public {
        registry = IlkRegistryAbstract(_registry);
    }

    /**
     * @notice Deploys a new instance of `RwaCageSettlement` for the RWA deal identified by `ilk`,
     * using `coin` as currency.
     * @param ilk The ilk name.
     * @param coin The address of the currency to be used in the settlement.
     * @return The deployed `RwaCageSettlement` contract address.
     */
    function createRwaCageSettlement(bytes32 ilk, address coin) external returns (RwaCageSettlement) {
        address gem = registry.gem(ilk);
        require(gem != address(0), "RwaCageSettlementFactory/gem-does-not-exist");

        DSValueAbstract pip = DSValueAbstract(registry.pip(ilk));
        uint256 price = uint256(pip.read());

        RwaCageSettlement rcs = new RwaCageSettlement(coin, gem, price);

        emit RwaCageSettlementCreated(address(rcs), ilk, coin, gem, price);
        return rcs;
    }
}
