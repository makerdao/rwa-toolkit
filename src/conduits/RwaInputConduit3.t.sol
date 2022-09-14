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

import {RwaInputConduit3} from "./RwaInputConduit3.sol";
// import {RwaOutputConduit} from "../conduits/RwaOutputConduit3.sol";

import {DssPsm} from "dss-psm/psm.sol";
import {AuthGemJoin5} from "dss-psm/join-5-auth.sol";
import {AuthGemJoin} from "dss-psm/join-auth.sol";

contract RwaInputConduit3Test is Test, DSMath {
    address me;

    Vat vat;
    Spotter spot;
    TestVow vow;
    DSValue pip;
    TestToken usdx;
    DaiJoin daiJoin;
    Dai dai;

    AuthGemJoin5 joinA;
    DssPsm psmA;
    RwaInputConduit3 inputConduit;
    TestUrn testUrn;

    bytes32 constant ilk = "usdx";

    uint256 constant USDX_BASE_UNIT = 10**6;
    uint256 constant USDX_DAI_DIF_DECIMALS = 10**12;
    uint256 constant USDX_MINT_AMOUNT = 1000 * USDX_BASE_UNIT;
    uint256 constant PSM_LINE = 1000 * 10**18;
    uint256 PSM_TIN;

    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event Mate(address indexed usr);
    event Hate(address indexed usr);
    event Push(address indexed to, uint256 wad);
    event File(bytes32 indexed what, address data);
    event Quit(address indexed quitTo, uint256 wad);
    event Yank(address indexed usr, uint256 gemAmt);

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10**9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10**27;
    }

    function gemToDai(uint256 gemAmt) internal view returns (uint256) {
        uint256 gemAmt18 = mul(gemAmt, USDX_DAI_DIF_DECIMALS);
        uint256 fee = mul(gemAmt18, PSM_TIN) / WAD;
        return sub(gemAmt18, fee);
    }

    function setUpMCDandPSM() internal {
        me = address(this);

        vat = new Vat();

        spot = new Spotter(address(vat));
        vat.rely(address(spot));

        vow = new TestVow(address(vat), address(0), address(0));

        usdx = new TestToken("USDX", 6);
        usdx.mint(USDX_MINT_AMOUNT);

        vat.init(ilk);

        joinA = new AuthGemJoin5(address(vat), ilk, address(usdx));
        vat.rely(address(joinA));

        dai = new Dai(0);
        daiJoin = new DaiJoin(address(vat), address(dai));
        vat.rely(address(daiJoin));
        dai.rely(address(daiJoin));

        psmA = new DssPsm(address(joinA), address(daiJoin), address(vow));
        joinA.rely(address(psmA));
        joinA.deny(me);

        pip = new DSValue();
        pip.poke(bytes32(uint256(1 ether))); // Spot = $1

        spot.file(ilk, bytes32("pip"), address(pip));
        spot.file(ilk, bytes32("mat"), ray(1 ether));
        spot.poke(ilk);

        vat.file(ilk, "line", rad(PSM_LINE));
        vat.file("Line", rad(PSM_LINE));
    }

    function setUp() public {
        setUpMCDandPSM();

        testUrn = new TestUrn();
        inputConduit = new RwaInputConduit3(address(psmA), address(testUrn));
        inputConduit.file("quitTo", address(this));
        inputConduit.mate(me);
        PSM_TIN = psmA.tin();
    }

    function testSetWardAndEmitRelyOnDeploy() public {
        vm.expectEmit(true, false, false, false);
        emit Rely(address(this));

        RwaInputConduit3 c = new RwaInputConduit3(address(psmA), address(testUrn));

        assertEq(c.wards(address(this)), 1);
    }

    function testRevertOnDeployWithZeroToAddress() public {
        vm.expectRevert("RwaInputConduit3/invalid-to-address");
        new RwaInputConduit3(address(psmA), address(0));
    }

    function testGiveUnlimitedApprovalToPsmGemJoinOnDeploy() public {
        assertEq(usdx.allowance(address(inputConduit), address(joinA)), type(uint256).max);
    }

    function testRevertOnGemUnssuportedDecimals() public {
        TestToken testGem = new TestToken("USDX", 19);
        AuthGemJoin testJoin = new AuthGemJoin(address(vat), "TCOIN", address(testGem));
        DssPsm psm = new DssPsm(address(testJoin), address(daiJoin), address(vow));

        vm.expectRevert("Math/sub-overflow");
        new RwaInputConduit3(address(psm), address(this));
    }

    function testRelyDeny() public {
        assertEq(inputConduit.wards(address(0)), 0);

        vm.expectEmit(true, false, false, false);
        emit Rely(address(0));

        inputConduit.rely(address(0));

        assertEq(inputConduit.wards(address(0)), 1);

        vm.expectEmit(true, false, false, false);
        emit Deny(address(0));

        inputConduit.deny(address(0));

        assertEq(inputConduit.wards(address(0)), 0);
    }

    function testMateHate() public {
        assertEq(inputConduit.may(address(0)), 0);

        vm.expectEmit(true, false, false, false);
        emit Mate(address(0));

        inputConduit.mate(address(0));

        assertEq(inputConduit.may(address(0)), 1);

        vm.expectEmit(true, false, false, false);
        emit Hate(address(0));

        inputConduit.hate(address(0));

        assertEq(inputConduit.may(address(0)), 0);
    }

    function testFile() public {
        assertEq(inputConduit.quitTo(), address(this));

        address quitToAddress = vm.addr(1);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("quitTo"), quitToAddress);

        inputConduit.file(bytes32("quitTo"), quitToAddress);

        assertEq(inputConduit.quitTo(), quitToAddress);

        address to = vm.addr(2);
        vm.expectEmit(true, true, false, false);
        emit File(bytes32("to"), to);

        inputConduit.file(bytes32("to"), to);

        assertEq(inputConduit.to(), to);
    }

    function testRevertOnFileUnrecognisedParam() public {
        vm.expectRevert("RwaInputConduit3/unrecognised-param");
        inputConduit.file(bytes32("random"), address(0));
    }

    function testRevertOnUnauthorizedMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.rely(address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.deny(address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.hate(address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.mate(address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.file(bytes32("quitTo"), address(0));

        vm.expectRevert("RwaInputConduit3/not-authorized");
        inputConduit.yank(address(0));
    }

    function testRevertOnNotMateMethods() public {
        vm.startPrank(address(0));

        vm.expectRevert("RwaInputConduit3/not-mate");
        inputConduit.push();

        vm.expectRevert("RwaInputConduit3/not-mate");
        inputConduit.quit();
    }

    function testPush() public {
        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(testUrn.balance(address(dai)), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 ether);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(testUrn.balance(address(dai)), gemToDai(500 * USDX_BASE_UNIT));
    }

    function testPushAmountWhenHaveSomeDaiBalanceGetExactAmount() public {
        dai.mint(address(inputConduit), 100 ether);
        assertEq(dai.balanceOf(address(inputConduit)), 100 ether);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(testUrn.balance(address(dai)), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 ether);
        inputConduit.push(500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(testUrn.balance(address(dai)), gemToDai(500 * USDX_BASE_UNIT));
        assertEq(dai.balanceOf(address(inputConduit)), 100 ether);
    }

    function testPushAmountWhenHaveSomeDaiBalanceGetAll() public {
        dai.mint(address(inputConduit), 100 ether);
        assertEq(dai.balanceOf(address(inputConduit)), 100 ether);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), 500 * USDX_BASE_UNIT);

        assertEq(usdx.balanceOf(me), USDX_MINT_AMOUNT - 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 500 * USDX_BASE_UNIT);

        assertEq(testUrn.balance(address(dai)), 0);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), 500 ether);
        inputConduit.push();

        assertEq(usdx.balanceOf(address(joinA)), 500 * USDX_BASE_UNIT);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(testUrn.balance(address(dai)), gemToDai(500 * USDX_BASE_UNIT));
        assertEq(dai.balanceOf(address(inputConduit)), 100 ether);
    }

    function testPushAmountFuzz(uint256 amt) public {
        uint256 usdxBalanceBefore = usdx.balanceOf(me);
        usdx.transfer(address(inputConduit), usdxBalanceBefore);
        assertEq(usdx.balanceOf(me), 0);

        uint256 usdxCBalanceBefore = usdx.balanceOf(address(inputConduit));
        uint256 urnUsdxBalanceBefore = usdx.balanceOf(address(testUrn));

        amt = bound(amt, 1 * USDX_BASE_UNIT, usdxCBalanceBefore);

        vm.expectEmit(true, true, false, false);
        emit Push(address(testUrn), amt * USDX_DAI_DIF_DECIMALS);
        inputConduit.push(amt);

        assertEq(usdx.balanceOf(address(inputConduit)), usdxCBalanceBefore - amt);
        assertEq(testUrn.balance(address(dai)), urnUsdxBalanceBefore + gemToDai(amt));
    }

    function testRevertOnPushAmountMoreThenGemBalance() public {
        assertEq(usdx.balanceOf(address(inputConduit)), 0);

        vm.expectRevert("ds-token-insufficient-balance");
        inputConduit.push(1);
    }

    function testRevertOnSwapAboveLine() public {
        usdx.mint(100 * USDX_BASE_UNIT);
        uint256 usdxMintedTotal = USDX_MINT_AMOUNT + 100 * USDX_BASE_UNIT;

        assertGt(usdxMintedTotal * USDX_DAI_DIF_DECIMALS, PSM_LINE);
        assertEq(usdx.balanceOf(me), usdxMintedTotal);
        assertEq(usdx.balanceOf(address(inputConduit)), 0);
        assertEq(usdx.balanceOf(address(joinA)), 0);

        usdx.transfer(address(inputConduit), usdxMintedTotal);

        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(inputConduit)), usdxMintedTotal);

        assertEq(testUrn.balance(address(dai)), 0);

        vm.expectRevert("Vat/ceiling-exceeded");
        inputConduit.push();

        assertEq(usdx.balanceOf(address(inputConduit)), usdxMintedTotal);
        assertEq(testUrn.balance(address(dai)), 0);
    }

    function testQuit() public {
        usdx.transfer(address(inputConduit), USDX_MINT_AMOUNT);

        assertEq(inputConduit.quitTo(), me);
        assertEq(usdx.balanceOf(me), 0);
        assertEq(usdx.balanceOf(address(inputConduit)), USDX_MINT_AMOUNT);

        vm.expectEmit(true, true, false, false);
        emit Quit(inputConduit.quitTo(), USDX_MINT_AMOUNT);
        inputConduit.quit();

        assertEq(usdx.balanceOf(inputConduit.quitTo()), USDX_MINT_AMOUNT);
    }

    function testQuitAmountFuzz(uint256 amt) public {
        assertEq(inputConduit.quitTo(), me);
        uint256 usdxBalance = usdx.balanceOf(me);
        usdx.transfer(address(inputConduit), usdxBalance);
        uint256 usdxCBalance = usdx.balanceOf(address(inputConduit));
        assertEq(usdx.balanceOf(me), 0);

        amt = bound(amt, 1 * USDX_BASE_UNIT, usdxCBalance);

        vm.expectEmit(true, true, false, false);
        emit Quit(inputConduit.quitTo(), amt);
        inputConduit.quit(amt);

        assertEq(usdx.balanceOf(inputConduit.quitTo()), amt);
        assertEq(usdx.balanceOf(address(inputConduit)), usdxCBalance - amt);
    }

    function testRevertOnQuitAmountMoreThenGemBalance() public {
        assertEq(usdx.balanceOf(address(inputConduit)), 0);

        vm.expectRevert("ds-token-insufficient-balance");
        inputConduit.quit(1);
    }

    function testRevertOnPushWhenToAddressNotSet() public {
        RwaInputConduit3 c = new RwaInputConduit3(address(psmA), address(testUrn));
        c.mate(me);
        c.file("to", address(0));

        assertEq(c.to(), address(0));

        vm.expectRevert("RwaInputConduit3/invalid-to-address");
        c.push();
    }

    function testRevertOnQuitWhenQuitToAddressNotSet() public {
        RwaInputConduit3 c = new RwaInputConduit3(address(psmA), address(testUrn));
        c.mate(me);

        assertEq(c.quitTo(), address(0));

        vm.expectRevert("RwaInputConduit3/invalid-quit-to-address");
        c.quit();
    }

    function testYank() public {
        uint256 wad = 100 ether;

        dai.mint(address(me), wad);
        dai.transfer(address(inputConduit), wad);
        uint256 daiBalance = dai.balanceOf(me);

        assertEq(dai.balanceOf(address(inputConduit)), wad);

        vm.expectEmit(true, true, false, false);
        emit Yank(address(me), wad);

        inputConduit.yank(me);
        assertEq(dai.balanceOf(me), daiBalance + wad);
        assertEq(dai.balanceOf(address(inputConduit)), 0);
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

contract TestUrn {
    function balance(address gem) public view returns (uint256) {
        return DSToken(gem).balanceOf(address(this));
    }
}
