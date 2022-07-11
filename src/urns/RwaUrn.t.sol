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
import {RwaLiquidationOracle} from "../oracles/RwaLiquidationOracle.sol";
import {RwaUrn} from "./RwaUrn.sol";

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
    function canPush(address wat) public returns (bool ok) {
        ok = this.tryCall(address(wat), abi.encodeWithSignature("push()"));
    }
}

contract RwaUrnTest is Test, DSMath, TryPusher {
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

    function testFile() public {
        urn.file("outputConduit", address(123));
        assertEq(urn.outputConduit(), address(123));
        urn.file("jug", address(456));
        assertEq(address(urn.jug()), address(456));
    }

    function testUnpickAndPickNewRec() public {
        // lock some acme and draw some dai
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        // the dai can be pushed
        assertTrue(canPush(address(outConduit)));

        // unpick current rec
        usr.pick(address(0));

        // dai can't move
        assertTrue(!canPush(address(outConduit)));

        // deploy and whitelist new rec
        RwaUltimateRecipient newrec = new RwaUltimateRecipient(dai);
        outConduit.kiss(address(newrec));

        usr.pick(address(newrec));
        outConduit.push();

        assertEq(dai.balanceOf(address(newrec)), 400 ether);
    }

    function testCantPickUnkissedRec() public {
        RwaUltimateRecipient newrec = new RwaUltimateRecipient(dai);
        assertTrue(!usr.canPick(address(newrec)));
    }

    function testLockAndDraw() public {
        // check initial balances
        assertEq(dai.balanceOf(address(outConduit)), 0);
        assertEq(dai.balanceOf(address(rec)), 0);

        vm.warp(now + 10 days); // Let rate be > 1

        assertEq(vat.dai(address(urn)), 0);

        (uint256 ink, uint256 art) = vat.urns("acme", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);

        usr.lock(1 ether);
        usr.draw(399 ether); // with 400 will fail due vat ceiling (rounding)

        assertEq(vat.dai(address(urn)), 463899466724981907732616508); // dust from divup

        (, uint256 rate, , , ) = vat.ilks("acme");
        (ink, art) = vat.urns("acme", address(urn));
        assertEq(ink, 1 ether);
        assertEq(art, (rad(399 ether) + 463899466724981907732616508) / rate);

        // check the amount went to the output conduit
        assertEq(dai.balanceOf(address(outConduit)), 399 ether);
        assertEq(dai.balanceOf(address(rec)), 0);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        // push the amount to the receiver
        outConduit.push();
        assertEq(dai.balanceOf(address(outConduit)), 0);
        assertEq(dai.balanceOf(address(rec)), 399 ether);
    }

    function testDrawExceedsDebtCeiling() public {
        usr.lock(1 ether);
        assertTrue(!usr.canDraw(500 ether));
    }

    function testCantDrawUnlessHoped() public {
        usr.lock(1 ether);

        RwaUser rando = new RwaUser(urn, outConduit, inConduit);
        assertTrue(!rando.canDraw(100 ether));

        urn.hope(address(rando));
        assertEq(dai.balanceOf(address(outConduit)), 0);
        rando.draw(100 ether);
        assertEq(dai.balanceOf(address(outConduit)), 100 ether);
    }

    function testPartialRepay() public {
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        vm.warp(now + 30 days);

        rec.transfer(address(inConduit), 100 ether);
        assertEq(dai.balanceOf(address(inConduit)), 100 ether);

        inConduit.push();
        usr.wipe(100 ether);
        assertTrue(!usr.canFree(1 ether));
        usr.free(0.1 ether);

        (uint256 ink, uint256 art) = vat.urns("acme", address(urn));
        // > 300 because of accumulated interest
        assertTrue(art > 300 ether);
        assertTrue(art < 301 ether);
        assertEq(ink, 0.9 ether);
        assertEq(dai.balanceOf(address(inConduit)), 0 ether);
    }

    function testPartialRepayFuzz(
        uint256 drawAmount,
        uint256 wipeAmount,
        uint256 drawTime,
        uint256 wipeTime
    ) public {
        // Convert to reasonable numbers
        drawAmount = (drawAmount % 300 ether) + 100 ether; // 100-400 ether
        wipeAmount = wipeAmount % drawAmount; // 0-drawAmount ether
        drawTime = drawTime % 15 days; // 0-15 days
        wipeTime = wipeTime % 15 days; // 0-15 days

        usr.lock(1 ether);

        vm.warp(now + drawTime);
        jug.drip("acme");

        usr.draw(drawAmount);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        vm.warp(now + wipeTime);
        jug.drip("acme");

        rec.transfer(address(inConduit), wipeAmount);
        assertEq(dai.balanceOf(address(inConduit)), wipeAmount);

        inConduit.push();
        usr.wipe(wipeAmount);
    }

    function testRepayRoundingFuzz(
        uint256 drawAmt,
        uint256 drawTime,
        uint256 wipeTime
    ) public {
        // Convert to reasonable numbers
        drawAmt = (drawAmt % 300 ether) + 99.99 ether; // 99.99-399.99 ether
        drawTime = drawTime % 15 days; // 0-15 days
        wipeTime = wipeTime % 15 days; // 0-15 days

        (uint256 ink, uint256 art) = vat.urns("acme", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);

        usr.lock(1 ether);

        vm.warp(now + drawTime);
        jug.drip("acme");

        usr.draw(drawAmt);

        uint256 urnVatDust = vat.dai(address(urn));

        // A draw should leave less than 2 RAY dust
        assertTrue(urnVatDust < 2 * RAY);

        (, uint256 rate, , , ) = vat.ilks("acme");
        (ink, art) = vat.urns("acme", address(urn));
        assertEq(ink, 1 ether);
        assertEq(art, (rad(drawAmt) + urnVatDust) / rate);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        vm.warp(now + wipeTime);
        jug.drip("acme");

        (, rate, , , ) = vat.ilks("acme");

        uint256 fullWipeAmt = (art * rate) / RAY;
        if (fullWipeAmt * RAY < art * rate) {
            fullWipeAmt += 1;
        }

        // Forcing extra DAI balance to pay accumulated fee
        // hevm.store(address(dai), keccak256(abi.encode(address(rec), uint256(3))), bytes32(uint256(fullWipeAmt)));
        stdstore.target(address(dai)).sig("balanceOf(address)").with_key(address(rec)).checked_write(fullWipeAmt);
        // hevm.store(address(dai), bytes32(uint256(2)), bytes32(uint256(fullWipeAmt)));
        stdstore.target(address(dai)).sig("totalSupply()").with_key(address(rec)).checked_write(fullWipeAmt);
        // hevm.store(
        //     address(vat),
        //     keccak256(abi.encode(address(daiJoin), uint256(5))),
        //     bytes32(uint256(fullWipeAmt * RAY))
        // );
        stdstore.target(address(vat)).sig("dai(address)").with_key(address(daiJoin)).checked_write(fullWipeAmt * RAY);

        rec.transfer(address(inConduit), fullWipeAmt);
        assertEq(dai.balanceOf(address(inConduit)), fullWipeAmt);

        inConduit.push();
        usr.wipe(fullWipeAmt);

        (, art) = vat.urns("acme", address(urn));
        assertEq(art, 0);

        uint256 newUrnVatDust = vat.dai(address(urn));
        // A wipe should leave less than 1 RAY dust
        assertTrue(newUrnVatDust - urnVatDust < RAY);
    }

    function testFullRepay() public {
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        rec.transfer(address(inConduit), 400 ether);

        inConduit.push();
        usr.wipe(400 ether);
        usr.free(1 ether);

        (uint256 ink, uint256 art) = vat.urns("acme", address(urn));
        assertEq(art, 0);
        assertEq(ink, 0);
        assertEq(rwa.balanceOf(address(usr)), 1 ether);
    }

    function testQuit() public {
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        rec.transfer(address(inConduit), 400 ether);

        inConduit.push();
        vat.cage();
        assertEq(dai.balanceOf(address(urn)), 400 ether);
        assertEq(dai.balanceOf(address(outConduit)), 0);
        urn.quit();
        assertEq(dai.balanceOf(address(urn)), 0);
        assertEq(dai.balanceOf(address(outConduit)), 400 ether);
    }

    function testFailQuit() public {
        usr.lock(1 ether);
        usr.draw(400 ether);

        // usr nominates ultimate recipient
        usr.pick(address(rec));
        outConduit.push();

        rec.transfer(address(inConduit), 400 ether);

        inConduit.push();
        urn.quit();
    }
}
