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

import {RwaMultiSwapOutputConduit} from "../conduits/RwaMultiSwapOutputConduit.sol";

abstract contract RwaMultiSwapOutputConduitsTestAbstract is Test, DSMath {
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

    RwaMultiSwapOutputConduit outputConduit;

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

        outputConduit = new RwaMultiSwapOutputConduit(address(dai));

        outputConduit.mate(me);
        outputConduit.hope(me);

        outputConduit.clap(address(psm));
        outputConduit.hook(address(psm));

        outputConduit.kiss(me);
        outputConduit.pick(me);
    }

    /*//////////////////////////////////
               Outnput Conduit Tests
    //////////////////////////////////*/

    function testOutputConduitPush() public {
        assertEq(outputConduit.to(), me);
        uint256 daiAmount = URN_INK;

        uint256 gemBalanceBefore = gem.balanceOf(me);
        dai.transfer(address(outputConduit), daiAmount);

        outputConduit.push();

        outputConduit.hook(address(psm));
        assertEq(gem.balanceOf(address(me)), gemBalanceBefore + outputConduit.expectedGemAmt(daiAmount));
        // We lose some dust because of decimals diff dai.decimals() > gem.decimals()
        assertApproxEqAbs(dai.balanceOf(address(outputConduit)), 0, GEM_DAI_DIFF_DECIMALS);
        assertEq(outputConduit.to(), address(0));
    }

    function testOutputConduitPushAmountFuzz(uint256 wadAmt) public {
        assertEq(outputConduit.to(), me);

        dai.transfer(address(outputConduit), getDaiInAmount(URN_INK / GEM_DAI_DIFF_DECIMALS));
        uint256 cDaiBalance = dai.balanceOf(address(outputConduit));
        uint256 gemBalance = gem.balanceOf(me);

        wadAmt = bound(wadAmt, 10**18, cDaiBalance);

        outputConduit.push(wadAmt);

        outputConduit.hook(address(psm));
        assertEq(gem.balanceOf(me), gemBalance + outputConduit.expectedGemAmt(wadAmt));
        // We lose some dust because of decimals diif dai.decimals() > gem.decimals()
        assertApproxEqAbs(
            dai.balanceOf(address(outputConduit)),
            cDaiBalance - getDaiInAmount(outputConduit.expectedGemAmt(wadAmt)),
            GEM_DAI_DIFF_DECIMALS
        );
        assertEq(outputConduit.to(), address(0));
    }

    function testRevertOutputConduitOnInsufficientGemAmountInPsm() public {
        uint256 daiAmount = getDaiInAmount(URN_INK / GEM_DAI_DIFF_DECIMALS + 1 * GEM_DECIMALS); // more then INK

        assertEq(gem.balanceOf(address(outputConduit)), 0);

        dai.transfer(address(outputConduit), daiAmount);

        assertEq(dai.balanceOf(address(outputConduit)), daiAmount);

        vm.expectRevert();
        // It will revert on vat.frob()
        // urn.ink = _add(urn.ink, dink); // _add method will revert with empty message because ink < dink
        outputConduit.push();

        assertEq(dai.balanceOf(address(outputConduit)), daiAmount);
    }

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

contract RwaMultiSwapOutputConduitPsmUsdcIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
    constructor() public {
        ILK = bytes32("PSM-USDC-A");
        psm = changelog.getAddress("MCD_PSM_USDC_A");
    }

    function setUp() public override {
        super.setUp();
        deal(address(gem), me, 2 * MAX_GEM_SELL);
    }
}

contract RwaMultiSwapOutputConduitPsmPaxIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
    constructor() public {
        ILK = bytes32("PSM-PAX-A");
        psm = changelog.getAddress("MCD_PSM_PAX_A");
    }

    function setUp() public override {
        super.setUp();
        deal(address(gem), me, 2 * MAX_GEM_SELL);
    }
}

contract RwaMultiSwapOutputConduitPsmGUSDIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
    constructor() public {
        ILK = bytes32("PSM-GUSD-A");
        psm = changelog.getAddress("MCD_PSM_GUSD_A");
    }

    function setUp() public override {
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

contract RwaMultiSwapOutputConduitPsmGUSDWith5PercentFeeIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
    constructor() public {
        ILK = bytes32("PSM-GUSD-A");
        psm = changelog.getAddress("MCD_PSM_GUSD_A");
    }

    function setUp() public override {
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

contract RwaMultiSwapOutputConduitPsmUSDCWith5PercentFeeIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
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

contract RwaMultiSwapOutputConduitPsmPAXWith5PercentFeeIntegrationTest is RwaMultiSwapOutputConduitsTestAbstract {
    constructor() public {
        ILK = bytes32("PSM-PAX-A");
        psm = changelog.getAddress("MCD_PSM_PAX_A");
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
