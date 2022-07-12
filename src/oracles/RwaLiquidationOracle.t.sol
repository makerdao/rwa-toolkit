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

import {Vat} from "dss/vat.sol";
import {Jug} from "dss/jug.sol";
import {Spotter} from "dss/spot.sol";

import {DaiJoin} from "dss/join.sol";
import {AuthGemJoin} from "dss-gem-joins/join-auth.sol";

import {RwaToken} from "../tokens/RwaToken.sol";
import {RwaInputConduit} from "../conduits/RwaInputConduit.sol";
import {RwaOutputConduit} from "../conduits/RwaOutputConduit.sol";
import {RwaUrn} from "../urns/RwaUrn.sol";
import {RwaLiquidationOracle} from "./RwaLiquidationOracle.sol";

contract RwaUltimateRecipient {
    DSToken internal dai;

    constructor(DSToken dai_) public {
        dai = dai_;
    }

    function transfer(address who, uint256 wad) public {
        dai.transfer(who, wad);
    }
}

contract TryCaller {
    function doCall(address addr, bytes calldata data) external returns (bool) {
        bytes memory _data = data;
        assembly {
            let ok := call(gas(), addr, 0, add(_data, 0x20), mload(_data), 0, 0)
            let free := mload(0x40)
            mstore(free, ok)
            mstore(0x40, add(free, 32))
            revert(free, 32)
        }
    }

    function tryCall(address addr, bytes calldata data) external returns (bool ok) {
        (, bytes memory returned) = address(this).call(abi.encodeWithSignature("doCall(address,bytes)", addr, data));
        ok = abi.decode(returned, (bool));
    }
}

contract RwaUser is TryCaller {
    RwaUrn internal urn;
    RwaOutputConduit internal outC;
    RwaInputConduit internal inC;

    constructor(
        RwaUrn urn_,
        RwaOutputConduit outC_,
        RwaInputConduit inC_
    ) public {
        urn = urn_;
        outC = outC_;
        inC = inC_;
    }

    function approve(
        RwaToken tok,
        address who,
        uint256 wad
    ) public {
        tok.approve(who, wad);
    }

    function pick(address who) public {
        outC.pick(who);
    }

    function lock(uint256 wad) public {
        urn.lock(wad);
    }

    function free(uint256 wad) public {
        urn.free(wad);
    }

    function draw(uint256 wad) public {
        urn.draw(wad);
    }

    function wipe(uint256 wad) public {
        urn.wipe(wad);
    }

    function canPick(address who) public returns (bool ok) {
        ok = this.tryCall(address(outC), abi.encodeWithSignature("pick(address)", who));
    }

    function canDraw(uint256 wad) public returns (bool ok) {
        ok = this.tryCall(address(urn), abi.encodeWithSignature("draw(uint256)", wad));
    }

    function canFree(uint256 wad) public returns (bool ok) {
        ok = this.tryCall(address(urn), abi.encodeWithSignature("free(uint256)", wad));
    }
}

contract TryPusher is TryCaller {
    function can_push(address wat) public returns (bool ok) {
        ok = this.tryCall(address(wat), abi.encodeWithSignature("push()"));
    }
}

contract RwaLiquidationOracleTest is Test, DSMath, TryPusher {
    DSToken internal gov;
    DSToken internal dai;
    RwaToken internal rwa;

    Vat internal vat;
    Jug internal jug;
    address internal vow = address(123);
    Spotter internal spotter;

    DaiJoin internal daiJoin;
    AuthGemJoin internal gemJoin;

    RwaLiquidationOracle internal oracle;
    RwaUrn internal urn;

    RwaOutputConduit internal outConduit;
    RwaInputConduit internal inConduit;

    RwaUser internal usr;
    RwaUltimateRecipient internal rec;

    // debt ceiling of 400 dai
    uint256 internal ceiling = 400 ether;
    string internal doc = "Please sign on the dotted line.";

    // $ bc -l <<< 'scale=27; e( l(1.08)/(60 * 60 * 24 * 365) )'
    uint256 internal constant EIGHT_PCT = 1000000002440418608258400030;

    string internal name = "RWA-001";
    string internal symbol = "RWA001";

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10**27;
    }

    function setUp() public {
        vm.warp(604411200);

        // deploy governance token
        gov = new DSToken("GOV");
        gov.mint(100 ether);

        // deploy rwa token
        rwa = new RwaToken(name, symbol);

        // standard Vat setup
        vat = new Vat();

        jug = new Jug(address(vat));
        jug.file("vow", address(vow));
        vat.rely(address(jug));

        spotter = new Spotter(address(vat));
        vat.rely(address(spotter));

        dai = new DSToken("Dai");
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.setOwner(address(daiJoin));

        // the first RWA ilk is Acme Real World Assets Corporation
        vat.init("acme");
        vat.file("Line", 100 * rad(ceiling));
        vat.file("acme", "line", rad(ceiling));

        jug.init("acme");
        jug.file("acme", "duty", EIGHT_PCT);

        oracle = new RwaLiquidationOracle(address(vat), vow);
        oracle.init("acme", wmul(ceiling, 1.1 ether), doc, 2 weeks);
        vat.rely(address(oracle));
        (, address pip, , ) = oracle.ilks("acme");

        spotter.file("acme", "mat", RAY);
        spotter.file("acme", "pip", pip);
        spotter.poke("acme");

        gemJoin = new AuthGemJoin(address(vat), "acme", address(rwa));
        vat.rely(address(gemJoin));

        // deploy output dai conduit
        outConduit = new RwaOutputConduit(address(gov), address(dai));
        // deploy urn
        urn = new RwaUrn(address(vat), address(jug), address(gemJoin), address(daiJoin), address(outConduit));
        gemJoin.rely(address(urn));
        // deploy input dai conduit, pointed permanently at the urn
        inConduit = new RwaInputConduit(address(gov), address(dai), address(urn));

        // deploy user and ultimate dai recipient
        usr = new RwaUser(urn, outConduit, inConduit);
        rec = new RwaUltimateRecipient(dai);

        // fund user with rwa
        rwa.transfer(address(usr), 1 ether);

        // auth user to operate
        urn.hope(address(usr));
        outConduit.hope(address(usr));
        outConduit.kiss(address(rec));

        usr.approve(rwa, address(urn), uint256(-1));
    }

    function testOracleCure() public {
        usr.lock(1 ether);
        assertTrue(usr.canDraw(10 ether));

        // flash the liquidation beacon
        vat.file("acme", "line", rad(0));
        oracle.tell("acme");

        // not able to borrow
        assertTrue(!usr.canDraw(10 ether));

        vm.warp(block.timestamp + 1 weeks);

        oracle.cure("acme");
        vat.file("acme", "line", rad(ceiling));
        assertTrue(oracle.good("acme"));

        // able to borrow
        assertEq(dai.balanceOf(address(rec)), 0);
        usr.draw(100 ether);
        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();
        assertEq(dai.balanceOf(address(rec)), 100 ether);
    }

    function testFailOracleCureUnknownIlk() public {
        // unknown ilk ecma
        oracle.cure("ecma");
    }

    function testFailOracleCureNotInRemediation() public {
        oracle.cure("acme");
    }

    function testFailOracleCureNotInRemediationAnymore() public {
        usr.lock(1 ether);
        assertTrue(usr.canDraw(10 ether));

        // flash the liquidation beacon
        vat.file("acme", "line", rad(0));
        oracle.tell("acme");

        // not able to borrow
        assertTrue(!usr.canDraw(10 ether));

        vm.warp(block.timestamp + 1 weeks);

        oracle.cure("acme");
        vat.file("acme", "line", rad(ceiling));
        assertTrue(oracle.good("acme"));

        // able to borrow
        assertEq(dai.balanceOf(address(rec)), 0);
        usr.draw(100 ether);
        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();
        assertEq(dai.balanceOf(address(rec)), 100 ether);
        oracle.cure("acme");
    }

    function testOracleCull() public {
        usr.lock(1 ether);
        // not at full utilisation
        usr.draw(200 ether);

        // flash the liquidation beacon
        vat.file("acme", "line", rad(0));
        oracle.tell("acme");

        // not able to borrow
        assertTrue(!usr.canDraw(10 ether));

        vm.warp(block.timestamp + 1 weeks);
        // still in remeditation period
        assertTrue(oracle.good("acme"));

        vm.warp(block.timestamp + 2 weeks);

        assertEq(vat.gem("acme", address(oracle)), 0);
        // remediation period has elapsed
        assertTrue(!oracle.good("acme"));
        oracle.cull("acme", address(urn));

        assertTrue(!usr.canDraw(10 ether));

        (uint256 ink, uint256 art) = vat.urns("acme", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);

        assertEq(vat.sin(vow), rad(200 ether));

        // after the write-off, the gem goes to the oracle
        assertEq(vat.gem("acme", address(oracle)), 1 ether);

        spotter.poke("acme");
        (, , uint256 spot, , ) = vat.ilks("acme");
        assertEq(spot, 0);
    }

    function testOracleUnremediedLoanIsNotGood() public {
        usr.lock(1 ether);
        usr.draw(200 ether);

        vat.file("acme", "line", 0);
        oracle.tell("acme");
        assertTrue(oracle.good("acme"));

        vm.warp(block.timestamp + 3 weeks);
        assertTrue(!oracle.good("acme"));
    }

    function testOracleCullTwoUrns() public {
        RwaUrn urn2 = new RwaUrn(address(vat), address(jug), address(gemJoin), address(daiJoin), address(outConduit));
        gemJoin.rely(address(urn2));
        RwaUser usr2 = new RwaUser(urn2, outConduit, inConduit);
        usr.approve(rwa, address(this), uint256(-1));
        rwa.transferFrom(address(usr), address(usr2), 0.5 ether);
        usr2.approve(rwa, address(urn2), uint256(-1));
        urn2.hope(address(usr2));
        usr.lock(0.5 ether);
        usr2.lock(0.5 ether);
        usr.draw(100 ether);
        usr2.draw(100 ether);

        assertTrue(usr.canDraw(1 ether));
        assertTrue(usr2.canDraw(1 ether));

        vat.file("acme", "line", 0);
        oracle.tell("acme");

        assertTrue(!usr.canDraw(1 ether));
        assertTrue(!usr2.canDraw(1 ether));

        vm.warp(block.timestamp + 3 weeks);

        oracle.cull("acme", address(urn));
        assertEq(vat.sin(vow), rad(100 ether));
        oracle.cull("acme", address(urn2));
        assertEq(vat.sin(vow), rad(200 ether));
    }

    function testOracleBump() public {
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        // can't borrow more, ceiling exceeded
        assertTrue(!usr.canDraw(1 ether));

        // increase ceiling by 200 dai
        vat.file("acme", "line", rad(ceiling + 200 ether));

        // still can't borrow much more, vault is unsafe
        assertTrue(usr.canDraw(1 ether));
        assertTrue(!usr.canDraw(200 ether));

        // bump the price of acme
        oracle.bump("acme", wmul(ceiling + 200 ether, 1.1 ether));
        spotter.poke("acme");

        usr.draw(200 ether);
        // recipient must be picked again for 2nd push
        usr.pick(address(rec));
        outConduit.push();

        assertEq(dai.balanceOf(address(rec)), 600 ether);
    }

    function testFailOracleBumpUnknownIlk() public {
        // unknown ilk ecma
        oracle.bump("ecma", wmul(ceiling + 200 ether, 1.1 ether));
    }

    function testFailOracleBumpInRemediation() public {
        vat.file("acme", "line", 0);
        oracle.tell("acme");
        oracle.bump("acme", wmul(ceiling + 200 ether, 1.1 ether));
    }
}
