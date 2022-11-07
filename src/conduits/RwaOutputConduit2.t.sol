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

import {RwaOutputConduit2} from "./RwaOutputConduit2.sol";

contract RwaOutputConduit2Test is Test, DSMath {
    address me = address(this);

    Dai dai = new Dai(0);
    RwaOutputConduit2 outputConduit = new RwaOutputConduit2(address(dai));

    function setUp() public {
        outputConduit.mate(me);
        outputConduit.hope(me);
        outputConduit.kiss(me);
        outputConduit.pick(me);
    }

    function testSetWardAndEmitRelyOnDeploy() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(me);

        RwaOutputConduit2 c = new RwaOutputConduit2(address(dai));

        assertEq(c.wards(me), 1);
    }

    function testRevertOnPushWhenToAddressNotPicked() public {
        RwaOutputConduit2 c = new RwaOutputConduit2(address(dai));

        c.mate(me);
        c.hope(me);

        vm.expectRevert("RwaOutputConduit2/to-not-picked");
        c.push();
    }

    function testRelyDeny() public {
        assertEq(outputConduit.wards(address(1)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(1));

        outputConduit.rely(address(1));

        assertEq(outputConduit.wards(address(1)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(1));

        outputConduit.deny(address(1));

        assertEq(outputConduit.wards(address(1)), 0);
    }

    function testMateHate() public {
        assertEq(outputConduit.may(address(1)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Mate(address(1));

        outputConduit.mate(address(1));

        assertEq(outputConduit.may(address(1)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hate(address(1));

        outputConduit.hate(address(1));

        assertEq(outputConduit.may(address(1)), 0);

        assertEq(outputConduit.may(address(1)), 0);

        // Test make it permissionless
        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Mate(address(0));

        outputConduit.mate(address(0));

        assertEq(outputConduit.may(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hate(address(0));

        outputConduit.hate(address(0));

        assertEq(outputConduit.may(address(0)), 0);
    }

    function testHopeNope() public {
        assertEq(outputConduit.can(address(1)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hope(address(1));

        outputConduit.hope(address(1));

        assertEq(outputConduit.can(address(1)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Nope(address(1));

        outputConduit.nope(address(1));

        assertEq(outputConduit.can(address(1)), 0);

        // Test make it permissionless
        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Hope(address(0));

        outputConduit.hope(address(0));

        assertEq(outputConduit.can(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Nope(address(0));

        outputConduit.nope(address(0));

        assertEq(outputConduit.can(address(0)), 0);
    }

    function testKissDiss() public {
        assertEq(outputConduit.bud(address(0)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Kiss(address(0));

        outputConduit.kiss(address(0));

        assertEq(outputConduit.bud(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Diss(address(0));

        outputConduit.diss(address(0));

        assertEq(outputConduit.bud(address(0)), 0);
    }

    function testFuzzRevertOnUnauthorizedMethods(address sender) public {
        vm.startPrank(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.rely(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.deny(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.hope(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.nope(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.hate(sender);

        vm.expectRevert("RwaOutputConduit2/not-authorized");
        outputConduit.mate(sender);
    }

    function testFuzzRevertOnNotMateMethods(address sender) public {
        vm.expectRevert("RwaOutputConduit2/not-mate");

        vm.prank(sender);
        outputConduit.push();
    }

    function testFuzzRevertOnNotOperatorMethods(address sender) public {
        vm.expectRevert("RwaOutputConduit2/not-operator");

        vm.prank(sender);
        outputConduit.pick(sender);
    }

    function testPick() public {
        address who = vm.addr(2);
        outputConduit.kiss(who);

        vm.expectEmit(true, false, false, false);
        emit Pick(who);
        outputConduit.pick(who);
        assertEq(outputConduit.to(), who);

        // pick zero address
        vm.expectEmit(true, false, false, false);
        emit Pick(address(0));

        outputConduit.pick(address(0));
        assertEq(outputConduit.to(), address(0));
    }

    function testFuzzPermissionlessPick(address sender, address who) public {
        vm.assume(sender != me);
        vm.assume(who != address(0));

        outputConduit.hope(address(0));
        outputConduit.kiss(who);

        vm.expectEmit(true, false, false, false);
        emit Pick(who);

        vm.prank(sender);
        outputConduit.pick(who);

        assertEq(outputConduit.to(), who);
    }

    function testPush() public {
        dai.mint(me, 1_000 * WAD);

        assertEq(outputConduit.to(), me);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, false, false, true);
        emit Push(me, 500 * WAD);

        outputConduit.push();

        assertEq(outputConduit.to(), address(0));
        assertEq(dai.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(me), 1_000 * WAD);
    }

    function testFuzzPermissionlessPush(address sender) public {
        vm.assume(sender != me);
        outputConduit.mate(address(0));

        dai.mint(me, 1_000 * WAD);

        assertEq(outputConduit.to(), me);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, false, false, true);
        emit Push(me, 500 * WAD);

        vm.prank(sender);
        outputConduit.push();

        assertEq(outputConduit.to(), address(0));
        assertEq(dai.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(me), 1_000 * WAD);
    }

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Hope(address indexed usr);
    event Nope(address indexed usr);
    event Kiss(address indexed who);
    event Diss(address indexed who);
    event Mate(address indexed usr);
    event Hate(address indexed usr);
    event Push(address indexed to, uint256 wad);
    event Pick(address indexed who);
}
