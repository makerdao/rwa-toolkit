// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
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
import "dss-interfaces/Interfaces.sol";

import {DssPsm} from "dss-psm/psm.sol";

import {RwaInputConduit3} from "./RwaInputConduit3.sol";
import {RwaOutputConduit3} from "../conduits/RwaOutputConduit3.sol";

abstract contract RwaConduits3TestAbstract is Test, DSMath {
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
    uint256 ART_LEFT;

    RwaInputConduit3 inputConduit;
    RwaOutputConduit3 outputConduit;

    function ray(uint256 wad) internal pure returns (uint256) {
        return wad * 10**9;
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * 10**27;
    }

    function wad(uint256 rad_) internal pure returns (uint256) {
        return rad_ / 10**27;
    }

    function setUp() public virtual {
        (uint256 art, , , uint256 line, ) = vat.ilks(ILK);
        dai = DaiAbstract(DssPsm(psm).dai());
        gem = GemAbstract(AuthGemJoinAbstract(address(DssPsm(psm).gemJoin())).gem());
        GEM_DECIMALS = 10**uint256(gem.decimals());
        GEM_DAI_DIFF_DECIMALS = 10**uint256(dai.decimals() - gem.decimals());
        ART_LEFT = (wad(line) - art) / GEM_DAI_DIFF_DECIMALS;

        inputConduit = new RwaInputConduit3(psm, testUrn);
        outputConduit = new RwaOutputConduit3(psm);

        inputConduit.mate(me);
        outputConduit.mate(me);

        outputConduit.kiss(me);
        outputConduit.pick(me);
    }

    function testInputConduitPush() public {
        uint256 gemAmount = ART_LEFT;

        assertEq(gem.balanceOf(address(inputConduit)), 0);

        gem.transfer(address(inputConduit), 500 * GEM_DECIMALS);

        assertEq(gem.balanceOf(address(inputConduit)), 500 * GEM_DECIMALS);
        assertEq(dai.balanceOf(testUrn), 0);

        inputConduit.push();

        assertEq(gem.balanceOf(address(inputConduit)), 0);
        assertEq(dai.balanceOf(testUrn), 500 ether);
    }

    function testInputConduitPushAmountFuzz(uint256 amt) public {
        uint256 gemAmount = ART_LEFT;

        gem.transfer(address(inputConduit), gemAmount);

        uint256 gemCBalanceBefore = gem.balanceOf(address(inputConduit));
        uint256 urnGemBalanceBefore = gem.balanceOf(address(testUrn));

        amt = bound(amt, 1 * GEM_DECIMALS, gemCBalanceBefore);

        inputConduit.push(amt);

        assertEq(gem.balanceOf(address(inputConduit)), gemCBalanceBefore - amt);
        assertEq(dai.balanceOf(testUrn), urnGemBalanceBefore + amt * GEM_DAI_DIFF_DECIMALS);
    }

    function testRevertInputConduitOnSwapAboveLine() public {
        uint256 gemAmount = ART_LEFT + 1; // 1 more then available

        assertEq(gem.balanceOf(address(inputConduit)), 0);

        gem.transfer(address(inputConduit), gemAmount);

        assertEq(gem.balanceOf(address(inputConduit)), gemAmount);

        assertEq(dai.balanceOf(testUrn), 0);

        vm.expectRevert("Vat/ceiling-exceeded");
        inputConduit.push();

        assertEq(gem.balanceOf(address(inputConduit)), gemAmount);
        assertEq(dai.balanceOf(testUrn), 0);
    }
}

contract RwaConduits3PsmUsdcIntegrationTest is RwaConduits3TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-USDC-A");
        psm = changelog.getAddress("MCD_PSM_USDC_A");
    }

    function setUp() public override {
        super.setUp();
        deal(address(gem), me, 2 * ART_LEFT);
    }
}

contract RwaConduits3PsmPaxIntegrationTest is RwaConduits3TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-PAX-A");
        psm = changelog.getAddress("MCD_PSM_PAX_A");
    }

    function setUp() public override {
        super.setUp();
        deal(address(gem), me, 2 * ART_LEFT);
    }
}

contract RwaConduits3PsmGUSDIntegrationTest is RwaConduits3TestAbstract {
    constructor() public {
        ILK = bytes32("PSM-GUSD-A");
        psm = changelog.getAddress("MCD_PSM_GUSD_A");
    }

    function setUp() public override {
        super.setUp();
        address impl = ERC20Proxy(address(gem)).erc20Impl();
        ERC20Store store = ERC20Store(ERC20Impl(impl).erc20Store());

        vm.startPrank(impl);

        store.setBalance(me, 2 * ART_LEFT);
        store.setTotalSupply(gem.totalSupply() + 2 * ART_LEFT);

        vm.stopPrank();

        assertEq(gem.balanceOf(me), 2 * ART_LEFT);
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
