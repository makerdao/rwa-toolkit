// SPDX-FileCopyrightText: © 2021 Lev Livnev <lev@liv.nev.org.uk>
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
import {VatAbstract} from "dss-interfaces/dss/VatAbstract.sol";
import {DaiAbstract} from "dss-interfaces/dss/DaiAbstract.sol";
import {PsmAbstract} from "dss-interfaces/dss/PsmAbstract.sol";
import {GemJoinAbstract} from "dss-interfaces/dss/GemJoinAbstract.sol";

/**
 * @author Lev Livnev <lev@liv.nev.org.uk>
 * @author Nazar Duchak <nazar@clio.finance>
 * @title An Input Conduit for real-world assets (RWA).
 * @dev This contract differs from the original [RwaInputConduit](https://github.com/makerdao/MIP21-RWA-Example/blob/fce06885ff89d10bf630710d4f6089c5bba94b4d/src/RwaConduit.sol#L20-L39):
 *  - Requires DAI, GEM and PSM addresses in the constructor.
 *      - DAI and GEM are immutable, PSM can be replaced as long as it uses the same DAI and GEM.
 *  - The caller of `push()` is not required to hold MakerDAO governance tokens.
 *  - The `push()` and `push(uint256)` methods are permissionless.
 *  - The `push()` method swaps entire GEM balance to DAI using PSM.
 *  - The `push(uint256)` method swaps specified amount of GEM to DAI using PSM.
 *  - The `file(bytes32, address)` method allows updating `to`, `psm` and `recovery` addresses. It can be called only by the admin.
 *  - There is a `recovery` address that will be allowed to pull GEM from this contract in case of Emergency Shutdown.
 *  - `push`, `yank` and `file` are disabled after Emergency Shutdown to prevent a potentially corrupt Governance contract from pulling funds from this contract.
 */
contract RwaSwapInputConduit2 {
    /// @notice MCD Vat module.
    VatAbstract public immutable vat;
    /// @notice PSM GEM token contract.
    GemAbstract public immutable gem;
    /// @notice DAI token contract.
    DaiAbstract public immutable dai;
    /// @dev DAI/GEM resolution difference.
    uint256 private immutable to18ConversionFactor;

    /// @notice Addresses with admin access on this contract. `wards[usr]`
    mapping(address => uint256) public wards;

    /// @notice PSM contract address.
    PsmAbstract public psm;
    /// @notice Recipient address for DAI.
    address public to;

    /// @notice Recovery address for `gem` after Emergency Shutdown.
    address public recovery;

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
     * @notice `wad` amount of Dai was pushed to `to`.
     * @param to Recipient address for DAI.
     * @param wad The amount of DAI.
     */
    event Push(address indexed to, uint256 wad);
    /**
     * @notice A contract parameter was updated.
     * @param what The changed parameter name. Currently the supported values are: "to", "psm".
     * @param data The new value of the parameter.
     */
    event File(bytes32 indexed what, address data);
    /**
     * @notice `amt` outstanding `token` balance was flushed out to `usr`.
     * @param token The token address.
     * @param usr The destination address.
     * @param amt The amount of `token` flushed out.
     */
    event Yank(address indexed token, address indexed usr, uint256 amt);

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaSwapInputConduit2/not-authorized");
        _;
    }

    /**
     * @notice Defines addresses and gives `msg.sender` admin access.
     * @param _vat MCD Vat module address.
     * @param _psm PSM contract address.
     * @param _dai DAI contract address.
     * @param _gem GEM contract address.
     * @param _to RwaUrn contract address.
     */
    constructor(
        address _vat,
        address _dai,
        address _gem,
        address _psm,
        address _to
    ) public {
        require(_to != address(0), "RwaSwapInputConduit2/invalid-to-address");
        require(PsmAbstract(_psm).dai() == _dai, "RwaSwapInputConduit2/wrong-dai-for-psm");
        require(GemJoinAbstract(PsmAbstract(_psm).gemJoin()).gem() == _gem, "RwaSwapInputConduit2/wrong-gem-for-psm");

        // We assume that DAI will alway have 18 decimals
        to18ConversionFactor = 10**_sub(18, GemAbstract(_gem).decimals());

        vat = VatAbstract(_vat);
        psm = PsmAbstract(_psm);
        dai = DaiAbstract(_dai);
        gem = GemAbstract(_gem);
        to = _to;

        // Give unlimited approval to PSM gemjoin
        GemAbstract(_gem).approve(address(psm.gemJoin()), type(uint256).max);

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

    /*//////////////////////////////////
               Administration
    //////////////////////////////////*/

    /**
     * @notice Updates a contract parameter.
     * @param what The changed parameter name. `"to"`, `"psm"`, `"recovery"`
     * @param data The new value of the parameter.
     */
    function file(bytes32 what, address data) external auth {
        require(vat.live() == 1, "RwaSwapInputConduit2/vat-not-live");

        if (what == "to") {
            to = data;
        } else if (what == "recovery") {
            recovery = data;
        } else if (what == "psm") {
            require(PsmAbstract(data).dai() == address(dai), "RwaSwapInputConduit2/wrong-dai-for-psm");
            require(
                GemJoinAbstract(PsmAbstract(data).gemJoin()).gem() == address(gem),
                "RwaSwapInputConduit2/wrong-gem-for-psm"
            );

            // Revoke approval for the old PSM gemjoin
            gem.approve(address(psm.gemJoin()), 0);
            // Give unlimited approval to the new PSM gemjoin
            gem.approve(address(PsmAbstract(data).gemJoin()), type(uint256).max);

            psm = PsmAbstract(data);
        } else {
            revert("RwaSwapInputConduit2/unrecognised-param");
        }

        emit File(what, data);
    }

    /*//////////////////////////////////
               Operations
    //////////////////////////////////*/

    /**
     * @notice Swaps the GEM balance of this contract into DAI through the PSM and push it into the recipient address.
     */
    function push() external {
        _doPush(gem.balanceOf(address(this)));
    }

    /**
     * @notice Swaps the specified amount of GEM into DAI through the PSM and push it into the recipient address.
     * @param amt Gem amount.
     */
    function push(uint256 amt) external {
        _doPush(amt);
    }

    /**
     * @notice Flushes out `amt` of `token` sitting in this contract to `usr` address.
     * @dev Can only be called by the admin.
     * @param token Token address.
     * @param usr Destination address.
     * @param amt Token amount.
     */
    function yank(
        address token,
        address usr,
        uint256 amt
    ) external auth {
        require(vat.live() == 1, "RwaSwapInputConduit2/vat-not-live");

        GemAbstract(token).transfer(usr, amt);
        emit Yank(token, usr, amt);
    }

    /**
     * @notice Calculates the amount of DAI received for swapping `amt` of GEM.
     * @param amt GEM amount.
     * @return wad Expected DAI amount.
     */
    function expectedDaiWad(uint256 amt) public view returns (uint256 wad) {
        uint256 amt18 = _mul(amt, to18ConversionFactor);
        uint256 fee = _mul(amt18, psm.tin()) / WAD;
        return _sub(amt18, fee);
    }

    /**
     * @notice Calculates the required amount of GEM to get `wad` amount of DAI.
     * @param wad DAI amount.
     * @return amt Required GEM amount.
     */
    function requiredGemAmt(uint256 wad) external view returns (uint256 amt) {
        return _mul(wad, WAD) / _mul(_sub(WAD, psm.tin()), to18ConversionFactor);
    }

    /**
     * @notice Swaps the specified amount of GEM into DAI through the PSM and push it into the recipient address.
     * @param amt GEM amount.
     */
    function _doPush(uint256 amt) internal {
        require(vat.live() == 1, "RwaSwapInputConduit2/vat-not-live");
        require(to != address(0), "RwaSwapInputConduit2/invalid-to-address");

        psm.sellGem(to, amt);
        emit Push(to, expectedDaiWad(amt));
    }

    /*//////////////////////////////////
             Emergency Shutdown
    //////////////////////////////////*/

    /**
     * @notice Allows the `recovery` address to pull GEM from this contract after Emergency Shutdown.
     * @dev This feature enables Dai holders to redeem any GEM tokens sitting in this contract as Emergency Shutdown happens.
     */
    function approveRecovery() external {
        require(vat.live() == 0, "RwaSwapInputConduit2/vat-still-live");
        require(recovery != address(0), "RwaSwapInputConduit2/recovery-not-set");

        gem.approve(recovery, type(uint256).max);
    }

    /*//////////////////////////////////
                    Math
    //////////////////////////////////*/

    uint256 internal constant WAD = 10**18;

    function _sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "Math/sub-overflow");
    }

    function _mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "Math/mul-overflow");
    }
}
