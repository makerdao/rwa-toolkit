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

import {DssPsm} from "dss-psm/psm.sol";
import {AuthGemJoin5} from "dss-psm/join-5-auth.sol";
import {AuthGemJoin} from "dss-psm/join-auth.sol";

import {RwaOutputConduit3} from "./RwaOutputConduit3.sol";

contract RwaOutputConduit3Test is Test, DSMath {
    address me;

    TestVat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    TestToken usdx;
    DaiJoin daiJoin;
    Dai dai;

    AuthGemJoin5 joinA;
    DssPsm psm;
    RwaOutputConduit3 outputConduit;
    address testUrn;

    bytes32 constant ilk = "USDX-A";

    uint256 constant USDX_DECIMALS = 6;
    uint256 constant USDX_BASE_UNIT = 10**USDX_DECIMALS;
    uint256 constant USDX_MINT_AMOUNT = 1000 * USDX_BASE_UNIT;
    uint256 constant USDX_DAI_CONVERSION_FACTOR = 10**12;
    // Debt Ceiling 10x the normalized minted amount
    uint256 constant PSM_LINE_WAD = 10 * USDX_MINT_AMOUNT * USDX_DAI_CONVERSION_FACTOR;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Hope(address indexed usr);
    event Nope(address indexed usr);
    event Mate(address indexed usr);
    event Hate(address indexed usr);
    event Kiss(address indexed who);
    event Diss(address indexed who);
    event Push(address indexed to, uint256 wad);
    event File(bytes32 indexed what, address data);
    event Quit(address indexed quitTo, uint256 wad);
    event Yank(address indexed token, address indexed usr, uint256 amt);
    event Pick(address indexed who);

    function setUpMCDandPSM() internal {
        me = address(this);

        vat = new TestVat();
        vat = vat;

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        usdx = new TestToken("USDX", uint8(USDX_DECIMALS));
        usdx.mint(USDX_MINT_AMOUNT);

        vat.init(ilk);

        joinA = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(joinA));

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        psm = new DssPsm(address(joinA), address(daiJoin), address(vow));
        joinA.rely(address(psm));
        joinA.deny(me);

        pip = new DSValue();
        pip.poke(bytes32(uint256(1 * WAD))); // Spot = $1

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(1 * WAD));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(PSM_LINE_WAD));
        vat.file("Line", rad(PSM_LINE_WAD));
    }

    function setUp() public {
        setUpMCDandPSM();

        testUrn = vm.addr(420);
        outputConduit = new RwaOutputConduit3(address(dai), address(usdx), address(psm));
        outputConduit.file("quitTo", address(testUrn));
        outputConduit.mate(me);
        outputConduit.hope(me);
        outputConduit.kiss(me);
        outputConduit.pick(me);

        usdx.approve(address(joinA));
        psm.sellGem(me, USDX_MINT_AMOUNT);
    }

    function testSetWardAndEmitRelyOnDeploy() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(address(this));

        RwaOutputConduit3 c = new RwaOutputConduit3(address(dai), address(usdx), address(psm));

        assertEq(c.wards(address(this)), 1);
    }

    function testGiveUnlimitedApprovalToPsmDaiJoinOnDeploy() public {
        assertEq(dai.allowance(address(outputConduit), address(psm)), type(uint256).max);
    }

    function testRevertOnGemUnssuportedDecimals() public {
        TestToken testGem = new TestToken("USDX", 19);
        AuthGemJoin testJoin = new AuthGemJoin(address(vat), "TCOIN", address(testGem));
        DssPsm psmT = new DssPsm(address(testJoin), address(daiJoin), address(vow));

        vm.expectRevert("Math/sub-overflow");
        new RwaOutputConduit3(address(dai), address(testGem), address(psmT));
    }

    function testRevertInvalidConstructorArguments() public {
        vm.expectRevert();
        new RwaOutputConduit3(address(0), address(0), address(0));

        vm.expectRevert("RwaOutputConduit3/wrong-dai-for-psm");
        new RwaOutputConduit3(address(0), address(usdx), address(psm));

        vm.expectRevert("RwaOutputConduit3/wrong-gem-for-psm");
        new RwaOutputConduit3(address(dai), address(0), address(psm));
    }

    function testRevertOnPushWhenToAddressNotPicked() public {
        RwaOutputConduit3 c = new RwaOutputConduit3(address(dai), address(usdx), address(psm));
        c.mate(me);
        c.hope(me);

        vm.expectRevert("RwaOutputConduit3/to-not-picked");
        c.push();
    }

    function testRelyDeny() public {
        assertEq(outputConduit.wards(address(0)), 0);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Rely(address(0));

        outputConduit.rely(address(0));

        assertEq(outputConduit.wards(address(0)), 1);

        // --------------------
        vm.expectEmit(true, false, false, false);
        emit Deny(address(0));

        outputConduit.deny(address(0));

        assertEq(outputConduit.wards(address(0)), 0);
    }

    function testMateHate() public {
        assertEq(outputConduit.may(address(0)), 0);

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
        assertEq(outputConduit.can(address(0)), 0);

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

    function testFileQuitTo() public {
        assertEq(outputConduit.quitTo(), address(testUrn));

        address quitToAddress = vm.addr(1);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("quitTo"), quitToAddress);

        outputConduit.file(bytes32("quitTo"), quitToAddress);

        assertEq(outputConduit.quitTo(), quitToAddress);
    }

    function testFilePsm() public {
        assertEq(address(outputConduit.psm()), address(psm));

        DssPsm newPsm = new DssPsm(address(joinA), address(daiJoin), address(vow));
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("psm"), address(newPsm));

        outputConduit.file(bytes32("psm"), address(newPsm));

        assertEq(address(outputConduit.psm()), address(newPsm));
        assertEq(dai.allowance(address(outputConduit), address(psm)), 0);
        assertEq(dai.allowance(address(outputConduit), address(newPsm)), type(uint256).max);
    }

    function testRevertOnFilePsmWithWrongGemDaiAddresses() public {
        address newGem = address(new TestToken("GEM", 6));
        address joinNew = address(new AuthGemJoin5(address(vat), bytes32("GEM-A"), newGem));
        address newDai = address(new Dai(0));
        address newDaiJoin = address(new DaiJoin(address(vat), address(newDai)));

        address newPsm = address(new DssPsm(address(joinA), address(newDaiJoin), address(vow)));
        vm.expectRevert("RwaOutputConduit3/wrong-dai-for-psm");
        outputConduit.file(bytes32("psm"), newPsm);

        newPsm = address(new DssPsm(address(joinNew), address(daiJoin), address(vow)));
        vm.expectRevert("RwaOutputConduit3/wrong-gem-for-psm");
        outputConduit.file(bytes32("psm"), newPsm);
    }

    function testRevertOnFileUnrecognisedParam() public {
        vm.expectRevert("RwaOutputConduit3/unrecognised-param");
        outputConduit.file(bytes32("random"), address(0));
    }

    function testRevertOnUnauthorizedMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.rely(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.deny(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.hope(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.nope(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.hate(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.mate(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.kiss(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.diss(address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.file(bytes32("quitTo"), address(0));

        vm.expectRevert("RwaOutputConduit3/not-authorized");
        outputConduit.yank(address(0), me, 0);
    }

    function testRevertOnNotMateMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaOutputConduit3/not-mate");
        outputConduit.push();

        vm.expectRevert("RwaOutputConduit3/not-mate");
        outputConduit.quit();
    }

    function testRevertOnNotOperatorMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaOutputConduit3/not-operator");
        outputConduit.pick(address(0));
    }

    function testRevertOnPickAddressNotWhitelisted() public {
        vm.expectRevert("RwaOutputConduit3/not-bud");
        outputConduit.pick(vm.addr(1));
    }

    function testPick() public {
        // pick address
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
        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 500 * USDX_BASE_UNIT);
        outputConduit.push();

        assertEq(usdx.balanceOf(address(me)), 500 * USDX_BASE_UNIT);
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), 0, USDX_DAI_CONVERSION_FACTOR);
        assertEq(outputConduit.to(), address(0));
    }

    function testFuzzPermissionlessPush(address sender) public {
        outputConduit.mate(address(0));

        vm.assume(sender != me);

        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 500 * USDX_BASE_UNIT);

        vm.prank(sender);
        outputConduit.push();

        assertEq(usdx.balanceOf(address(me)), 500 * USDX_BASE_UNIT);
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), 0, USDX_DAI_CONVERSION_FACTOR);
        assertEq(outputConduit.to(), address(0));
    }

    function testPushAfterChangingPsm() public {
        // Init new PSM
        usdx.mint(USDX_MINT_AMOUNT);

        AuthGemJoin5 join = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(join));
        DssPsm newPsm = new DssPsm(address(join), address(daiJoin), address(vow));
        join.rely(address(newPsm));
        join.deny(me);

        usdx.approve(address(join));
        newPsm.sellGem(me, USDX_MINT_AMOUNT);

        // Change PSM
        outputConduit.file("psm", address(newPsm));

        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(address(me)), 2_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 1_500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 500 * USDX_BASE_UNIT);
        outputConduit.push();

        assertEq(usdx.balanceOf(address(me)), 500 * USDX_BASE_UNIT);
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), 0, USDX_DAI_CONVERSION_FACTOR);
        assertEq(outputConduit.to(), address(0));
    }

    function testPushAmountWhenAlreadyHaveSomeGemBalanceGetExactAmount() public {
        usdx.mint(100 * USDX_BASE_UNIT);
        usdx.transfer(address(outputConduit), 100 * USDX_BASE_UNIT);

        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 100 * USDX_BASE_UNIT);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 500 * USDX_BASE_UNIT);
        outputConduit.push(500 * WAD);

        assertEq(usdx.balanceOf(address(me)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(outputConduit)), 100 * USDX_BASE_UNIT);
        assertEq(dai.balanceOf(address(outputConduit)), 0);
        assertEq(outputConduit.to(), address(0));
    }

    function testPushAmountWhenAlreadyHaveSomeGemBalanceGetAll() public {
        usdx.mint(100 * USDX_BASE_UNIT);
        usdx.transfer(address(outputConduit), 100 * USDX_BASE_UNIT);

        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 100 * USDX_BASE_UNIT);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 500 * USDX_BASE_UNIT);
        outputConduit.push();

        assertEq(usdx.balanceOf(address(me)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(outputConduit)), 100 * USDX_BASE_UNIT);
        assertEq(outputConduit.to(), address(0));
    }

    function testPushAmountWhenAlreadyHaveSomeDaiBalance() public {
        assertEq(outputConduit.to(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500 * WAD);

        assertEq(dai.balanceOf(me), 500 * WAD);
        assertEq(dai.balanceOf(address(outputConduit)), 500 * WAD);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), 400 * USDX_BASE_UNIT);
        // Push only 400 DAI; leave 100 DAI in conduit
        outputConduit.push(400 * WAD);

        assertEq(usdx.balanceOf(address(me)), 400 * USDX_BASE_UNIT);
        assertEq(dai.balanceOf(address(outputConduit)), 100 * WAD);
        assertEq(outputConduit.to(), address(0));
    }

    function testPushAmountFuzz(uint256 wad) public {
        assertEq(outputConduit.to(), me);
        dai.transfer(address(outputConduit), dai.balanceOf(me));
        uint256 cDaiBalance = dai.balanceOf(address(outputConduit));
        uint256 usdxBalance = usdx.balanceOf(me);

        wad = bound(wad, 1 * WAD, cDaiBalance);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), wad / USDX_DAI_CONVERSION_FACTOR);
        outputConduit.push(wad);

        assertEq(usdx.balanceOf(me), usdxBalance + wad / USDX_DAI_CONVERSION_FACTOR);
        // We might lose some dust because of precision difference dai.decimals() > gem.decimals()
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), cDaiBalance - wad, USDX_DAI_CONVERSION_FACTOR);
    }

    function testExpectedGemAmtFuzz(uint256 wad) public {
        psm.file("tout", (1 * WAD) / 100); // add 1% fee

        assertEq(outputConduit.to(), me);
        dai.transfer(address(outputConduit), dai.balanceOf(me));
        uint256 cDaiBalance = dai.balanceOf(address(outputConduit));
        uint256 usdxBalance = usdx.balanceOf(me);

        wad = bound(wad, 1 * WAD, cDaiBalance);
        uint256 expectedGem = outputConduit.expectedGemAmt(wad);

        vm.expectEmit(true, true, false, false);
        emit Push(address(me), expectedGem);
        outputConduit.push(wad);

        assertEq(usdx.balanceOf(me), usdxBalance + expectedGem);
        // We might lose some dust because of precision difference
        assertApproxEqAbs(
            dai.balanceOf(address(outputConduit)),
            cDaiBalance - outputConduit.requiredDaiWad(expectedGem),
            USDX_DAI_CONVERSION_FACTOR
        );
    }

    function testRequiredDaiWadFuzz(uint256 amt) public {
        psm.file("tout", (1 * WAD) / 100); // add 1% fee

        assertEq(outputConduit.to(), me);
        uint256 daiBalance = dai.balanceOf(me);

        amt = bound(amt, 1 * USDX_BASE_UNIT, outputConduit.expectedGemAmt(daiBalance));
        uint256 requiredDai = outputConduit.requiredDaiWad(amt);

        dai.transfer(address(outputConduit), requiredDai);

        uint256 cDaiBalance = dai.balanceOf(address(outputConduit));
        uint256 usdxBalance = usdx.balanceOf(me);

        vm.expectEmit(true, false, false, false);
        emit Push(address(me), amt);
        outputConduit.push(requiredDai);

        assertEq(usdx.balanceOf(me), usdxBalance + amt);
        // We might lose some dust because of precision difference
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), cDaiBalance - requiredDai, USDX_DAI_CONVERSION_FACTOR);
    }

    function testRevertOnPushAmountMoreThenBalance() public {
        assertEq(dai.balanceOf(address(outputConduit)), 0);

        vm.expectRevert("RwaOutputConduit3/insufficient-swap-gem-amount");
        outputConduit.push(1);
    }

    function testRevertOnInsufficientSwapGemAmount() public {
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(address(me)), 1_000 * WAD);

        dai.transfer(address(outputConduit), 500);

        assertEq(dai.balanceOf(address(outputConduit)), 500);

        vm.expectRevert("RwaOutputConduit3/insufficient-swap-gem-amount");
        outputConduit.push();

        assertEq(dai.balanceOf(address(outputConduit)), 500);
    }

    function testRevertOnInsufficientGemAmountInPsm() public {
        // Mint additional 100 DAI, so the total balance is 1_100 DAI
        dai.mint(me, 100 * WAD);

        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
        assertEq(dai.balanceOf(address(me)), 1_100 * WAD);

        dai.transfer(address(outputConduit), 1_100 * WAD);

        assertEq(dai.balanceOf(address(outputConduit)), 1_100 * WAD);

        vat.mint(address(daiJoin), rad(1_100 * WAD));

        vm.expectRevert();
        // It will revert on vat.frob():
        //      urn.ink = _add(urn.ink, dink);
        // _add method will revert with empty message because ink = 1000 and dink = -1100
        outputConduit.push();

        assertEq(dai.balanceOf(address(outputConduit)), 1_100 * WAD);
    }

    function testQuit() public {
        assertEq(dai.balanceOf(outputConduit.quitTo()), 0);

        dai.transfer(address(outputConduit), 1_000 * WAD);

        assertEq(outputConduit.quitTo(), address(testUrn));
        assertEq(dai.balanceOf(address(outputConduit)), 1_000 * WAD);

        outputConduit.quit();

        assertEq(dai.balanceOf(outputConduit.quitTo()), 1_000 * WAD);
    }

    function testQuitAmountFuzz(uint256 wad) public {
        dai.transfer(address(outputConduit), dai.balanceOf(me));
        uint256 cBalance = dai.balanceOf(address(outputConduit));
        uint256 qBalance = dai.balanceOf(outputConduit.quitTo());

        vm.assume(cBalance >= wad);

        assertEq(outputConduit.quitTo(), address(testUrn));

        outputConduit.quit(wad);

        assertEq(dai.balanceOf(outputConduit.quitTo()), qBalance + wad);
        assertEq(dai.balanceOf(address(outputConduit)), cBalance - wad);
    }

    function testRevertOnQuitWhenQuitToAddressNotSet() public {
        outputConduit.file("quitTo", address(0));
        assertEq(outputConduit.quitTo(), address(0));

        vm.expectRevert("RwaOutputConduit3/invalid-quit-to-address");
        outputConduit.quit();
    }

    function testRevertOnQuitAmountMoreThenBalance() public {
        assertEq(dai.balanceOf(address(outputConduit)), 0);

        vm.expectRevert("Dai/insufficient-balance");
        outputConduit.quit(1);
    }

    function testYank() public {
        usdx.mint(100 * USDX_BASE_UNIT);
        usdx.transfer(address(outputConduit), 100 * USDX_BASE_UNIT);
        uint256 usdxBalance = usdx.balanceOf(me);

        assertEq(usdx.balanceOf(address(outputConduit)), 100 * USDX_BASE_UNIT);

        vm.expectEmit(true, true, false, false);
        emit Yank(address(usdx), address(me), 100 * USDX_BASE_UNIT);

        outputConduit.yank(address(usdx), me, 100 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(me), usdxBalance + 100 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(outputConduit)), 0);
    }

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * (RAY / WAD);
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * RAY;
    }
}

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
    constructor(
        address vat,
        address flapper,
        address flopper
    ) public Vow(vat, flapper, flopper) {}

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
