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
import {DaiJoin} from "dss/join.sol";
import {ChainLog} from "dss-chain-log/ChainLog.sol";

import {RwaJar} from "./RwaJar.sol";

interface Hevm {
    function store(
        address,
        bytes32,
        bytes32
    ) external;
}

contract RwaJarTest is DSTest, DSMath {
    bytes20 internal constant CHEAT_CODE = bytes20(uint160(uint256(keccak256("hevm cheat code"))));

    Hevm internal hevm;

    Vat internal vat;
    ChainLog internal chainlog;
    DaiJoin internal daiJoin;
    DSToken internal dai;
    address internal constant VOW = address(0x1337);

    RwaJar internal jar;

    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        chainlog = new ChainLog();
        vat = new Vat();
        dai = new DSToken("Dai");
        daiJoin = new DaiJoin(address(vat), address(dai));

        vat.rely(address(daiJoin));
        dai.setOwner(address(daiJoin));

        chainlog.setAddress("MCD_VOW", VOW);
        chainlog.setAddress("MCD_JOIN_DAI", address(daiJoin));

        jar = new RwaJar(address(chainlog));
    }

    function test_void_sends_all_dai_balance_to_the_vow(uint128 amount) public {
        // Make sure amount is not zero
        amount = (amount % (type(uint128).max - 1)) + 1;

        _createFakeDai(address(this), amount);
        dai.transfer(address(jar), amount);

        jar.void();

        assertEq(dai.balanceOf(address(jar)), 0, "Balance of RwaJar is not zero");
        assertEq(vat.dai(VOW), _rad(amount), "Vow internal balance not equals to the amount transfereed");
    }

    function testFail_void_when_dai_balance_is_zero() public {
        jar.void();
    }

    function test_toss_pulls_dai_from_sender_into_the_vow(uint128 amount) public {
        // Make sure amount is not zero
        amount = (amount % (type(uint128).max - 1)) + 1;

        _createFakeDai(address(this), amount);
        dai.approve(address(jar), amount);

        uint256 senderBalanceBefore = dai.balanceOf(address(this));
        uint256 vowBalanceBefore = vat.dai(VOW);

        jar.toss(amount);

        uint256 senderBalanceAfter = dai.balanceOf(address(this));
        uint256 vowBalanceAfter = vat.dai(VOW);

        assertEq(senderBalanceAfter, senderBalanceBefore - amount, "Balance of sender not reduced correctly");
        assertEq(vowBalanceAfter, vowBalanceBefore + _rad(amount), "Balance of vow not increased correctly");
    }

    function _createFakeDai(address usr, uint256 wad) private {
        // Set initial balance for `usr` in the vat
        hevm.store(address(vat), keccak256(abi.encode(usr, 5)), bytes32(_rad(wad)));
        // Authorizes daiJoin to operate on behalf of the user in the vat
        hevm.store(
            address(vat),
            keccak256(abi.encode(address(daiJoin), keccak256(abi.encode(usr, 1)))),
            bytes32(uint256(1))
        );
        // Converts the minted Dai into ERC-20 Dai and sends it to `usr`.
        daiJoin.exit(usr, wad);
    }

    function _rad(uint256 wad) internal pure returns (uint256) {
        return mul(wad, RAY);
    }
}
