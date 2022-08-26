// Copyright (C) 2020, 2021 Lev Livnev <lev@liv.nev.org.uk>
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

import {DSTokenAbstract} from "dss-interfaces/dapp/DSTokenAbstract.sol";
import {PsmAbstract} from "dss-interfaces/dss/PsmAbstract.sol";
import {GemJoinAbstract} from "dss-interfaces/dss/GemJoinAbstract.sol";

/**
 * @author Lev Livnev <lev@liv.nev.org.uk>
 * @author Nazar Duchak <nazar@clio.finance>
 * @title An Output Conduit for real-world assets (RWA).
 * @dev This contract differs from the original [RwaOutputConduit](https://github.com/makerdao/MIP21-RWA-Example/blob/fce06885ff89d10bf630710d4f6089c5bba94b4d/src/RwaConduit.sol#L41-L118):
 *  - The caller of `push()` is not required to hold MakerDAO governance tokens.
 *  - The `push()` method is permissioned.
 *  - `push()` permissions are managed by `mate()`/`hate()` methods.
 *  - `pick` whitelist are managed by `kiss() / diss()` methods.
 *  - Require PSM address in constructor
 *  - `pick` can be called to set `to` address. Address shoild be whitelisted be GOV.
 *  - The `push()` method swaps DAI to GEM using PSM and set `to` to zero address.
 *  - The `quit` method allows moving outstanding DAI balance to `quitTo`. It can be called only by the admin.
 *  - The `file` method allows updating `quitTo` addresses. It can be called only by the admin.
 */
contract RwaOutputConduit3 {
    /// @notice PSM GEM token contract address
    DSTokenAbstract public immutable gem;
    /// @notice PSM contract address
    PsmAbstract public immutable psm;
    /// @dev DAI/GEM decimal difference
    uint256 private immutable toGemConversionFactor;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with operator access on this contract. `can[usr]`
    mapping(address => uint256) public can;

    /// @dev This is declared here so the storage layout lines up with RwaOutputConduit.
    DSTokenAbstract private __unused_gov;
    /// @notice Dai token contract address
    DSTokenAbstract public dai;
    /// @notice Dai output address
    address public to;

    /// @dev Whitelist for addresses which can be picked.
    mapping(address => uint256) public bud;
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
     * @notice The conduit outstanding gem balance was flushed out to `quitTo` address.
     * @param quitTo The quitTo address.
     * @param wad The amount flushed out.
     */
    event Quit(address indexed quitTo, uint256 wad);

    /**
     * @notice Defines PSM and quitTo addresses and gives `msg.sender` admin access.
     * @param _psm PSM contract address.
     * @param _quitTo Address to where outstanding GEM balance will go after `quit`
     */
    constructor(address _psm, address _quitTo) public {
        DSTokenAbstract _gem = DSTokenAbstract(GemJoinAbstract(PsmAbstract(_psm).gemJoin()).gem());
        psm = PsmAbstract(_psm);
        gem = _gem;
        dai = DSTokenAbstract(PsmAbstract(_psm).dai());
        quitTo = _quitTo;

        uint256 gemDecimals = _gem.decimals();
        uint256 daiDecimals = dai.decimals();
        require(gemDecimals <= daiDecimals, "RwaOutputConduit3/invalid-gem-decimals");
        toGemConversionFactor = 10**(daiDecimals - gemDecimals);

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
     * @notice Whitelist `who` address for `pick`
     * @param who The user address.
     */
    function kiss(address who) public auth {
        bud[who] = 1;
        emit Kiss(who);
    }

    /**
     * @notice Remove `who` address from `pick` whitelist
     * @param who The user address.
     */
    function diss(address who) public auth {
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
            require(data != address(0), "RwaOutputConduit3/invalid-quit-to-address");
            quitTo = data;
        } else {
            revert("RwaOutputConduit3/unrecognised-param");
        }

        emit File(what, data);
    }

    /**
     * @notice Sets `who` address as the recipient. `who` address should be whitelisted using `kiss`
     * @param who Recipient Dai address.
     */
    function pick(address who) public isMate {
        require(bud[who] == 1 || who == address(0), "RwaOutputConduit3/not-bud");
        to = who;
        emit Pick(who);
    }

    /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    /**
     * @notice Method to swap DAI contract balance to GEM through PSM and push it to the recipient address.
     * @dev `msg.sender` must have been `mate`d and `to` must be setted.
     */
    function push() external isMate {
        require(to != address(0), "RwaOutputConduit3/to-not-picked");

        uint256 balance = dai.balanceOf(address(this));
        uint256 gemAmount = balance / toGemConversionFactor;
        require(gemAmount > 0, "RwaOutputConduit3/insufficient-swap-gem-amount");

        psm.buyGem(address(this), gemAmount);

        uint256 gemBalance = gem.balanceOf(address(this));
        gem.transfer(to, gemBalance);

        emit Push(to, gemBalance);
        to = address(0);
    }

    /**
     * @notice Method to swap DAI contract balance to GEM through PSM and push it to the recipient address.
     * @dev `msg.sender` must have been `mate`d and `to` must be setted.
     * @param wad Dai amount
     */
    function push(uint256 wad) external isMate {
        require(to != address(0), "RwaOutputConduit3/to-not-picked");

        uint256 balance = dai.balanceOf(address(this));
        require(balance >= wad, "RwaOutputConduit3/not-enough-dai");

        // We can lose some dust there. For exm: USDC has 6 dec and DAI has 18
        uint256 gemAmount = wad / toGemConversionFactor;
        require(gemAmount > 0, "RwaOutputConduit3/insufficient-swap-gem-amount");

        psm.buyGem(address(this), gemAmount);

        uint256 gemBalance = gem.balanceOf(address(this));
        gem.transfer(to, gemBalance);

        emit Push(to, gemBalance);
        to = address(0);
    }

    /**
     * @notice Flushes out any DAI balance to `quitTo` address.
     * @dev `msg.sender` must first receive push acess through mate().
     */
    function quit() external isMate {
        uint256 wad = dai.balanceOf(address(this));

        dai.transfer(quitTo, wad);
        emit Quit(quitTo, wad);
    }

    /**
     * @notice Flushes out specific amount of DAI balance to `quitTo` address.
     * @dev `msg.sender` must first receive push acess through mate().
     * @param wad Dai amount
     */
    function quit(uint256 wad) external isMate {
        uint256 balance = dai.balanceOf(address(this));
        require(balance >= wad, "RwaOutputConduit3/not-enough-dai");

        dai.transfer(quitTo, wad);
        emit Quit(quitTo, wad);
    }
}
