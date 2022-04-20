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

import {DSTest} from "ds-test/test.sol";
import {ForwardProxy} from "forward-proxy/ForwardProxy.sol";

import {RwaToken} from "./RwaToken.sol";
import {RwaTokenFactory} from "./RwaTokenFactory.sol";

contract RwaTokenFactoryTest is DSTest {
    uint256 internal constant WAD = 10**18;

    ForwardProxy recipient;
    RwaTokenFactory tokenFactory;
    string internal constant NAME = "RWA001-Test";
    string internal constant SYMBOL = "RWA001";

    function setUp() public {
        recipient = new ForwardProxy();
        tokenFactory = new RwaTokenFactory();
    }

    function testFail_nameAndSymbolRequired() public {
        tokenFactory.createRwaToken("", "", address(this));
    }

    function testFail_recipientRequired() public {
        tokenFactory.createRwaToken(NAME, SYMBOL, address(0));
    }

    function testFail_failOnAlreadyExistSymbol() public {
        RwaToken token = tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
        assertTrue(address(token) != address(0));
        tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
    }

    function test_canCreateRwaToken() public {
        RwaToken token = tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
        assertTrue(address(token) != address(0));
        assertEq(token.balanceOf(address(recipient)), 1 * WAD);
    }

    function test_canGetRegistry() public {
        RwaToken token = tokenFactory.createRwaToken(NAME, SYMBOL, address(recipient));
        assertTrue(address(token) != address(0));
        bytes32 symbol = tokenFactory.stringToBytes32(SYMBOL);
        bytes32[1] memory tokens = [symbol];
        bytes32[] memory tokensFromFactory = tokenFactory.list();
        assertEq(tokenFactory.count(), tokens.length);
        assertEq(tokensFromFactory[0], tokens[0]);
        assertEq(tokenFactory.tokenAddresses(symbol), address(token));
    }

    function test_truncatesLargeStrings() public {
        string memory str40Bytes = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";
        string memory str32Bytes = "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz";

        bytes32 truncated = tokenFactory.stringToBytes32(str40Bytes);
        bytes32 notTruncated = tokenFactory.stringToBytes32(str32Bytes);

        assertEq(truncated, notTruncated);
    }
}
