// Copyright (C) 2020, 2021 Lev Livnev <lev@liv.nev.org.uk>
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
import {DSToken} from "ds-token/token.sol";
import {DSMath} from "ds-math/math.sol";

import {Vat} from "dss/vat.sol";
import {Jug} from "dss/jug.sol";
import {Spotter} from "dss/spot.sol";

import {DaiJoin} from "dss/join.sol";
import {AuthGemJoin} from "dss-gem-joins/join-auth.sol";

import {RwaToken} from "../tokens/RwaToken.sol";
import {RwaInputConduit2} from "../conduits/RwaInputConduit2.sol";
import {RwaOutputConduit2} from "../conduits/RwaOutputConduit2.sol";
import {RwaLiquidationOracle} from "../oracles/RwaLiquidationOracle.sol";
import {RwaUrn2} from "./RwaUrn2.sol";

interface Hevm {
    function warp(uint256) external;

    function store(
        address,
        bytes32,
        bytes32
    ) external;

    function load(address, bytes32) external returns (bytes32);
}

contract TokenUser {
    DSToken internal immutable dai;

    constructor(DSToken dai_) public {
        dai = dai_;
    }

    function transfer(address who, uint256 wad) external {
        dai.transfer(who, wad);
    }
}

contract TryCaller {
    function doCall(address addr, bytes memory data) external returns (bool) {
        assembly {
            let ok := call(gas(), addr, 0, add(data, 0x20), mload(data), 0, 0)
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

contract RwaOperator is TryCaller {
    RwaUrn2 internal urn;
    RwaOutputConduit2 internal outC;
    RwaInputConduit2 internal inC;

    constructor(
        RwaUrn2 urn_,
        RwaOutputConduit2 outC_,
        RwaInputConduit2 inC_
    ) public {
        urn = urn_;
        outC = outC_;
        inC = inC_;
    }

    function approve(
        DSToken tok,
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

    function quit() public {
        urn.quit();
    }

    function canPick(address who) public returns (bool) {
        return this.tryCall(address(outC), abi.encodeWithSignature("pick(address)", who));
    }

    function canDraw(uint256 wad) public returns (bool) {
        return this.tryCall(address(outC), abi.encodeWithSignature("draw(uint256)", wad));
    }

    function canFree(uint256 wad) public returns (bool) {
        return this.tryCall(address(outC), abi.encodeWithSignature("free(uint256)", wad));
    }
}

contract RwaMate is TryCaller {
    RwaOutputConduit2 internal outC;
    RwaInputConduit2 internal inC;

    constructor(RwaOutputConduit2 outC_, RwaInputConduit2 inC_) public {
        outC = outC_;
        inC = inC_;
    }

    function pushOut() public {
        return outC.push();
    }

    function pushIn() public {
        return inC.push();
    }

    function canPushOut() public returns (bool) {
        return this.tryCall(address(outC), abi.encodeWithSignature("push()"));
    }

    function canPushIn() public returns (bool) {
        return this.tryCall(address(inC), abi.encodeWithSignature("push()"));
    }
}

contract RwaUrn2Test is DSTest, DSMath {
    bytes20 internal constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    Hevm internal hevm;

    DSToken internal dai;
    RwaToken internal rwa;

    Vat internal vat;
    Jug internal jug;
    Spotter internal spotter;
    address internal constant VOW = address(123);

    DaiJoin internal daiJoin;
    AuthGemJoin internal gemJoin;

    RwaLiquidationOracle internal oracle;
    RwaUrn2 internal urn;

    RwaOutputConduit2 internal outConduit;
    RwaInputConduit2 internal inConduit;

    RwaOperator internal op;
    RwaMate internal mate;
    TokenUser internal rec;

    // Debt ceiling of 1000 DAI
    string internal constant DOC = "Please sign this";
    uint256 internal constant CEILING = 200 ether;
    uint256 internal constant EIGHT_PCT = 1000000002440418608258400030;

    uint48 internal constant TAU = 2 weeks;

    string internal name = "RWA-001";
    string internal symbol = "RWA001";

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * RAY;
    }

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));
        hevm.warp(104411200);

        rwa = new RwaToken(name, symbol);

        vat = new Vat();

        jug = new Jug(address(vat));
        jug.file("vow", VOW);
        vat.rely(address(jug));

        dai = new DSToken("Dai");
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.setOwner(address(daiJoin));

        vat.init("RWA001-A");
        vat.file("Line", 100 * rad(CEILING));
        vat.file("RWA001-A", "line", rad(CEILING));

        jug.init("RWA001-A");
        jug.file("RWA001-A", "duty", EIGHT_PCT);

        oracle = new RwaLiquidationOracle(address(vat), VOW);
        oracle.init("RWA001-A", wmul(CEILING, 1.1 ether), DOC, TAU);
        vat.rely(address(oracle));
        (, address pip, , ) = oracle.ilks("RWA001-A");

        spotter = new Spotter(address(vat));
        vat.rely(address(spotter));
        spotter.file("RWA001-A", "mat", RAY);
        spotter.file("RWA001-A", "pip", pip);
        spotter.poke("RWA001-A");

        gemJoin = new AuthGemJoin(address(vat), "RWA001-A", address(rwa));
        vat.rely(address(gemJoin));

        outConduit = new RwaOutputConduit2(address(dai));

        urn = new RwaUrn2(address(vat), address(jug), address(gemJoin), address(daiJoin), address(outConduit));
        gemJoin.rely(address(urn));
        inConduit = new RwaInputConduit2(address(dai), address(urn));

        op = new RwaOperator(urn, outConduit, inConduit);
        mate = new RwaMate(outConduit, inConduit);
        rec = new TokenUser(dai);

        // fund user with rwa
        rwa.transfer(address(op), 1 ether);

        urn.hope(address(op));

        inConduit.mate(address(mate));
        outConduit.mate(address(mate));
        outConduit.hope(address(op));

        op.approve(DSToken(address(rwa)), address(urn), type(uint256).max);
    }

    function testFile() public {
        urn.file("outputConduit", address(123));
        assertEq(urn.outputConduit(), address(123));
        urn.file("jug", address(456));
        assertEq(address(urn.jug()), address(456));
    }

    function testPickAndPush() public {
        uint256 amount = 200 ether;
        op.lock(1 ether);
        op.draw(amount);

        op.pick(address(rec));

        mate.pushOut();
        assertEq(dai.balanceOf(address(rec)), amount);
    }

    function testUnpickAndPickNewReceiver() public {
        uint256 amount = 200 ether;

        op.lock(1 ether);
        op.draw(amount);

        op.pick(address(rec));

        assertTrue(mate.canPushOut());

        op.pick(address(0));

        assertTrue(!mate.canPushOut());

        TokenUser newRec = new TokenUser(dai);

        op.pick(address(newRec));

        mate.pushOut();
        assertEq(dai.balanceOf(address(newRec)), amount);
    }

    function testFailPushBeforePick() public {
        uint256 amount = 200 ether;

        op.lock(1 ether);
        op.draw(amount);

        mate.pushOut();
    }

    function testLockAndDrawFuzz(uint24 secs) public {
        assertEq(dai.balanceOf(address(outConduit)), 0);
        assertEq(dai.balanceOf(address(rec)), 0);

        hevm.warp(block.timestamp + secs); // Let rate be > 1

        assertEq(vat.dai(address(urn)), 0);

        (uint256 ink, uint256 art) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);

        op.lock(1 ether);
        op.draw(199 ether);

        uint256 dustLimit = rad(15);

        assertLe(vat.dai(address(urn)), dustLimit);

        (, uint256 rate, , , ) = vat.ilks("RWA001-A");
        (ink, art) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 1 ether);
        assertLe((art * rate) - rad(199 ether), dustLimit);

        // check the amount went to the output conduit
        assertEq(dai.balanceOf(address(outConduit)), 199 ether);
        assertEq(dai.balanceOf(address(rec)), 0);

        // op nominates the receiver
        op.pick(address(rec));
        // push the amount to the receiver
        mate.pushOut();

        assertEq(dai.balanceOf(address(outConduit)), 0);
        assertEq(dai.balanceOf(address(rec)), 199 ether);
    }

    function testFailDrawAboveDebtCeiling() public {
        op.lock(1 ether);

        op.draw(1000 ether);
    }

    function testCannotDrawUnlessHoped() public {
        op.lock(1 ether);

        RwaOperator rando = new RwaOperator(urn, outConduit, inConduit);
        assertTrue(!rando.canDraw(1 ether));

        urn.hope(address(rando));
        assertEq(dai.balanceOf(address(outConduit)), 0);
        rando.draw(1 ether);
        assertEq(dai.balanceOf(address(outConduit)), 1 ether);
    }

    function testPartialRepayment() public {
        op.lock(1 ether);
        op.draw(200 ether);

        // op nominats the receiver
        op.pick(address(rec));
        mate.pushOut();

        hevm.warp(block.timestamp + 30 days);

        rec.transfer(address(inConduit), 100 ether);

        mate.pushIn();
        op.wipe(100 ether);

        // Since only ~half of the loan was repaid, op cannot free the total amount locked
        assertTrue(!op.canFree(1 ether));

        op.free(0.4 ether);
        (uint256 ink, uint256 art) = vat.urns("RWA001-A", address(urn));
        // 100 < art < 101 because of accumulated interest
        assertLt(art - 100 ether, 1 ether);
        assertEq(ink, 0.6 ether);
        assertEq(dai.balanceOf(address(inConduit)), 0);
    }

    function testPartialRepaymentFuzz(
        uint256 drawAmount,
        uint256 wipeAmount,
        uint256 drawTime,
        uint256 wipeTime
    ) public {
        drawAmount = (drawAmount % 150 ether) + 50 ether; // 50-200 ether
        wipeAmount = wipeAmount % drawAmount; // 0-drawAmount ether
        drawTime = drawTime % 15 days; // 0-15 days
        wipeTime = wipeTime % 15 days; // 0-15 days

        op.lock(1 ether);

        hevm.warp(now + drawTime);
        jug.drip("RWA001-A");
        op.draw(drawAmount);
        op.pick(address(rec));
        mate.pushOut();

        hevm.warp(now + wipeTime);
        jug.drip("RWA001-A");
        rec.transfer(address(inConduit), wipeAmount);
        assertEq(dai.balanceOf(address(inConduit)), wipeAmount);

        mate.pushIn();
        op.wipe(wipeAmount);
    }

    function testRepaymentWithRoundingFuzz(
        uint256 drawAmount,
        uint256 drawTime,
        uint256 wipeTime
    ) public {
        drawAmount = (drawAmount % 175 ether) + 24.99 ether; // 24.99-199.99 ether
        drawTime = drawTime % 15 days; // 0-15 days
        wipeTime = wipeTime % 15 days; // 0-15 days

        (uint256 ink, uint256 art) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);

        op.lock(1 ether);

        hevm.warp(block.timestamp + drawTime);
        jug.drip("RWA001-A");

        op.draw(drawAmount);

        uint256 urnVatDust = vat.dai(address(urn));

        // A draw should leave less than 2 RAY dust
        assertLt(urnVatDust, 2 * RAY);

        (, uint256 rate, , , ) = vat.ilks("RWA001-A");
        (ink, art) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 1 ether);
        assertLe((art * rate) - rad(drawAmount), urnVatDust);

        // op nomitates the receiver
        op.pick(address(rec));
        mate.pushOut();

        hevm.warp(block.timestamp + wipeTime);
        jug.drip("RWA001-A");

        (, rate, , , ) = vat.ilks("RWA001-A");

        uint256 fullWipeAmount = (art * rate) / RAY;
        if (fullWipeAmount * RAY < art * rate) {
            fullWipeAmount += 1;
        }

        /*/////////////////////////////////////////////////
          Forcing extra DAI balance to pay accumulated fee
        /////////////////////////////////////////////////*/

        // Overwrite `balanceOf` for `rec` on the Dai token contract.
        hevm.store(address(dai), keccak256(abi.encode(address(rec), 3)), bytes32(fullWipeAmount));
        // Overwrite `totalSupply` on the Dai Token contract.
        hevm.store(address(dai), bytes32(uint256(2)), bytes32(uint256(fullWipeAmount)));
        // Overwite the `dai` balance mapping for `rec` on the Vat contract.
        hevm.store(address(vat), keccak256(abi.encode(address(daiJoin), 5)), bytes32((fullWipeAmount * RAY)));

        /*///////////////////////////////////////////////*/

        rec.transfer(address(inConduit), fullWipeAmount);
        assertEq(dai.balanceOf(address(inConduit)), fullWipeAmount);

        mate.pushIn();
        op.wipe(fullWipeAmount);

        (, art) = vat.urns("RWA001-A", address(urn));
        assertEq(art, 0);

        uint256 newUrnVatDust = vat.dai(address(urn));
        assertLt(newUrnVatDust - urnVatDust, RAY);
    }

    function testFullRepayment() public {
        op.lock(1 ether);
        op.draw(200 ether);

        op.pick(address(rec));
        mate.pushOut();

        rec.transfer(address(inConduit), 200 ether);
        mate.pushIn();

        RwaOperator rando = new RwaOperator(urn, outConduit, inConduit);
        // authorizes `rando` on the urn
        urn.hope(address(rando));

        rando.wipe(200 ether);
        rando.free(1 ether);

        (uint256 ink, uint256 art) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 0);
        assertEq(art, 0);
        assertEq(rwa.balanceOf(address(rando)), 1 ether);
    }

    function testQuitByOperator() public {
        op.lock(1 ether);
        op.draw(200 ether);

        op.pick(address(rec));
        mate.pushOut();

        rec.transfer(address(inConduit), 200 ether);
        mate.pushIn();

        assertEq(dai.balanceOf(address(urn)), 200 ether);
        assertEq(dai.balanceOf(address(outConduit)), 0);
        op.quit();
        assertEq(dai.balanceOf(address(urn)), 0);
        assertEq(dai.balanceOf(address(outConduit)), 200 ether);
    }

    function testFailQuitNotOperatorVatStillAlive() public {
        op.lock(1 ether);
        op.draw(200 ether);

        op.pick(address(rec));
        mate.pushOut();

        rec.transfer(address(inConduit), 200 ether);
        mate.pushIn();

        urn.quit();
    }

    function testQuit() public {
        op.lock(1 ether);
        op.draw(200 ether);

        op.pick(address(rec));
        mate.pushOut();

        rec.transfer(address(inConduit), 200 ether);
        mate.pushIn();

        vat.cage();

        assertEq(dai.balanceOf(address(urn)), 200 ether);
        assertEq(dai.balanceOf(address(outConduit)), 0);
        urn.quit();
        assertEq(dai.balanceOf(address(urn)), 0);
        assertEq(dai.balanceOf(address(outConduit)), 200 ether);
    }

    function testFailQuitVatStillLive() public {
        op.lock(1 ether);
        op.draw(200 ether);

        op.pick(address(rec));
        mate.pushOut();

        rec.transfer(address(inConduit), 200 ether);
        mate.pushIn();

        urn.quit();
    }

    function testDecreaseGemValueOnFree() public {
        (uint256 ink, ) = vat.urns("RWA001-A", address(urn));
        assertEq(ink, 0);

        op.lock(1 ether);
        op.draw(200 ether);

        (uint256 inkAfterDraw, ) = vat.urns("RWA001-A", address(urn));
        assertEq(inkAfterDraw, 1 ether);

        // op nominats the receiver
        op.pick(address(rec));
        mate.pushOut();

        hevm.warp(block.timestamp + 30 days);

        rec.transfer(address(inConduit), 100 ether);

        mate.pushIn();
        op.wipe(100 ether);

        // Since only ~half of the loan was repaid, op cannot free the total amount locked
        assertTrue(!op.canFree(1 ether));

        op.free(0.4 ether);

        (uint256 inkAfterFree, ) = vat.urns("RWA001-A", address(urn));
        assertEq(inkAfterFree, 0.6 ether);
    }
}
