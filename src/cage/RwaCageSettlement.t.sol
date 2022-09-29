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

import {Test} from "forge-std/Test.sol";
import {DSToken} from "ds-token/token.sol";
import {DSMath} from "ds-math/math.sol";
import {Vat} from "dss/vat.sol";
import {RwaCageSettlement} from "./RwaCageSettlement.sol";

contract RwaCageSettlementTest is Test {
    uint256 internal constant WAD = 10**18;

    RwaCageSettlement internal settlement;
    TestCoin internal gem;
    TestCoin internal coin;
    address internal sender = address(0x1337);

    // Regular test parameters
    uint8 internal constant DEFAULT_COIN_DECIMALS = 6;
    uint8 internal constant DEFAULT_GEM_DECIMALS = 18;
    uint256 internal constant DEFAULT_GEM_PRICE = 100_000_000 * WAD;

    // Using regular setUp makes fuzz tests fail, so we need a different name.
    // We also need to invoke this function manually in every test.
    function _setUp() internal {
        _parametricSetUp(DEFAULT_COIN_DECIMALS, DEFAULT_GEM_DECIMALS, DEFAULT_GEM_PRICE);
    }

    function _parametricSetUp(
        uint256 _coinDecimals,
        uint256 _gemDecimals,
        uint256 _gemPrice
    ) internal {
        require(_coinDecimals <= _gemDecimals, "coinDecimals too big");
        require(_gemDecimals <= 27, "gemDecimals too big");
        require(_gemPrice >= 1 * WAD && _gemPrice <= 10**15 * WAD, "gemPrice out of bounds");

        coin = new TestCoin("USDX", uint8(_coinDecimals));
        gem = new TestCoin("RWA00X", uint8(_gemDecimals));
        settlement = new RwaCageSettlement(address(coin), address(gem), _gemPrice);

        // Mint the gem into the sender's balance
        uint256 gemSupply = 1 * 10**uint256(_gemDecimals);
        _mint(gem, sender, gemSupply);

        // Mint enough coins into the settlements's balance
        uint256 requiredCoinAmt = settlement.totalRequiredDeposit();
        _mint(coin, address(settlement), requiredCoinAmt);

        // Approve the settlement to spend RWA tokens on sender's behalf
        _approve(address(gem), sender, address(settlement), type(uint256).max);

        // Approve the settlement to spend coins on sender's behalf
        _approve(address(coin), sender, address(settlement), type(uint256).max);
    }

    // Asserts against gem and coin balance changes of the sender and the settlement contract, before and after calling
    // `redeem` with an arbitrary value.
    function testRedeemFuzz(
        uint8 _coinDecimals,
        uint8 _gemDecimals,
        uint256 _gemPrice,
        uint256 _redeemGems
    ) public {
        uint256 gemDecimals = bound(uint256(_gemDecimals), 2, 27);
        uint256 coinDecimals = bound(uint256(_coinDecimals), 2, gemDecimals);
        // RWA price between 1 and 1_000_000_000_000_000 Dai
        _gemPrice = bound(_gemPrice, 1 * WAD, 10**15 * WAD);

        // Manual _parametricSetUp required because of fuzzing
        _parametricSetUp(coinDecimals, gemDecimals, _gemPrice);

        uint256 pCurrentlyRedeemable = settlement.currentlyRedeemable();
        uint256 minRedeemable = settlement.minRedeemable();
        _redeemGems = bound(_redeemGems, minRedeemable, pCurrentlyRedeemable);

        Balances memory pGemBalances = Balances({
            sender: gem.balanceOf(sender),
            settlement: gem.balanceOf(address(settlement))
        });

        Balances memory pCoinBalances = Balances({
            sender: coin.balanceOf(sender),
            settlement: coin.balanceOf(address(settlement))
        });

        vm.prank(sender);
        settlement.redeem(_redeemGems);

        Balances memory gemBalances = Balances({
            sender: gem.balanceOf(sender),
            settlement: gem.balanceOf(address(settlement))
        });

        Balances memory coinBalances = Balances({
            sender: coin.balanceOf(sender),
            settlement: coin.balanceOf(address(settlement))
        });

        assertEq(
            gemBalances.sender,
            pGemBalances.sender - _redeemGems,
            "redeem: [sender] invalid gem balance change!!!"
        );
        assertEq(
            gemBalances.settlement,
            pGemBalances.settlement + _redeemGems,
            "redeem: [settlement] invalid gem balance change!!!"
        );

        uint256 receivedCoin = settlement.gemToCoin(_redeemGems);
        assertEq(
            coinBalances.sender,
            pCoinBalances.sender + receivedCoin,
            "redeem: [sender] invalid coin balance change!!!"
        );
        assertEq(
            coinBalances.settlement,
            pCoinBalances.settlement - receivedCoin,
            "redeem: [settlement] invalid coin balance change!!!"
        );
    }

    // Asserts against the coin balances of both the sender and the settlement contract, before and after calling
    // `deposit` with an arbitrary value.
    function testDepositFuzz(
        uint8 _coinDecimals,
        uint8 _gemDecimals,
        uint256 _gemPrice,
        uint256 _coinAmt
    ) public {
        uint256 gemDecimals = bound(uint256(_gemDecimals), 2, 27);
        uint256 coinDecimals = bound(uint256(_coinDecimals), 2, gemDecimals);
        // RWA price between 1 and 1_000_000_000_000_000 Dai
        _gemPrice = bound(_gemPrice, 1 * WAD, 10**15 * WAD);

        _parametricSetUp(coinDecimals, gemDecimals, _gemPrice);

        // Up to 100_000_000 units of coin
        _coinAmt = bound(_coinAmt, 1, settlement.totalRequiredDeposit());
        _mint(coin, sender, _coinAmt);

        Balances memory pBalances = Balances({
            sender: coin.balanceOf(sender),
            settlement: coin.balanceOf(address(settlement))
        });

        vm.prank(sender);
        settlement.deposit(_coinAmt);

        Balances memory balances = Balances({
            sender: coin.balanceOf(sender),
            settlement: coin.balanceOf(address(settlement))
        });

        assertEq(balances.sender, pBalances.sender - _coinAmt, "deposit: [sender] Invalid coin balance change");
        assertEq(
            balances.settlement,
            pBalances.settlement + _coinAmt,
            "deposit: [settlement] Invalid coin balance change"
        );
    }

    // Asserts that is not possible to redeem less than `minRedeemable`.  Asserts that is always possible redeem
    // `minRedeemable`, given enough gems and coins are available.
    function testMinRedeemableFuzz(
        uint8 _coinDecimals,
        uint8 _gemDecimals,
        uint256 _gemPrice
    ) public {
        uint256 gemDecimals = bound(uint256(_gemDecimals), 2, 27);
        uint256 coinDecimals = bound(uint256(_coinDecimals), 2, gemDecimals);
        // RWA price between 1 and 1_000_000_000_000_000 Dai
        _gemPrice = bound(_gemPrice, 1 * WAD, 10**15 * WAD);

        // Manual _parametricSetUp required because of fuzzing
        _parametricSetUp(coinDecimals, gemDecimals, _gemPrice);

        uint256 redeemGems = settlement.minRedeemable();

        // Fails if below threshold
        vm.expectRevert(bytes("RwaCageSettlement/too-few-gems"));
        vm.prank(sender);
        settlement.redeem(redeemGems - 1);

        // Succeeds at threshold
        vm.prank(sender);
        settlement.redeem(redeemGems);

        uint256 settlementGemBalance = gem.balanceOf(address(settlement));
        assertEq(settlementGemBalance, redeemGems, "minRedeemable: invalid gem balance");
    }

    // Attempts to redeem a smaller amount first. Redeem either the remaining balance or the maximum redeemable,
    // depending on how rounding errors played out.
    // Asserts that the remaining redeemable amount is negligible.
    function testCurrentlyRedeemableFuzz(
        uint8 _coinDecimals,
        uint8 _gemDecimals,
        uint256 _gemPrice,
        uint256 _redeemGems
    ) public {
        uint256 gemDecimals = bound(uint256(_gemDecimals), 2, 27);
        uint256 coinDecimals = bound(uint256(_coinDecimals), 2, gemDecimals);
        // RWA price between 1 and 1_000_000_000_000_000 Dai
        _gemPrice = bound(_gemPrice, 1 * WAD, 10**15 * WAD);

        // Manual _parametricSetUp required because of fuzzing
        _parametricSetUp(coinDecimals, gemDecimals, _gemPrice);

        uint256 pCurrentlyRedeemable = settlement.currentlyRedeemable();
        uint256 minRedeemable = settlement.minRedeemable();
        // First redeem up to half of the available gems...
        _redeemGems = bound(_redeemGems, minRedeemable, pCurrentlyRedeemable / 2);

        vm.prank(sender);
        settlement.redeem(_redeemGems);

        uint256 currentlyRedeemable = settlement.currentlyRedeemable();
        vm.assume(currentlyRedeemable > 0);

        uint256 pGemBalance = gem.balanceOf(sender);

        // ... Next redeem all the remaining balance or all available (rounding errors might exist)
        _redeemGems = pGemBalance > currentlyRedeemable ? currentlyRedeemable : pGemBalance;

        vm.prank(sender);
        settlement.redeem(_redeemGems);

        uint256 gemBalance = gem.balanceOf(sender);
        assertEq(gemBalance, pGemBalance - _redeemGems, "currentlyRedeemable: invalid sender gem balance change");

        uint256 tolerance = 10**uint256(_gemDecimals); // <1%
        assertApproxEqAbs(
            settlement.currentlyRedeemable(),
            0,
            tolerance,
            "currentlyRedeemable: invalid currentlyRedeemable at the end"
        );
    }

    function testRevertConstructorWhenTokensHaveInvalidDecimals() public {
        // Coins with decimals < 2 are not supported
        TestCoin coin0 = new TestCoin("USDX", 0);
        TestCoin coin8 = new TestCoin("USDX", 8);

        // Gems with decimals > 27 are not supported
        TestCoin gem30 = new TestCoin("RWA00X", 30);
        // Gems with decimals < 2 are not supported
        TestCoin gem0 = new TestCoin("RWA00X", 0);
        TestCoin gem2 = new TestCoin("RWA00X", 2);

        vm.expectRevert(bytes("RwaCageSettlement/gem-decimals-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin8), address(gem30), DEFAULT_GEM_PRICE);

        vm.expectRevert(bytes("RwaCageSettlement/gem-decimals-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin0), address(gem0), DEFAULT_GEM_PRICE);

        // Requires coin.decimals() <= gem.decimals()
        vm.expectRevert(bytes("RwaCageSettlement/coin-decimals-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin8), address(gem2), DEFAULT_GEM_PRICE);

        vm.expectRevert(bytes("RwaCageSettlement/coin-decimals-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin0), address(gem2), DEFAULT_GEM_PRICE);
    }

    function testRevertConstructorWhenPriceIsZero() public {
        coin = new TestCoin("USDX", DEFAULT_COIN_DECIMALS);

        vm.expectRevert(bytes("RwaCageSettlement/price-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin), address(gem), 0);
    }

    function testRevertConstructorWhenPriceIsTooHigh() public {
        coin = new TestCoin("USDX", DEFAULT_COIN_DECIMALS);

        vm.expectRevert(bytes("RwaCageSettlement/price-out-of-bounds"));
        // Max price is 10**(15+18)=10**33, which means 1 Trillion Dai
        settlement = new RwaCageSettlement(address(coin), address(gem), 10**45);
    }

    function testRedeemEvents() public {
        _setUp();

        uint256 redeemGems = gem.balanceOf(sender);

        vm.expectEmit(true, false, false, true);
        emit Redeem(sender, redeemGems, settlement.totalRequiredDeposit());

        vm.prank(sender);
        settlement.redeem(redeemGems);
    }

    function testRevertRedeemWithoutGemBalance() public {
        _setUp();

        address otherSender = address(0xde4d);
        _approve(address(gem), otherSender, address(settlement), type(uint256).max);

        vm.expectRevert(bytes("ds-token-insufficient-balance"));
        vm.prank(otherSender);
        settlement.redeem(10**16);
    }

    function testRevertRedeemWithoutCoinBalance() public {
        _setUp();

        // Burning half of the settlement coins is enough to make it fail...
        uint256 settlementCoins = coin.balanceOf(address(settlement));
        vm.prank(address(settlement));
        coin.transfer(address(0), settlementCoins / 2);

        uint256 redeemGems = gem.balanceOf(sender);

        vm.expectRevert(bytes("ds-token-insufficient-balance"));
        vm.prank(sender);
        settlement.redeem(redeemGems);
    }

    function testRevertRedeemWithoutGemAllowance() public {
        _setUp();

        uint256 redeemGems = gem.balanceOf(sender);
        // Remove allowance
        _approve(address(gem), sender, address(settlement), 0);

        vm.expectRevert(bytes("ds-token-insufficient-approval"));
        vm.prank(sender);
        settlement.redeem(redeemGems);
    }

    function testDepositEvents() public {
        _setUp();

        uint256 mintedCoins = settlement.gemToCoin(10_000 * WAD);
        _mint(coin, sender, mintedCoins);

        vm.expectEmit(true, false, false, true);
        emit Deposit(sender, mintedCoins);

        vm.prank(sender);
        settlement.deposit(mintedCoins);
    }

    function testRevertDepositWithoutCoinBalance() public {
        _setUp();

        address otherSender = address(0xde4d);
        _approve(address(coin), otherSender, address(settlement), type(uint256).max);

        vm.expectRevert(bytes("ds-token-insufficient-balance"));
        vm.prank(otherSender);
        settlement.deposit(10**16);
    }

    function testRevertDepositWithoutCoinAllowance() public {
        _setUp();
        // Remove allowance
        _approve(address(coin), sender, address(settlement), 0);

        uint256 mintedCoins = settlement.gemToCoin(10_000 * WAD);
        _mint(coin, sender, mintedCoins);

        vm.expectRevert(bytes("ds-token-insufficient-approval"));
        vm.prank(sender);
        settlement.deposit(mintedCoins);
    }

    function testGetTotalRedeemed() public {
        _setUp();

        uint256 redeemGems = gem.balanceOf(sender);
        vm.prank(sender);
        settlement.redeem(redeemGems);

        uint256 totalRedeemed = settlement.totalRedeemed();

        assertEq(totalRedeemed, redeemGems, "totalRedeemed: invalid result");
    }

    function testGetRemainingToRedeem() public {
        _setUp();

        uint256 redeemGems = gem.balanceOf(sender) / 4;

        vm.prank(sender);
        settlement.redeem(redeemGems);

        uint256 remainingToRedeem = settlement.remainingToRedeem();

        assertEq(remainingToRedeem, gem.totalSupply() - redeemGems, "remainingToRedeem: invalid result");
    }

    function testGetCurrentlyDeposited() public {
        _setUp();

        uint256 mintedCoins = settlement.gemToCoin(10_000 * WAD);
        _mint(coin, sender, mintedCoins);

        uint256 pCurrentlyDeposited = settlement.currentlyDeposited();

        vm.prank(sender);
        settlement.deposit(mintedCoins);

        uint256 currentlyDeposited = settlement.currentlyDeposited();

        assertEq(currentlyDeposited, pCurrentlyDeposited + mintedCoins, "currentlyDeposited: invalid result");
    }

    function _mint(
        DSToken token,
        address to,
        uint256 coinAmt
    ) internal {
        token.mint(coinAmt);
        token.transfer(to, coinAmt);

        // Sanity check
        assertEq(token.balanceOf(to), coinAmt, "_mint: coin minting failed");
    }

    function _approve(
        address _token,
        address from,
        address to,
        uint256 allowance
    ) internal {
        DSToken token = DSToken(_token);

        vm.prank(from);
        token.approve(address(to), allowance);

        // Sanity check
        assertEq(token.allowance(from, to), allowance, "_approve: approve failed");
    }

    event Redeem(address indexed sender, uint256 gemWad, uint256 coinAmt);
    event Deposit(address indexed sender, uint256 coinAmt);

    struct Balances {
        uint256 settlement;
        uint256 sender;
    }
}

contract TestCoin is DSToken {
    constructor(string memory _symbol, uint8 _decimals) public DSToken(_symbol) {
        decimals = _decimals;
    }
}
