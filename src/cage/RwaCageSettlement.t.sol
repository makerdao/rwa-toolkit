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
    IERC20 internal gem;
    IERC20 internal coin;
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

        // Make sure to use both standard and non-confirming tokens as `coin`
        uint256 coinImpl = (_coinDecimals + _gemDecimals + _gemPrice) % 3;
        if (coinImpl == 0) {
            coin = IERC20(address(new StandardToken("USDX", uint8(_coinDecimals))));
        } else if (coinImpl == 1) {
            coin = IERC20(address(new NoRevertToken("USDX", uint8(_coinDecimals))));
        } else {
            coin = IERC20(address(new MissingReturnsToken("USDX", uint8(_coinDecimals))));
        }

        gem = IERC20(address(new StandardToken("RWA00X", uint8(_gemDecimals))));
        settlement = new RwaCageSettlement(address(coin), address(gem), _gemPrice);

        // Mint the gem into the sender's balance
        uint256 gemSupply = 1 * 10**uint256(_gemDecimals);
        _mint(gem, sender, gemSupply);

        // Mint enough coins into the settlements's balance
        uint256 requiredCoinAmt = settlement.gemToCoin(gem.totalSupply());
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
        _coinAmt = bound(_coinAmt, 1, settlement.gemToCoin(gem.totalSupply()));
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
        StandardToken coin0 = new StandardToken("USDX", 0);
        StandardToken coin8 = new StandardToken("USDX", 8);

        // Gems with decimals > 27 are not supported
        StandardToken gem30 = new StandardToken("RWA00X", 30);
        // Gems with decimals < 2 are not supported
        StandardToken gem0 = new StandardToken("RWA00X", 0);
        StandardToken gem2 = new StandardToken("RWA00X", 2);

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
        coin = IERC20(address(new StandardToken("USDX", DEFAULT_COIN_DECIMALS)));

        vm.expectRevert(bytes("RwaCageSettlement/price-out-of-bounds"));
        settlement = new RwaCageSettlement(address(coin), address(gem), 0);
    }

    function testRevertConstructorWhenPriceIsTooHigh() public {
        coin = IERC20(address(new StandardToken("USDX", DEFAULT_COIN_DECIMALS)));

        vm.expectRevert(bytes("RwaCageSettlement/price-out-of-bounds"));
        // Max price is 10**(15+18)=10**33, which means 1 Trillion Dai
        settlement = new RwaCageSettlement(address(coin), address(gem), 10**45);
    }

    function testRedeemEvents() public {
        _setUp();

        uint256 redeemGems = gem.balanceOf(sender);

        vm.expectEmit(true, false, false, true);
        emit Redeem(sender, redeemGems, settlement.gemToCoin(gem.totalSupply()));

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

        vm.expectRevert(bytes("RwaCageSettlement/coin-transfer-failed"));
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

        vm.expectRevert(bytes("RwaCageSettlement/coin-transfer-failed"));
        vm.prank(otherSender);
        settlement.deposit(10**16);
    }

    function testRevertDepositWithoutCoinAllowance() public {
        _setUp();
        // Remove allowance
        _approve(address(coin), sender, address(settlement), 0);

        uint256 mintedCoins = settlement.gemToCoin(10_000 * WAD);
        _mint(coin, sender, mintedCoins);

        vm.expectRevert(bytes("RwaCageSettlement/coin-transfer-failed"));
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
        IERC20 token,
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
        vm.prank(from);
        (bool ok, ) = _token.call(abi.encodeWithSelector(IERC20(_token).approve.selector, to, allowance));

        assertTrue(ok, "_approve: approve failed");
        // Sanity check
        assertEq(IERC20(_token).allowance(from, to), allowance, "_approve: approve failed");
    }

    event Redeem(address indexed sender, uint256 gemWad, uint256 coinAmt);
    event Deposit(address indexed sender, uint256 coinAmt);

    struct Balances {
        uint256 settlement;
        uint256 sender;
    }
}

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function transfer(address, uint256) external;

    function allowance(address, address) external view returns (uint256);

    function approve(address, uint256) external;

    function transferFrom(
        address,
        address,
        uint256
    ) external;

    function mint(uint256) external;

    function mint(address, uint256) external;
}

contract StandardToken is DSToken {
    constructor(string memory _symbol, uint8 _decimals) public DSToken(_symbol) {
        decimals = _decimals;
    }
}

contract NoRevertToken {
    // --- ERC20 Data ---
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Mint(address indexed usr, uint256 wad);

    // --- Init ---
    constructor(string memory _symbol, uint8 _decimals) public {
        symbol = _symbol;
        decimals = _decimals;
    }

    // --- Token ---
    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public virtual returns (bool) {
        if (balanceOf[src] < wad) return false; // insufficient src bal
        if (balanceOf[dst] >= (type(uint256).max - wad)) return false; // dst bal too high

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            if (allowance[src][msg.sender] < wad) return false; // insufficient allowance
            allowance[src][msg.sender] = allowance[src][msg.sender] - wad;
        }

        balanceOf[src] = Math.sub(balanceOf[src], wad);
        balanceOf[dst] = Math.add(balanceOf[dst], wad);

        emit Transfer(src, dst, wad);
        return true;
    }

    function approve(address usr, uint256 wad) external virtual returns (bool) {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
        return true;
    }

    function mint(uint256 wad) external {
        mint(msg.sender, wad);
    }

    function mint(address usr, uint256 wad) public virtual {
        balanceOf[usr] = Math.add(balanceOf[usr], wad);
        totalSupply = Math.add(totalSupply, wad);
        emit Mint(usr, wad);
    }
}

contract MissingReturnsToken {
    // --- ERC20 Data ---
    string public symbol;
    uint8 public immutable decimals;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Mint(address indexed usr, uint256 wad);

    // --- Init ---
    constructor(string memory _symbol, uint8 _decimals) public {
        symbol = _symbol;
        decimals = _decimals;
    }

    // --- Token ---
    function transfer(address dst, uint256 wad) external {
        transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public virtual {
        require(balanceOf[src] >= wad, "insufficient-balance");

        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            require(allowance[src][msg.sender] >= wad, "insufficient-allowance");
            allowance[src][msg.sender] = allowance[src][msg.sender] - wad;
        }

        balanceOf[src] = Math.sub(balanceOf[src], wad);
        balanceOf[dst] = Math.add(balanceOf[dst], wad);

        emit Transfer(src, dst, wad);
    }

    function approve(address usr, uint256 wad) external virtual {
        allowance[msg.sender][usr] = wad;
        emit Approval(msg.sender, usr, wad);
    }

    function mint(uint256 wad) external {
        mint(msg.sender, wad);
    }

    function mint(address usr, uint256 wad) public virtual {
        balanceOf[usr] = Math.add(balanceOf[usr], wad);
        totalSupply = Math.add(totalSupply, wad);
        emit Mint(usr, wad);
    }
}

library Math {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Math/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }
}
