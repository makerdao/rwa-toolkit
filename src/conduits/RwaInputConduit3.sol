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
 * @author Kaue Cano <kaue@clio.finance>
 * @author Henrique Barcelos <henrique@clio.finance>
 * @author Nazar Duchak <nazar@clio.finance>
 * @title An Input Conduit for real-world assets (RWA).
 * @dev This contract differs from the original [RwaInputConduit](https://github.com/makerdao/MIP21-RWA-Example/blob/fce06885ff89d10bf630710d4f6089c5bba94b4d/src/RwaConduit.sol#L20-L39):
 *  - The caller of `push()` is not required to hold MakerDAO governance tokens.
 *  - The `push()` method is permissioned.
 *  - `push()` permissions are managed by `mate()`/`hate()` methods.
 *  - Require PSM address in constructor
 *  - The `push()` method swaps GEM to DAI using PSM
 *  - The `quit` method allows moving outstanding GEM balance to `quitAddress`. It can be called only by the admin.
 *  - The `file` method allows updating `quiteAddress`. It can be called only by the admin.
 */
contract RwaInputConduit3 {
    /// @dev This is declared here so the storage layout lines up with RwaInputConduit.
    DSTokenAbstract private __unused_gov;
    /// @notice Dai token contract address
    DSTokenAbstract public dai;
    /// @notice RWA urn contract address
    address public to;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;
    /// @notice Addresses with push access on this contract. `may[usr]`
    mapping(address => uint256) public may;

    /// @notice PSM GEM token contract address
    DSTokenAbstract immutable public gem;
    /// @notice PSM contract address
    PsmAbstract immutable public psm;
    /// @notice Exit address
    address public quitAddress;

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
     * @param what The changed parameter name. Currently the supported values are: "quitAddress".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice The conduit outstanding gem balance was flushed out to `exitAddress`.
     * @param quitAddress The quiteAddress address.
     * @param wad The amount flushed out.
     */
    event Quit(address indexed quitAddress, uint256 wad);

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaInputConduit3/not-authorized");
        _;
    }

    /**
     * @notice Define addresses and gives `msg.sender` admin access.
     * @param _psm PSM contract address.
     * @param _to RwaUrn contract address.
     * @param _quitAddress Address to where outstanding GEM balance will go after `quit`
     */
    constructor(address _psm, address _to, address _quitAddress) public {
        DSTokenAbstract _gem = DSTokenAbstract(GemJoinAbstract(PsmAbstract(_psm).gemJoin()).gem());
        psm = PsmAbstract(_psm);
        dai = DSTokenAbstract(PsmAbstract(_psm).dai());
        gem = _gem;
        to = _to;
        quitAddress = _quitAddress;

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
     * @param what The changed parameter name. `"quitAddress"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        if (what == "quitAddress") {
            require(data != address(0), "RwaInputConduit3/invalid-quit-address");
            quitAddress = data;
        } else {
            revert("RwaInputConduit3/unrecognised-param");
        }

        emit File(what, data);
    }

     /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    /**
     * @notice Method to swap USDC contract balance to DAI through PSM and push it into RwaUrn address.
     * @dev `msg.sender` must first receive push acess through mate().
     */
     function push() external {
        require(may[msg.sender] == 1, "RwaInputConduit3/not-mate");
        uint256 balance = gem.balanceOf(address(this));
        require(balance > 0, "RwaInputConduit3/insufficient-gem-balance");

        psm.sellGem(address(this), balance);

        uint256 daiBalance = dai.balanceOf(address(this));
        dai.transfer(to, daiBalance);

        emit Push(to, daiBalance);
    }

     /**
     * @notice Flushes out any GEM balance to `quitAddress` address.
     * @dev Can only be called by an admin.
     */
    function quit() external auth {
        uint256 wad = gem.balanceOf(address(this));

        gem.transfer(quitAddress, wad);
        emit Quit(quitAddress, wad);
    }
}
