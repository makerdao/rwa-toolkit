// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
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

import "forge-std/Test.sol";
import "ds-token/token.sol";
import "ds-math/math.sol";
import "ds-value/value.sol";

import {Vat} from "dss/vat.sol";
import {Jug} from "dss/jug.sol";
import {Spotter} from "dss/spot.sol";
import {Vow} from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai} from "dss/dai.sol";

import {RwaInputConduit2} from "./RwaInputConduit2.sol";

contract RwaInputConduit2Test is Test, DSMath {
    address me = address(this);
    address to = address(0x1337);

    Dai dai = new Dai(0);
    RwaInputConduit2 inputConduit = new RwaInputConduit2(address(dai), to);

    function setUp() public {
        inputConduit.mate(me);
        inputConduit.may(me);
    }

    function testSetWardAndEmitRelyOnDeploy() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(me);

        RwaInputConduit2 c = new RwaInputConduit2(address(dai), to);

        assertEq(c.wards(me), 1);
    }

    function testRelyDeny() public {
        assertEq(inputConduit.wards(address(1)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(1));

        inputConduit.rely(address(1));

        assertEq(inputConduit.wards(address(1)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(1));

        inputConduit.deny(address(1));

        assertEq(inputConduit.wards(address(1)), 0);

        // Test make it permissionless
        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(0));

        inputConduit.rely(address(0));

        assertEq(inputConduit.wards(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(0));

        inputConduit.deny(address(0));

        assertEq(inputConduit.wards(address(0)), 0);
    }

    function testMateHate() public {
        assertEq(inputConduit.may(address(1)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Mate(address(1));

        inputConduit.mate(address(1));

        assertEq(inputConduit.may(address(1)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hate(address(1));

        inputConduit.hate(address(1));

        assertEq(inputConduit.may(address(1)), 0);

        assertEq(inputConduit.may(address(1)), 0);

        // Test make it permissionless
        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Mate(address(0));

        inputConduit.mate(address(0));

        assertEq(inputConduit.may(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hate(address(0));

        inputConduit.hate(address(0));

        assertEq(inputConduit.may(address(0)), 0);
    }

    function testFuzzRevertOnUnauthorizedMethods(address sender) public {
        vm.assume(sender != me);

        vm.startPrank(sender);

        vm.expectRevert("RwaInputConduit2/not-authorized");
        inputConduit.rely(sender);

        vm.expectRevert("RwaInputConduit2/not-authorized");
        inputConduit.deny(sender);

        vm.expectRevert("RwaInputConduit2/not-authorized");
        inputConduit.hate(sender);

        vm.expectRevert("RwaInputConduit2/not-authorized");
        inputConduit.mate(sender);
    }

    function testFuzzRevertOnNotMateMethods(address sender) public {
        vm.expectRevert("RwaInputConduit2/not-mate");

        vm.prank(sender);
        inputConduit.push();
    }

    function testFuzzMakeMethodsPermissionless(address sender) public {
        vm.assume(sender != address(0));

        inputConduit.rely(address(0));
        inputConduit.may(address(0));

        vm.startPrank(sender);

        inputConduit.rely(sender);
        assertEq(inputConduit.wards(sender), 1);

        inputConduit.mate(sender);
        assertEq(inputConduit.may(sender), 1);

        inputConduit.hate(sender);
        assertEq(inputConduit.may(sender), 0);

        inputConduit.deny(sender);
        assertEq(inputConduit.wards(sender), 0);
    }

    function testFileTo() public {
        address updatedTo = vm.addr(2);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("to"), updatedTo);

        inputConduit.file(bytes32("to"), updatedTo);

        assertEq(inputConduit.to(), updatedTo);
    }

    function testPush() public {
        dai.mint(me, 1_000 * WAD);

        assertEq(inputConduit.to(), to);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(inputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(inputConduit)), 500 * WAD);

        vm.expectEmit(true, false, false, true);
        emit Push(to, 500 * WAD);

        inputConduit.push();

        assertEq(dai.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(to), 500 * WAD);
    }

    function testFuzzPermissionlessPush(address sender) public {
        vm.assume(sender != me);

        dai.mint(me, 1_000 * WAD);

        assertEq(inputConduit.to(), to);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(inputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(inputConduit)), 500 * WAD);

        inputConduit.mate(address(0));

        vm.expectEmit(true, false, false, true);
        emit Push(to, 500 * WAD);

        vm.prank(sender);
        inputConduit.push();

        assertEq(dai.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(to), 500 * WAD);
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Mate(address indexed usr);
    event Hate(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Push(address indexed to, uint256 wad);
}
