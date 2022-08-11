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
import {PsmAbstract} from "dss-interfaces/dapp/PsmAbstract.sol";

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
 *  - The `push()` method swaps GEM to DAI using PSM
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

    /// @notice GEM token contract address (should ERC20 compliant)
    DSTokenAbstract public gem;
    /// @notice PSM contract address for the GEM
    PsmAbstract public psm;

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
     * @notice Define addresses and gives `msg.sender` admin access.
     * @param _dai Dai token contract address.
     * @param _to RwaUrn contract address.
     */
    constructor(address _dai, address _gem, address _psm, address _to) public {
        dai = DSTokenAbstract(_dai);
        gem = DSTokenAbstract(_gem);
        psm = PsmAbstract(_psm);
        to = _to;

        require(GemJoinAbstract(psm.gemJoin()).gem() == _gem, "RwaInputConduit3/wrong-gem-for-psm");

        wards[msg.sender] = 1;
        emit Rely(msg.sender);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaInputConduit3/not-authorized");
        _;
    }

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
     * @notice Internal method to pushes WAD amount of contract Dai balance into RwaUrn address.
     * @dev `msg.sender` must first receive push acess through mate().
     */
    function _swapAndPush(uint256 wad) internal {        
        // swap gem to dai through PSM and push it
        psm.sellGem(address(to), wad);

    }

    /**
     * @notice Method to swap WAD amount of USDC contract balance to DAI through PSM and push it into RwaUrn address.
     * @dev `msg.sender` must first receive push acess through mate().
     */
     function push(uint256 wad) public {
        require(may[msg.sender] == 1, "RwaInputConduit3/not-mate");
        uint256 balance = gem.balanceOf(address(this));
        require(balance >= wad, "RwaInputConduit3/insufficient-gem-balance");

        // swap gem to dai through PSM and push it
        psm.sellGem(address(to), wad);

        emit Push(to, wad);
    }

    /**
     * @notice Method to swap USDC contract balance to DAI through PSM and push it into RwaUrn address.
     * @dev `msg.sender` must first receive push acess through mate().
     */
     function push() public {
        require(may[msg.sender] == 1, "RwaInputConduit3/not-mate");
        uint256 balance = gem.balanceOf(address(this));
        require(balance > 0, "RwaInputConduit3/insufficient-gem-balance");

        // swap gem to dai through PSM and push it
        psm.sellGem(address(to), balance);

        emit Push(to, wad);
    }
}
