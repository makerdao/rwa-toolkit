// SPDX-FileCopyrightText: © 2022 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RwaCageSettlementFactory.sol -- On-chain factory for RwaCageSettlement.
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

import {Test} from "forge-std/Test.sol";
import {DSToken} from "ds-token/token.sol";
import {DSMath} from "ds-math/math.sol";

import {Vat} from "dss/vat.sol";
import {Cat} from "dss/cat.sol";
import {Dog} from "dss/dog.sol";
import {Vow} from "dss/vow.sol";
import {Flapper} from "dss/flap.sol";
import {Flopper} from "dss/flop.sol";
import {Pot} from "dss/pot.sol";
import {Cure} from "dss/cure.sol";
import {Spotter} from "dss/spot.sol";
import {End} from "dss/end.sol";
import {Jug} from "dss/jug.sol";
import {DaiJoin} from "dss/join.sol";
import {IlkRegistry} from "ilk-registry/IlkRegistry.sol";
import {AuthGemJoin} from "dss-gem-joins/join-auth.sol";

import {RwaTokenFactory} from "../tokens/RwaTokenFactory.sol";
import {RwaToken} from "../tokens/RwaToken.sol";
import {RwaUrn2} from "../urns/RwaUrn2.sol";
import {RwaLiquidationOracle} from "../oracles/RwaLiquidationOracle.sol";
import {RwaCageSettlement} from "./RwaCageSettlement.sol";
import {RwaCageSettlementFactory} from "./RwaCageSettlementFactory.sol";

contract RwaCageSettlementFactoryTest is Test, DSMath {
    bytes32 constant ILK = "RWA00X-A";
    uint256 constant CEILING = 200 * WAD;
    uint256 immutable price = wmul(CEILING, 1.1 ether);
    uint256 constant EIGHT_PCT = 1000000002440418608258400030;
    string constant DOC = "Please sign this";
    uint96 constant ILK_CLASS_RWA = 3;
    uint48 constant TAU = 2 weeks;

    mapping(bytes32 => IlkInfo) ilkToIlkInfo;

    DSToken dai = new DSToken("Dai");
    DSToken gov = new DSToken("Maker");

    Vat vat = new Vat();
    Cat cat = new Cat(address(vat));
    Dog dog = new Dog(address(vat));
    Flapper flap = new Flapper(address(vat), address(gov));
    Flopper flop = new Flopper(address(vat), address(gov));
    Vow vow = new Vow(address(vat), address(flap), address(flop));
    Pot pot = new Pot(address(vat));
    Cure cure = new Cure();
    Spotter spot = new Spotter(address(vat));
    End end = new End();
    Jug jug = new Jug(address(vat));

    DaiJoin daiJoin = new DaiJoin(address(vat), address(dai));

    RwaTokenFactory tokenFactory = new RwaTokenFactory();
    RwaLiquidationOracle oracle = new RwaLiquidationOracle(address(vat), address(vow));
    address constant OUTPUT_CONDUIT = address(0x2448);

    IlkRegistry registry;

    TestCoin coin = new TestCoin("USDX", 6);
    RwaCageSettlementFactory factory;

    function setUp() public {
        _initMCD();
        ilkToIlkInfo[ILK] = _initRWACollateral(ILK);

        factory = new RwaCageSettlementFactory(address(vat), address(end), address(registry));
    }

    function testCanCreateSettlementBeforeCage() public {
        RwaCageSettlement rcs = factory.createRwaCageSettlement(ILK, address(coin));

        assertTrue(address(rcs) != address(0), "Invalid RwaCageSettlement address");
        assertEq(rcs.price(), price, "Invalid RwaCageSettlement price");
    }

    function testCreateSettlementBeforeCageEmitTheProperEvent() public {
        IlkInfo storage info = ilkToIlkInfo[ILK];

        // 1. Ignore the created token address
        // 2. Check the `coin` param
        // 3. There is no 3rd indexed parameter, so ignore it
        // 4. Check the data
        vm.expectEmit(false, true, false, true);
        emit RwaCageSettlementCreated(address(0xde4d), ILK, address(coin), info.gem, info.price);

        factory.createRwaCageSettlement(ILK, address(coin));
    }

    function testCanCreateSettlementAfterCage() public {
        end.cage();
        end.cage(ILK);

        RwaCageSettlement rcs = factory.createRwaCageSettlement(ILK, address(coin));

        assertTrue(address(rcs) != address(0), "Invalid RwaCageSettlement address");
        assertEq(rcs.price(), price, "Invalid RwaCageSettlement price");
    }

    function testRevertWhenGemDoesNotExist() public {
        vm.expectRevert(bytes("RwaCageSettlementFactory/gem-does-not-exist"));
        factory.createRwaCageSettlement("INVALID_GEM", address(coin));
    }

    function testRevertWhenIlkHasBeenLiquidated() public {
        _liquidateRWA(ILK);

        // After liquidation the price for the collateral is set to 0.
        vm.expectRevert(bytes("RwaCageSettlement/price-out-of-bounds"));
        factory.createRwaCageSettlement(ILK, address(coin));
    }

    function _initMCD() internal {
        vat.rely(address(jug));
        vat.rely(address(daiJoin));
        vat.rely(address(spot));
        vat.rely(address(cat));
        vat.rely(address(dog));
        vat.rely(address(end));
        vat.file("Line", 100 * rad(CEILING));

        end.file("vat", address(vat));
        end.file("cat", address(cat));
        end.file("dog", address(dog));
        end.file("vow", address(vow));
        end.file("pot", address(pot));
        end.file("spot", address(spot));
        end.file("cure", address(cure));

        cat.rely(address(end));
        dog.rely(address(end));
        spot.rely(address(end));
        vow.rely(address(end));
        pot.rely(address(end));
        spot.rely(address(end));
        cure.rely(address(end));

        flap.rely(address(vow));
        flop.rely(address(vow));

        jug.file("vow", address(vow));

        dai.setOwner(address(daiJoin));

        registry = new IlkRegistry(address(vat), address(dog), address(cat), address(spot));
    }

    function _initRWACollateral(bytes32 ilk) internal returns (IlkInfo memory) {
        string memory name = bytes32ToStr(ilk);
        string memory symbol = name;

        RwaToken rwa = tokenFactory.createRwaToken(name, symbol, address(this));

        AuthGemJoin gemJoin = new AuthGemJoin(address(vat), ilk, address(rwa));
        vat.rely(address(gemJoin));

        RwaUrn2 urn = new RwaUrn2(address(vat), address(jug), address(gemJoin), address(daiJoin), OUTPUT_CONDUIT);
        gemJoin.rely(address(urn));
        rwa.approve(address(urn), type(uint256).max);

        vat.init(ilk);
        vat.file(ilk, "line", rad(CEILING));

        jug.init(ilk);
        jug.file(ilk, "duty", EIGHT_PCT);

        oracle.init(ilk, price, DOC, TAU);
        vat.rely(address(oracle));
        (, address pip, , ) = oracle.ilks(ilk);

        spot.file(ilk, "mat", 1 * RAY);
        spot.file(ilk, "pip", pip);
        spot.poke(ilk);

        urn.hope(address(this));
        urn.lock(1 * WAD);
        urn.draw(CEILING);

        IlkInfo memory info = IlkInfo({
            urn: address(urn),
            join: address(gemJoin),
            gem: address(rwa),
            dec: uint8(rwa.decimals()),
            class: ILK_CLASS_RWA,
            pip: pip,
            xlip: address(0),
            name: name,
            symbol: symbol,
            price: price
        });

        registry.put(ilk, info.join, info.gem, info.dec, info.class, info.pip, info.xlip, info.name, info.symbol);

        return info;
    }

    function _liquidateRWA(bytes32 ilk) internal {
        // Set DC to 0
        vat.file(ilk, "line", 0);

        // Start the liquidation process...
        oracle.tell(ilk);
        (, , uint256 tau, ) = oracle.ilks(ilk);
        // ... move past the remmediation period
        skip(tau);

        // ... and finally write-off the debt.
        oracle.cull(ilk, ilkToIlkInfo[ilk].urn);

        // Last, but not least, update the price feed.
        spot.poke(ilk);
    }

    function bytes32ToStr(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory bytesArray = new bytes(32);
        for (uint256 i; i < 32; i++) {
            bytesArray[i] = _bytes32[i];
        }
        return string(bytesArray);
    }

    function rad(uint256 wad) internal pure returns (uint256) {
        return wad * RAY;
    }

    event RwaCageSettlementCreated(
        address indexed cageSettlement,
        bytes32 indexed ilk,
        address coin,
        address gem,
        uint256 price
    );

    struct IlkInfo {
        address urn; // RWA urn
        address join; // DSS GemJoin adapter
        address gem; // The token contract
        uint8 dec; // Token decimals
        uint96 class; // Classification code (1 - clip, 2 - flip, 3+ - other)
        address pip; // Token price
        address xlip; // Auction contract
        string name; // Token name
        string symbol; // Token symbol
        uint256 price; // Token price
    }
}

contract TestCoin is DSToken {
    constructor(string memory _symbol, uint8 _decimals) public DSToken(_symbol) {
        decimals = _decimals;
    }
}
