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
import "dss-interfaces/Interfaces.sol";

import {DssPsm} from "dss-psm/psm.sol";

import {RwaSwapInputConduit2} from "./RwaSwapInputConduit2.sol";

abstract contract RwaConduits4TestAbstract is Test, DSMath {
    // Define both in constructor of derived contract
    bytes32 ILK;
    address psm;

    address me = address(this);
    address testUrn = vm.addr(420);

    ChainlogAbstract changelog = ChainlogAbstract(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    VatAbstract vat = VatAbstract(changelog.getAddress("MCD_VAT"));

    DaiAbstract dai;
    GemAbstract gem;

    uint256 GEM_DECIMALS;
    uint256 GEM_DAI_DIFF_DECIMALS;
    uint256 MAX_GEM_SELL;
    uint256 URN_INK;

    uint256 PSM_TIN;
    uint256 PSM_TOUT;

    RwaSwapInputConduit2 inputConduit;

    function setUp() public virtual {
        dai = DaiAbstract(DssPsm(psm).dai());
        gem = GemAbstract(AuthGemJoinAbstract(address(DssPsm(psm).gemJoin())).gem());

        (uint256 art, , , uint256 line, ) = vat.ilks(ILK);
        GEM_DECIMALS = 10**uint256(gem.decimals());
        GEM_DAI_DIFF_DECIMALS = 10**uint256(dai.decimals() - gem.decimals());
        MAX_GEM_SELL = (wad(line) - art) / GEM_DAI_DIFF_DECIMALS;
        (uint256 ink, ) = vat.urns(ILK, psm);
        URN_INK = ink;

        PSM_TIN = DssPsm(psm).tin();
        PSM_TOUT = DssPsm(psm).tout();

        deal(address(dai), me, 2 * URN_INK);

        inputConduit = new RwaSwapInputConduit2(address(dai), address(gem), psm, testUrn);
    }

    /*//////////////////////////////////
               Input Conduit Tests
    //////////////////////////////////*/

    function testInputConduitPush() public {
        uint256 gemAmount = MAX_GEM_SELL;

        assertEq(gem.balanceOf(address(inputConduit)), 0);

        gem.transfer(address(inputConduit), gemAmount);

        assertEq(gem.balanceOf(address(inputConduit)), gemAmount);
        assertEq(dai.balanceOf(testUrn), 0);

        inputConduit.push();

        assertEq(gem.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), gemToDai(gemAmount));
    }

    function testInputConduitPushAmountFuzz(uint256 amt, uint256 urnBalance) public {
        urnBalance = bound(urnBalance, 1 * WAD, 1_000_000 * WAD);
        deal(address(dai), address(testUrn), urnBalance);
        uint256 gemAmount = MAX_GEM_SELL;

        gem.transfer(address(inputConduit), gemAmount);

        uint256 gemCBalanceBefore = gem.balanceOf(address(inputConduit));
        uint256 urnDaiBalanceBefore = dai.balanceOf(address(testUrn));

        amt = bound(amt, 1 * GEM_DECIMALS, gemCBalanceBefore);

        inputConduit.push(amt);

        assertEq(gem.balanceOf(address(inputConduit)), gemCBalanceBefore - amt);
        assertEq(dai.balanceOf(testUrn), urnDaiBalanceBefore + gemToDai(amt));
    }

    function testRevertInputConduitOnSwapAboveLine() public {
        uint256 gemAmount = MAX_GEM_SELL + 1; // more then MAX

        assertEq(gem.balanceOf(address(inputConduit)), 0);

        gem.transfer(address(inputConduit), gemAmount);

        assertEq(gem.balanceOf(address(inputConduit)), gemAmount);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectRevert("Vat/ceiling-exceeded");
        inputConduit.push();

        assertEq(gem.balanceOf(address(inputConduit)), gemAmount);
        assertEq(dai.balanceOf(testUrn), 0);
    }

    /*//////////////////////////////////
               Outnput Conduit Tests
    //////////////////////////////////*/

    function wad(uint256 rad_) internal pure returns (uint256) {
        return rad_ / 10**27;
    }

    function getDaiInAmount(uint256 gemAmt) internal view returns (uint256) {
        uint256 gemAmt18 = mul(gemAmt, GEM_DAI_DIFF_DECIMALS);
        uint256 fee = mul(gemAmt18, PSM_TOUT) / WAD;
        return add(gemAmt18, fee);
    }

    function gemToDai(uint256 gemAmt) internal view returns (uint256) {
        uint256 gemAmt18 = mul(gemAmt, GEM_DAI_DIFF_DECIMALS);
        uint256 fee = mul(gemAmt18, PSM_TIN) / WAD;
        return sub(gemAmt18, fee);
    }
}

contract RwaConduits4PsmUsdcIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-USDC-A");
        psm = changelog.getAddress("MCD_PSM_USDC_A");
    }

    function setUp() public override {
        super.setUp();
        deal(address(gem), me, 2 * MAX_GEM_SELL);
    }
}

contract RwaConduits4PsmPaxIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-PAX-A");
        psm = changelog.getAddress("MCD_PSM_PAX_A");
    }

    function setUp() public override {
        // We set DC manually as DC is currently 0
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        vat.file(ILK, "line", 500_000_000 * (10**45));

        vm.stopPrank();

        super.setUp();
        deal(address(gem), me, 2 * MAX_GEM_SELL);
    }
}

contract RwaConduits4PsmGUSDIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-GUSD-A");
        psm = changelog.getAddress("MCD_PSM_GUSD_A");
    }

    function setUp() public override {
        // We set DC manually as DC is currently maxed
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        vat.file(ILK, "line", 700_000_000 * (10**45));

        vm.stopPrank();

        super.setUp();

        // Add GUSD blance
        address impl = ERC20Proxy(address(gem)).erc20Impl();
        ERC20Store store = ERC20Store(ERC20Impl(impl).erc20Store());

        vm.startPrank(impl);

        store.setBalance(me, 2 * MAX_GEM_SELL);
        store.setTotalSupply(gem.totalSupply() + 2 * MAX_GEM_SELL);

        vm.stopPrank();

        assertEq(gem.balanceOf(me), 2 * MAX_GEM_SELL);
    }
}

contract RwaConduits4PsmGUSDWith5PercentFeeIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-GUSD-A");
        psm = changelog.getAddress("MCD_PSM_GUSD_A");
    }

    function setUp() public override {
        // We set DC manually as DC is currently maxed
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        vat.file(ILK, "line", 700_000_000 * (10**45));

        vm.stopPrank();

        super.setUp();

        // Add GUSD blance
        address impl = ERC20Proxy(address(gem)).erc20Impl();
        ERC20Store store = ERC20Store(ERC20Impl(impl).erc20Store());

        vm.startPrank(impl);

        store.setBalance(me, 2 * MAX_GEM_SELL);
        store.setTotalSupply(gem.totalSupply() + 2 * MAX_GEM_SELL);

        vm.stopPrank();

        assertEq(gem.balanceOf(me), 2 * MAX_GEM_SELL);

        // Adjust tin/tour for PSM
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        uint256 fee = (5 * WAD) / 100;
        DssPsm(psm).file("tin", fee);
        DssPsm(psm).file("tout", fee);

        assertEq(DssPsm(psm).tin(), fee);
        assertEq(DssPsm(psm).tout(), fee);

        vm.stopPrank();

        PSM_TIN = DssPsm(psm).tin();
        PSM_TOUT = DssPsm(psm).tout();
    }
}

contract RwaConduits4PsmUSDCWith5PercentFeeIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-USDC-A");
        psm = changelog.getAddress("MCD_PSM_USDC_A");
    }

    function setUp() public override {
        super.setUp();

        deal(address(gem), me, 2 * MAX_GEM_SELL);

        // Adjust tin/tour for PSM
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        uint256 fee = (5 * WAD) / 100;
        DssPsm(psm).file("tin", fee);
        DssPsm(psm).file("tout", fee);

        assertEq(DssPsm(psm).tin(), fee);
        assertEq(DssPsm(psm).tout(), fee);

        vm.stopPrank();

        PSM_TIN = DssPsm(psm).tin();
        PSM_TOUT = DssPsm(psm).tout();
    }
}

contract RwaConduits4PsmPAXWith5PercentFeeIntegrationTest is RwaConduits4TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-PAX-A");
        psm = changelog.getAddress("MCD_PSM_PAX_A");
    }

    function setUp() public override {
        // We set DC manually as DC is currently 0
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        vat.file(ILK, "line", 500_000_000 * (10**45));

        vm.stopPrank();

        super.setUp();

        deal(address(gem), me, 2 * MAX_GEM_SELL);

        // Adjust tin/tour for PSM
        vm.startPrank(changelog.getAddress("MCD_PAUSE_PROXY"));

        uint256 fee = (5 * WAD) / 100;
        DssPsm(psm).file("tin", fee);
        DssPsm(psm).file("tout", fee);

        assertEq(DssPsm(psm).tin(), fee);
        assertEq(DssPsm(psm).tout(), fee);

        vm.stopPrank();

        PSM_TIN = DssPsm(psm).tin();
        PSM_TOUT = DssPsm(psm).tout();
    }
}

interface ERC20Proxy {
    function erc20Impl() external returns (address);

    function totalSupply() external returns (uint256);
}

interface ERC20Impl {
    function erc20Store() external returns (address);
}

interface ERC20Store {
    function setTotalSupply(uint256 _newTotalSupply) external;

    function setBalance(address _owner, uint256 _newBalance) external;
}
