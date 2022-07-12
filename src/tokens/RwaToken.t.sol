/**
 * This file is a copy of https://goerli.etherscan.io/address/0xeb7C7DE82c3b05BD4059f11aE8f43dD7f1595bce#code.
 * The only change is the solidity version, since this repo is using 0.6.x
 */

// Copyright (C) 2020, 2021 Lev Livnev <lev@liv.nev.org.uk>
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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import {Test} from "forge-std/Test.sol";
import {RwaToken} from "./RwaToken.sol";

contract RwaTokenTest is Test {
    uint256 internal constant WAD = 10**18;

    RwaToken internal token;
    uint256 internal expectedTokensMinted = 1 * WAD;
    string internal name = "RWA001-Test";
    string internal symbol = "RWA001";

    function setUp() public {
        token = new RwaToken(name, symbol);
    }

    function testTokenAndSymbol() public {
        assertEq(token.name(), name);
        assertEq(token.symbol(), symbol);
    }

    function testTotalSupplyHardcoded() public {
        assertEq(token.totalSupply(), expectedTokensMinted);
    }

    function testTokenMinted() public {
        assertEq(token.balanceOf(address(this)), expectedTokensMinted);
    }
}
