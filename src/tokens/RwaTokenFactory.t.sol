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

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.6.12;

import {Test} from "forge-std/Test.sol";
import {ForwardProxy} from "forward-proxy/ForwardProxy.sol";

import {RwaToken} from "./RwaToken.sol";
import {RwaTokenFactory} from "./RwaTokenFactory.sol";

contract RwaTokenFactoryTest is Test {
    uint256 internal constant WAD = 10**18;

    ForwardProxy internal recipient;
    RwaTokenFactory internal tokenFactory;
    string internal constant NAME = "RWA001-Test";
    string internal constant SYMBOL = "RWA001";

    event RwaTokenCreated(address indexed token, string name, string indexed symbol, address indexed recipient);

    function setUp() public {
        recipient = new ForwardProxy();
        tokenFactory = new RwaTokenFactory();
    }

    function testFailNameAndSymbolRequired() public {
        tokenFactory.createRwaToken("", "", address(this));
    }

    function testFailRecipientRequired() public {
        tokenFactory.createRwaToken(NAME, SYMBOL, address(0));
    }

    function testCanCreateRwaToken() public {
        RwaToken token = tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
        assertTrue(address(token) != address(0));
        assertEq(token.balanceOf(address(recipient)), 1 * WAD);
    }

    function testCreateRwaTokenEmitTheProperEvent() public {
        // `token` is the 1st topic, but we cannot check it since it will only be known after calling the method.
        vm.expectEmit(false, true, true, true);
        emit RwaTokenCreated(address(0), NAME, SYMBOL, address(recipient));

        tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
    }
}
