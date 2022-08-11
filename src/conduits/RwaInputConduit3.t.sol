// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RwaUrn.t.sol -- Tests for the Urn contract
//
// Copyright (C) 2020-2021 Lev Livnev <lev@liv.nev.org.uk>
// Copyright (C) 2021-2022 Dai Foundation
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

import {Vat}              from "dss/vat.sol";
import {Jug}              from "dss/jug.sol";
import {Spotter}          from "dss/spot.sol";
import {Vow}              from "dss/vow.sol";
import {GemJoin, DaiJoin} from "dss/join.sol";
import {Dai}              from "dss/dai.sol";

import {RwaInputConduit3}  from "./RwaInputConduit3.sol";
// import {RwaOutputConduit} from "../conduits/RwaOutputConduit3.sol";

import {DssPsm}           from "dss-psm/psm.sol";
import {AuthGemJoin5}     from "dss-psm/join-5-auth.sol";


contract TestToken is DSToken {

    constructor(string memory symbol_, uint8 decimals_) public DSToken(symbol_) {
        decimals = decimals_;
    }

}

contract TestVat is Vat {
    function mint(address usr, uint256 rad) public {
        dai[usr] += rad;
    }
}

contract TestVow is Vow {
    constructor(address vat, address flapper, address flopper)
        public Vow(vat, flapper, flopper) {}
    // Total deficit
    function Awe() public view returns (uint256) {
        return vat.sin(address(this));
    }
    // Total surplus
    function Joy() public view returns (uint256) {
        return vat.dai(address(this));
    }
    // Unqueued, pre-auction debt
    function Woe() public view returns (uint256) {
        return sub(sub(Awe(), Sin), Ash);
    }
}

contract TestUrn {
    function balance(address gem) public view returns (uint256) {
        return DSToken(gem).balanceOf(address(this));
    }
}

contract RwaInputConduit3Test is Test, DSMath {
    address me;

    TestVat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    TestToken usdx;
    DaiJoin daiJoin;
    Dai dai;

    AuthGemJoin5 gemA;
    DssPsm psmA;
    RwaInputConduit3 inputConduit;
    TestUrn testUrn;

    bytes32 constant ilk = "usdx";

    uint256 constant TOLL_ONE_PCT = 10 ** 16;
    uint256 constant USDX_WAD = 10 ** 6;

    event Rely(address indexed usr);
    
    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10 ** 27;
    }

    function setUpMCDandPSM() internal {
        me = address(this);

        vat = new TestVat();
        vat = vat;

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        usdx = new TestToken("USDX", 6);
        usdx.mint(1000 * USDX_WAD);

        vat.init(ilk);

        gemA = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(gemA));

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        psmA = new DssPsm(address(gemA), address(daiJoin), address(vow));
        gemA.rely(address(psmA));
        gemA.deny(me);

        pip = new DSValue();
        pip.poke(bytes32(uint256(1 ether))); // Spot = $1

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(1 ether));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(1000 ether));
        vat.file("Line",      rad(1000 ether));
    }

    function setUp() public {
        setUpMCDandPSM();

        testUrn = new TestUrn();
        inputConduit = new RwaInputConduit3(address(dai), address(usdx), address(psmA), address(testUrn));
    }

    function testRevertOnDeployConduitWithWrongGem() public {
        vm.expectRevert("RwaInputConduit3/wrong-gem-for-psm");
        new RwaInputConduit3(address(dai), address(me), address(psmA), address(testUrn));
    }

    function testSetWardAndEmitRely() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(address(this));

        RwaInputConduit3 c = new RwaInputConduit3(address(dai), address(usdx), address(psmA), address(testUrn));

        assertEq(c.wards(address(this)), 1);
    }

    function testPsmWorks() public {
        assertEq(usdx.balanceOf(me), 1000 * USDX_WAD);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(gemA)), 0);
    }
}
