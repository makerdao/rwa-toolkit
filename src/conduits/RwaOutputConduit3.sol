// SPDX-FileCopyrightText: © 2020-2021 Lev Livnev <lev@liv.nev.org.uk>
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

import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";
import {PsmAbstract} from "dss-interfaces/dss/PsmAbstract.sol";
import {GemAbstract} from "dss-interfaces/ERC/GemAbstract.sol";
import {GemJoinAbstract} from "dss-interfaces/dss/GemJoinAbstract.sol";

/**
 * @author Lev Livnev <lev@liv.nev.org.uk>
 * @author Nazar Duchak <nazar@clio.finance>
 * @title An Output Conduit for real-world assets (RWA).
 * @dev This contract differs from the original [RwaOutputConduit](https://github.com/makerdao/MIP21-RWA-Example/blob/fce06885ff89d10bf630710d4f6089c5bba94b4d/src/RwaConduit.sol#L41-L118):
 *  - The caller of `push()` is not required to hold MakerDAO governance tokens.
 *  - The `push()` method is permissioned.
 *  - `push()` permissions are managed by `mate()`/`hate()` methods.
 *  - `pick` whitelist is managed by `kiss() / diss()` methods.
 *  - Requires a PSM address in the constructor.
 *  - `pick` can be called to set the `to` address. Eligible `to` addresses should be whitelisted by an admin through `kiss`.
 *  - The `push()` method swaps DAI to GEM using PSM and set `to` to zero address.
 *  - The `push()` method with `amount` argument swaps specified amount of DAI to GEM using PSM and set `to` to zero address.
 *  - The `quit` method allows moving outstanding DAI balance to `quitTo`. It can be called only by `mate`d addresses.
 *  - The `quit` method with `amount` argument allows moving specified amount of DAI balance to `quitTo`
 *  - The `file` method allows updating `quitTo` addresses. It can be called only by the admin.
 */
contract RwaOutputConduit3 {
    /// @notice PSM GEM token contract address.
    GemAbstract public immutable gem;
    /// @notice PSM contract address.
    PsmAbstract public immutable psm;
    /// @dev DAI/GEM resolution difference.
    uint256 private immutable to18ConvertionFactor;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @dev Addresses with operator access on this contract. `can[usr]`
    mapping(address => uint256) public can;

    /// @dev Not used
    address private __unused_gov;
    /// @notice Dai token contract address.
    DaiAbstract public dai;
    /// @notice Dai Recipient address.
    address public to;

    /// @notice Whitelist for addresses which can be picked. `bud[who]`
    mapping(address => uint256) public bud;
    /// @notice Addresses with push access on this contract. `may[usr]`
    mapping(address => uint256) public may;

    /// @notice Address to where DAI goes after calling `quit`
    address public quitTo;

    /**
     * @notice `usr` was granted admin access.
     * @param usr The user address.
     */
    event Rely(address indexed usr);
    /**
     * @notice `usr` admin access was revoked.
     * @param usr The user address.
     */
    event Deny(address indexed usr);
    /**
     * @notice `usr` was granted operator access.
     * @param usr The user address.
     */
    event Hope(address indexed usr);
    /**
     * @notice `usr` operator access was revoked.
     * @param usr The user address.
     */
    event Nope(address indexed usr);
    /**
     * @notice `usr` was granted push access.
     * @param usr The user address.
     */
    event Mate(address indexed usr);
    /**
     * @notice `usr` push access was revoked.
     * @param usr The user address.
     */
    event Hate(address indexed usr);
    /**
     * @notice `who` address whitelisted for pick.
     * @param who The user address.
     */
    event Kiss(address indexed who);
    /**
     * @notice `who` address was removed from whitelist.
     * @param who The user address.
     */
    event Diss(address indexed who);
    /**
     * @notice `who` address was picked as the recipient.
     * @param who The user address.
     */
    event Pick(address indexed who);
    /**
     * @notice `wad` amount of Dai was pushed to the recipient `to`.
     * @param to The Dai recipient address
     * @param wad The amount of Dai
     */
    event Push(address indexed to, uint256 wad);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "quitTo".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice The conduit outstanding DAI balance was flushed out to `quitTo` address.
     * @param quitTo The quitTo address.
     * @param wad The amount of DAI flushed out.
     */
    event Quit(address indexed quitTo, uint256 wad);
    /**
     * @notice The conduit outstanding gem balance was flushed out to destination address.
     * @param usr The destination address.
     * @param amt The amount of Gem flushed out.
     */
    event Yank(address indexed usr, uint256 amt);

    /**
     * @notice Defines PSM and quitTo addresses and gives `msg.sender` admin access.
     * @param _psm PSM contract address.
     */
    constructor(address _psm) public {
        GemAbstract _gem = GemAbstract(GemJoinAbstract(PsmAbstract(_psm).gemJoin()).gem());
        psm = PsmAbstract(_psm);
        gem = _gem;
        dai = DaiAbstract(PsmAbstract(_psm).dai());
        to18ConvertionFactor = 10**sub(18, _gem.decimals());

        // Give unlimited approve to PSM
        dai.approve(_psm, type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaOutputConduit3/not-authorized");
        _;
    }

    modifier isMate() {
        require(may[msg.sender] == 1, "RwaOutputConduit3/not-mate");
        _;
    }

    /*//////////////////////////////////
               Authorization
    //////////////////////////////////*/

    /**
     * @notice Grants `usr` admin access to this contract.
     * @param usr The user address.
     */
    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    /**
     * @notice Revokes `usr` admin access from this contract.
     * @param usr The user address.
     */
    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    /**
     * @notice Grants `usr` operator access to this contract.
     * @param usr The user address.
     */
    function hope(address usr) external auth {
        can[usr] = 1;
        emit Hope(usr);
    }

    /**
     * @notice Revokes `usr` operator access from this contract.
     * @param usr The user address.
     */
    function nope(address usr) external auth {
        can[usr] = 0;
        emit Nope(usr);
    }

    /**
     * @notice Grants `usr` push access to this contract.
     * @param usr The user address.
     */
    function mate(address usr) external auth {
        may[usr] = 1;
        emit Mate(usr);
    }

    /**
     * @notice Revokes `usr` push access from this contract.
     * @param usr The user address.
     */
    function hate(address usr) external auth {
        may[usr] = 0;
        emit Hate(usr);
    }

    /**
     * @notice Whitelist `who` address for `pick`.
     * @param who The user address.
     */
    function kiss(address who) external auth {
        bud[who] = 1;
        emit Kiss(who);
    }

    /**
     * @notice Remove `who` address from `pick` whitelist.
     * @param who The user address.
     */
    function diss(address who) external auth {
        if (to == who) to = address(0);
        bud[who] = 0;
        emit Diss(who);
    }

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"quitTo"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "quitTo") {
            quitTo = data;
        } else {
            revert("RwaOutputConduit3/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Sets `who` address as the recipient.
     * @param who Recipient address.
     * @dev `who` address should have been whitelisted using `kiss`.
     */
    function pick(address who) external {
        require(can[msg.sender] == 1, "RwaOutputConduit3/not-operator");
        require(bud[who] == 1 || who == address(0), "RwaOutputConduit3/not-bud");
        to = who;
        emit Pick(who);
    }

    /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    /**
     * @notice Method to swap DAI contract balance to GEM through PSM and push it to the recipient address.
     * @dev `msg.sender` must have been `mate`d and `to` must have been `pick`ed.
     */
    function push() external isMate {
        _doPush(dai.balanceOf(address(this)));
    }

    /**
     * @notice Swaps the specified amount of DAI into GEM through the PSM and push it to the recipient address.
     * @dev `msg.sender` must have been `mate`d and `to` must have been `pick`ed.
     * @param wad DAI amount.
     */
    function push(uint256 wad) external isMate {
        _doPush(wad);
    }

    /**
     * @notice Flushes out any DAI balance to `quitTo` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     */
    function quit() external isMate {
        _doQuit(dai.balanceOf(address(this)));
    }

    /**
     * @notice Flushes out the specified amount of DAI to the `quitTo` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     * @param wad DAI amount.
     */
    function quit(uint256 wad) external isMate {
        _doQuit(wad);
    }

    /**
     * @notice Flushes out any GEM balance to `usr` address.
     * @param usr Destination address
     * @dev Can be called only by admin.
     */
    function yank(address usr) external auth {
        uint256 amt = gem.balanceOf(address(this));
        gem.transfer(usr, amt);
        emit Yank(usr, amt);
    }

    /**
     * @notice Calculate expected amount of GEM received for swapping `wad` amount of DAI.
     * @param wad DAI amount.
     * @return gemAmt Amount of GEM expected.
     */
    function expectedGemAmt(uint256 wad) public view returns (uint256) {
        return mul(wad, WAD) / mul(add(WAD, psm.tout()), to18ConvertionFactor);
    }

    /**
     * @notice Swaps the specified amount of DAI into GEM through the PSM and push it to the recipient address.
     * @param wad DAI amount.
     */
    function _doPush(uint256 wad) internal {
        require(to != address(0), "RwaOutputConduit3/to-not-picked");

        // We might lose some dust here because of rounding errors. I.e.: USDC has 6 dec and DAI has 18.
        uint256 gemAmt = expectedGemAmt(wad);
        require(gemAmt > 0, "RwaOutputConduit3/insufficient-swap-gem-amount");

        address recipient = to;
        to = address(0);

        psm.buyGem(recipient, gemAmt);

        emit Push(recipient, gemAmt);
    }

    /**
     * @notice Flushes out the specified amount of DAI to `quitTo` address.
     * @param wad The DAI amount.
     */
    function _doQuit(uint256 wad) internal {
        require(quitTo != address(0), "RwaOutputConduit3/invalid-quit-to-address");
        dai.transfer(quitTo, wad);
        emit Quit(quitTo, wad);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    uint256 internal constant WAD = 10**18;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "Math/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-overflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }
}
