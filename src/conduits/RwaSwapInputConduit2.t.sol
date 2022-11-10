// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
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

import {RwaSwapInputConduit2} from "./RwaSwapInputConduit2.sol";

contract RwaSwapInputConduit2Test is Test, DSMath {
    address me;

    Vat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    TestToken usdx;
    DaiJoin daiJoin;
    Dai dai;

    AuthGemJoin5 joinA;
    DssPsm psm;
    uint256 tin;
    RwaSwapInputConduit2 inputConduit;
    address testUrn;

    bytes32 constant ilk = "USDX-A";

    uint256 constant USDX_DECIMALS = 6;
    uint256 constant USDX_BASE_UNIT = 10**USDX_DECIMALS;
    uint256 constant USDX_DAI_CONVERSION_FACTOR = 10**12;
    uint256 constant USDX_MINT_AMOUNT = 1000 * USDX_BASE_UNIT;
    // Debt Ceiling 10x the normalized minted amount
    uint256 constant PSM_LINE_WAD = 10 * USDX_MINT_AMOUNT * USDX_DAI_CONVERSION_FACTOR;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Push(address indexed to, uint256 wad);
    event File(bytes32 indexed what, address data);
    event Yank(address indexed token, address indexed usr, uint256 amt);

    function setUp() public {
        setUpMCDandPSM();

        testUrn = vm.addr(420);
        inputConduit = new RwaSwapInputConduit2(
            address(vat),
            address(dai),
            address(usdx),
            address(psm),
            address(testUrn)
        );
        tin = psm.tin();
    }

    function setUpMCDandPSM() internal {
        me = address(this);

        vat = new Vat();

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

    function testSetWardAndEmitRelyOnDeploy() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(address(this));

        RwaSwapInputConduit2 c = new RwaSwapInputConduit2(
            address(vat),
            address(dai),
            address(usdx),
            address(psm),
            address(testUrn)
        );

        assertEq(c.wards(address(this)), 1);
    }

    function testRevertInvalidConstructorArguments() public {
        vm.expectRevert("RwaSwapInputConduit2/invalid-to-address");
        new RwaSwapInputConduit2(address(vat), address(dai), address(usdx), address(psm), address(0));

        vm.expectRevert();
        new RwaSwapInputConduit2(address(vat), address(0), address(0), address(0), address(testUrn));

        vm.expectRevert("RwaSwapInputConduit2/wrong-dai-for-psm");
        new RwaSwapInputConduit2(address(vat), address(0), address(usdx), address(psm), address(testUrn));

        vm.expectRevert("RwaSwapInputConduit2/wrong-gem-for-psm");
        new RwaSwapInputConduit2(address(vat), address(dai), address(0), address(psm), address(testUrn));
    }

    function testGiveUnlimitedApprovalToPsmGemJoinOnDeploy() public {
        assertEq(usdx.allowance(address(inputConduit), address(joinA)), type(uint256).max);
    }

    function testRevertOnGemUnssuportedDecimals() public {
        TestToken testGem = new TestToken("USDX", 19);
        AuthGemJoin testJoin = new AuthGemJoin(address(vat), "TCOIN", address(testGem));
        DssPsm psmT = new DssPsm(address(testJoin), address(daiJoin), address(vow));

        vm.expectRevert("Math/sub-overflow");
        new RwaSwapInputConduit2(address(vat), address(dai), address(testGem), address(psmT), address(this));
    }

    function testRelyDeny() public {
        assertEq(inputConduit.wards(address(0)), 0);

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

    function testFileTo() public {
        address to = vm.addr(2);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("to"), to);

        inputConduit.file(bytes32("to"), to);

        assertEq(inputConduit.to(), to);
    }

    function testFilePsm() public {
        assertEq(address(inputConduit.psm()), address(psm));

        AuthGemJoin5 newJoin = new AuthGemJoin5(address(vat), ilk, address(usdx));
        DssPsm newPsm = new DssPsm(address(newJoin), address(daiJoin), address(vow));
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("psm"), address(newPsm));

        inputConduit.file(bytes32("psm"), address(newPsm));

        assertEq(address(inputConduit.psm()), address(newPsm));
        assertEq(usdx.allowance(address(inputConduit), address(psm.gemJoin())), 0);
        assertEq(usdx.allowance(address(inputConduit), address(newPsm.gemJoin())), type(uint256).max);
    }

    function testFileRecovery() public {
        address recovery = vm.addr(0x1337);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("recovery"), recovery);

        inputConduit.file(bytes32("recovery"), recovery);

        assertEq(inputConduit.recovery(), recovery);
    }

    function testRevertOnFilePsmWithWrongGemDaiAddresses() public {
        address newGem = address(new TestToken("GEM", 6));
        address joinNew = address(new AuthGemJoin5(address(vat), bytes32("GEM-A"), newGem));
        address newDai = address(new Dai(0));
        address newDaiJoin = address(new DaiJoin(address(vat), address(newDai)));

        address newPsm = address(new DssPsm(address(joinA), address(newDaiJoin), address(vow)));
        vm.expectRevert("RwaSwapInputConduit2/wrong-dai-for-psm");
        inputConduit.file(bytes32("psm"), newPsm);

        newPsm = address(new DssPsm(address(joinNew), address(daiJoin), address(vow)));
        vm.expectRevert("RwaSwapInputConduit2/wrong-gem-for-psm");
        inputConduit.file(bytes32("psm"), newPsm);
    }

    function testRevertOnFileUnrecognisedParam() public {
        vm.expectRevert("RwaSwapInputConduit2/unrecognised-param");
        inputConduit.file(bytes32("random"), address(0));
    }

    function testRevertOnUnauthorizedMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaSwapInputConduit2/not-authorized");
        inputConduit.rely(address(0));

        vm.expectRevert("RwaSwapInputConduit2/not-authorized");
        inputConduit.deny(address(0));

        vm.expectRevert("RwaSwapInputConduit2/not-authorized");
        inputConduit.yank(address(0), me, 0);
    }

    function testPush() public {
        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 * WAD);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(500 * USDX_BASE_UNIT));
    }

    function testFuzzPermissionlessPush(address sender) public {
        vm.assume(sender != me);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 * WAD);

        vm.prank(sender);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(500 * USDX_BASE_UNIT));
    }

    function testPushAfterChangingPsm() public {
        // Init new PSM
        AuthGemJoin5 join = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(join));
        DssPsm newPsm = new DssPsm(address(join), address(daiJoin), address(vow));
        join.rely(address(newPsm));
        join.deny(me);

        // Change PSM
        inputConduit.file("psm", address(newPsm));

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(join)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 * WAD);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(join)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(500 * USDX_BASE_UNIT));
    }

    function testPushAmountWhenHaveSomeDaiBalanceGetExactAmount() public {
        dai.mint(address(inputConduit), 100 * WAD);
        assertEq(dai.balanceOf(address(inputConduit)), 100 * WAD);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 * WAD);
        inputConduit.push(500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(500 * USDX_BASE_UNIT));
        assertEq(dai.balanceOf(address(inputConduit)), 100 * WAD);
    }

    function testPushAmountWhenHaveSomeDaiBalanceGetAll() public {
        dai.mint(address(inputConduit), 100 * WAD);
        assertEq(dai.balanceOf(address(inputConduit)), 100 * WAD);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 * WAD);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(500 * USDX_BASE_UNIT));
        assertEq(dai.balanceOf(address(inputConduit)), 100 * WAD);
    }

    function testPushAmountFuzz(uint256 amt, uint256 wad) public {
        wad = bound(wad, 1 * WAD, type(uint256).max);
        deal(address(dai), testUrn, wad);

        uint256 usdxBalanceBefore = usdx.balanceOf(me);
        usdx.transfer(address(inputConduit), usdxBalanceBefore);
        assertEq(usdx.balanceOf(me), 0);

        uint256 usdxCBalanceBefore = usdx.balanceOf(address(inputConduit));
        uint256 urnDaiBalanceBefore = dai.balanceOf(address(testUrn));

        amt = bound(amt, 1 * USDX_BASE_UNIT, usdxCBalanceBefore);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), amt * USDX_DAI_CONVERSION_FACTOR);
        inputConduit.push(amt);

        assertEq(usdx.balanceOf(address(inputConduit)), usdxCBalanceBefore - amt);
        assertEq(dai.balanceOf(testUrn), urnDaiBalanceBefore + gemToDai(amt));
    }

    function testRevertOnPushAmountMoreThenGemBalance() public {
        assertEq(usdx.balanceOf(address(inputConduit)), 0);

        vm.expectRevert("ds-token-insufficient-balance");
        inputConduit.push(1);
    }

    function testRevertOnSwapAboveLine() public {
        // Mint beyond the debt ceiling for the PSM
        uint256 newlyMinted = PSM_LINE_WAD / USDX_DAI_CONVERSION_FACTOR;
        usdx.mint(newlyMinted);
        uint256 usdxMintedTotal = USDX_MINT_AMOUNT + newlyMinted;

        assertGt(usdxMintedTotal * USDX_DAI_CONVERSION_FACTOR, PSM_LINE_WAD);
        assertEq(usdx.balanceOf(me), usdxMintedTotal);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), usdxMintedTotal);

        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(inputConduit)), usdxMintedTotal);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectRevert("Vat/ceiling-exceeded");
        inputConduit.push();

        assertEq(usdx.balanceOf(address(inputConduit)), usdxMintedTotal);
        assertEq(dai.balanceOf(testUrn), 0);
    }

    function testRevertOnPushWhenToAddressNotSet() public {
        inputConduit.file("to", address(0));

        assertEq(inputConduit.to(), address(0));

        vm.expectRevert("RwaSwapInputConduit2/invalid-to-address");
        inputConduit.push();
    }

    function testRequiredGemAmtFuzz(uint256 wad) public {
        psm.file("tin", (1 * WAD) / 100); // add 1% fee

        uint256 myGemBlance = usdx.balanceOf(me);
        wad = bound(wad, 1 * WAD, inputConduit.expectedDaiWad(myGemBlance));

        uint256 amt = inputConduit.requiredGemAmt(wad);
        usdx.transfer(address(inputConduit), amt);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), amt * USDX_DAI_CONVERSION_FACTOR);
        inputConduit.push(amt);

        assertApproxEqAbs(dai.balanceOf(address(testUrn)), wad, USDX_DAI_CONVERSION_FACTOR);
    }

    function testExpectedDaiWadFuzz(uint256 amt) public {
        psm.file("tin", (1 * WAD) / 100); // add 1% fee

        uint256 myGemBlance = usdx.balanceOf(me);
        amt = bound(amt, 10 * USDX_BASE_UNIT, myGemBlance);

        uint256 expectedWad = inputConduit.expectedDaiWad(amt);
        usdx.transfer(address(inputConduit), amt);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), expectedWad);
        inputConduit.push(amt);

        assertApproxEqAbs(dai.balanceOf(address(testUrn)), expectedWad, USDX_DAI_CONVERSION_FACTOR);
    }

    function testYank() public {
        uint256 wad = 100 * WAD;

        dai.mint(address(me), wad);
        dai.transfer(address(inputConduit), wad);
        uint256 daiBalance = dai.balanceOf(me);

        assertEq(dai.balanceOf(address(inputConduit)), wad);

        vm.expectEmit(true, true, false, false);
        emit Yank(address(dai), address(me), wad);

        inputConduit.yank(address(dai), me, dai.balanceOf(address(inputConduit)));
        assertEq(dai.balanceOf(me), daiBalance + wad);
        assertEq(dai.balanceOf(address(inputConduit)), 0);
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    function testRevertDisableMethodsAfterEmergencyShutdown() public {
        vat.cage();

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.file("to", address(1));

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.file("recovery", address(1));

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.file("psm", address(1));

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.push();

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.push(1);

        vm.expectRevert("RwaSwapInputConduit2/vat-not-live");
        inputConduit.yank(address(usdx), address(this), 1);
    }

    function testApproveRecoveryAfterEmergencyShutdown() public {
        address recovery = address(0x1337);
        inputConduit.file("recovery", recovery);

        vat.cage();

        assertEq(usdx.allowance(address(inputConduit), recovery), 0, "Pre-condition failed: allowance is not zero");

        inputConduit.approveRecovery();

        assertEq(
            usdx.allowance(address(inputConduit), recovery),
            type(uint256).max,
            "Post-condition failed: allowance is not unlimited"
        );
    }

    function testReverApproveRecoveryIfAddressWasNotSet() public {
        vat.cage();

        vm.expectRevert("RwaSwapInputConduit2/recovery-not-set");
        inputConduit.approveRecovery();
    }

    function gemToDai(uint256 gemAmt) internal view returns (uint256) {
        uint256 gemAmt18 = mul(gemAmt, USDX_DAI_CONVERSION_FACTOR);
        uint256 fee = mul(gemAmt18, tin) / WAD;
        return sub(gemAmt18, fee);
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
