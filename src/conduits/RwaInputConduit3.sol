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

import {GemAbstract} from "dss-interfaces/ERC/GemAbstract.sol";
import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";
import {PsmAbstract} from "dss-interfaces/dss/PsmAbstract.sol";
import {GemJoinAbstract} from "dss-interfaces/dss/GemJoinAbstract.sol";

/**
 * @author Lev Livnev <lev@liv.nev.org.uk>
 * @author Nazar Duchak <nazar@clio.finance>
 * @title An Input Conduit for real-world assets (RWA).
 * @dev This contract differs from the original [RwaInputConduit](https://github.com/makerdao/MIP21-RWA-Example/blob/fce06885ff89d10bf630710d4f6089c5bba94b4d/src/RwaConduit.sol#L20-L39):
 *  - The caller of `push()` is not required to hold MakerDAO governance tokens.
 *  - The `push()` method is permissioned.
 *  - `push()` permissions are managed by `mate()`/`hate()` methods.
 *  - Require PSM address in constructor
 *  - The `push()` method swaps GEM to DAI using PSM
 *  - THe `push()` method with `amt` argument swaps specified amount of GEM to DAI using PSM
 *  - The `quit` method allows moving outstanding GEM balance to `quitTo`. It can be called only by the admin.
 *  - The `quit` method with `amount` argument allows moving specified amount of GEM balance to `quitTo`.
 *  - The `file` method allows updating `quitTo`, `to` addresses. It can be called only by the admin.
 */
contract RwaInputConduit3 {
    /// @notice PSM GEM token contract address
    GemAbstract public immutable gem;
    /// @notice PSM contract address
    PsmAbstract public immutable psm;
    /// @dev DAI/GEM resolution difference.
    uint256 private immutable to18ConvertionFactor;

    /// @dev This is declared here so the storage layout lines up with RwaInputConduit.
    address private __unused_gov;
    /// @notice Dai token contract address
    DaiAbstract public dai;
    /// @notice RWA urn contract address
    address public to;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with push access on this contract. `may[usr]`
    mapping(address => uint256) public may;

    /// @notice Exit address
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
     * @notice `wad` amount of Dai was pushed to `to`
     * @param to The RwaUrn address
     * @param wad The amount of Dai
     */
    event Push(address indexed to, uint256 wad);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "quitTo", "to".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice The conduit outstanding gem balance was flushed out to `exitAddress`.
     * @param quitTo The quitTo address.
     * @param wad The amount flushed out.
     */
    event Quit(address indexed quitTo, uint256 wad);
    /**
     * @notice The conduit outstanding DAI balance was flushed out to destination address.
     * @param usr The destination address.
     * @param wad The amount of DAI flushed out.
     */
    event Yank(address indexed usr, uint256 wad);

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaInputConduit3/not-authorized");
        _;
    }

    modifier isMate() {
        require(may[msg.sender] == 1, "RwaInputConduit3/not-mate");
        _;
    }

    /**
     * @notice Define addresses and gives `msg.sender` admin access.
     * @param _psm PSM contract address.
     * @param _to RwaUrn contract address.
     */
    constructor(address _psm, address _to) public {
        require(_to != address(0), "RwaInputConduit3/invalid-to-address");

        GemAbstract _gem = GemAbstract(GemJoinAbstract(PsmAbstract(_psm).gemJoin()).gem());
        psm = PsmAbstract(_psm);
        dai = DaiAbstract(PsmAbstract(_psm).dai());
        gem = _gem;
        to = _to;

        to18ConvertionFactor = 10**sub(18, _gem.decimals());

        // Give unlimited approve to PSM gemjoin
        _gem.approve(address(PsmAbstract(_psm).gemJoin()), type(uint256).max);

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
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

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"quitTo", "to"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "quitTo") {
            quitTo = data;
        } else if (what == "to") {
            to = data;
        } else {
            revert("RwaInputConduit3/unrecognised-param");
        }

        emit File(what, data);
    }

    /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    /**
     * @notice Swaps the GEM balance of this contract into DAI through the PSM and push it into the `to` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     */
    function push() external isMate {
        _doPush(gem.balanceOf(address(this)));
    }

    /**
     * @notice Swaps the specified amount of GEM into DAI through the PSM and push it into the `to` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     * @param amt Gem amount.
     */
    function push(uint256 amt) external isMate {
        _doPush(amt);
    }

    /**
     * @notice Flushes out any GEM balance to `quitTo` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     */
    function quit() external isMate {
        _doQuit(gem.balanceOf(address(this)));
    }

    /**
     * @notice Flushes out specific amount of GEM balance to `quitTo` address.
     * @dev `msg.sender` must have received push access through `mate()`.
     * @param amt Gem amount.
     */
    function quit(uint256 amt) external isMate {
        _doQuit(amt);
    }

    /**
     * @notice Flushes out all outstanding DAI balance to `usr` address.
     * @dev Can only be called by the admin
     * @param usr Destination address.
     */
    function yank(address usr) external auth {
        uint256 wad = dai.balanceOf(address(this));
        dai.transfer(usr, wad);
        emit Yank(usr, wad);
    }

    /**
     * @notice Calculate required amount of GEM to get `wad` amount of DAI.
     * @param wad DAI amount.
     * @return gemAmt Amount of GEM required.
     */
    function requiredGemAmt(uint256 wad) external view returns (uint256 gemAmt) {
        return mul(wad, WAD) / mul(sub(WAD, psm.tin()), to18ConvertionFactor);
    }

    /**
     * @notice Swaps the specified amount of GEM into DAI through the PSM and push it into the `to` address.
     * @param amt GEM amount.
     */
    function _doPush(uint256 amt) internal {
        require(to != address(0), "RwaInputConduit3/invalid-to-address");
        uint256 prevDaiBalance = dai.balanceOf(address(this));

        psm.sellGem(address(this), amt);

        uint256 daiPushAmt = sub(dai.balanceOf(address(this)), prevDaiBalance);
        dai.transfer(to, daiPushAmt);

        emit Push(to, daiPushAmt);
    }

    /**
     * @notice Flushes out the specified amount of GEM to the `quitTo` address.
     * @param amt GEM amount.
     */
    function _doQuit(uint256 amt) internal {
        require(quitTo != address(0), "RwaInputConduit3/invalid-quit-to-address");
        gem.transfer(quitTo, amt);
        emit Quit(quitTo, amt);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    uint256 internal constant WAD = 10**18;

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-overflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }
}
