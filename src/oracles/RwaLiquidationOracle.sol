// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RwaLiquidationOracle.sol -- Pricing data for RWA
//
// Copyright (C) 2020-2021 Lev Livnev <lev@liv.nev.org.uk>
// Copyright (C) 2021-2022 Dai Foundation
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

import {VatAbstract} from "dss-interfaces/dss/VatAbstract.sol";
import {DSValue} from "ds-value/value.sol";

contract RwaLiquidationOracle {
    // --- auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external auth {
        wards[usr] = 1;
        emit Rely(usr);
    }

    function deny(address usr) external auth {
        wards[usr] = 0;
        emit Deny(usr);
    }

    modifier auth() {
        require(wards[msg.sender] == 1, "RwaOracle/not-authorized");
        _;
    }

    // --- math ---
    function add(uint48 x, uint48 y) internal pure returns (uint48 z) {
        require((z = x + y) >= x);
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    VatAbstract public vat;
    address public vow;
    struct Ilk {
        string doc; // hash of borrower's agreement with MakerDAO
        address pip; // DSValue tracking nominal loan value
        uint48 tau; // pre-agreed remediation period
        uint48 toc; // timestamp when liquidation initiated
    }
    mapping(bytes32 => Ilk) public ilks;

    // Events
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, address data);
    event Init(bytes32 indexed ilk, uint256 val, string doc, uint48 tau);
    event Bump(bytes32 indexed ilk, uint256 val);
    event Tell(bytes32 indexed ilk);
    event Cure(bytes32 indexed ilk);
    event Cull(bytes32 indexed ilk, address indexed urn);

    constructor(address vat_, address vow_) public {
        vat = VatAbstract(vat_);
        vow = vow_;
        wards[msg.sender] = 1;
        emit Rely(msg.sender);
        emit File("vow", vow_);
    }

    // --- administration ---
    function file(bytes32 what, address data) external auth {
        if (what == "vow") {
            vow = data;
        } else revert("RwaOracle/unrecognised-param");
        emit File(what, data);
    }

    function init(
        bytes32 ilk,
        uint256 val,
        string calldata doc,
        uint48 tau
    ) external auth {
        // doc, and tau can be amended, but tau cannot decrease
        require(tau >= ilks[ilk].tau, "RwaOracle/decreasing-tau");
        ilks[ilk].doc = doc;
        ilks[ilk].tau = tau;
        if (ilks[ilk].pip == address(0)) {
            DSValue pip = new DSValue();
            ilks[ilk].pip = address(pip);
            pip.poke(bytes32(val));
        } else {
            val = uint256(DSValue(ilks[ilk].pip).read());
        }
        emit Init(ilk, val, doc, tau);
    }

    // --- valuation adjustment ---
    function bump(bytes32 ilk, uint256 val) external auth {
        DSValue pip = DSValue(ilks[ilk].pip);
        require(address(pip) != address(0), "RwaOracle/unknown-ilk");
        require(ilks[ilk].toc == 0, "RwaOracle/in-remediation");
        // only cull can decrease
        require(val >= uint256(pip.read()), "RwaOracle/decreasing-val");
        pip.poke(bytes32(val));
        emit Bump(ilk, val);
    }

    // --- liquidation ---
    function tell(bytes32 ilk) external auth {
        (, , , uint256 line, ) = vat.ilks(ilk);
        // DC must be set to zero first
        require(line == 0, "RwaOracle/nonzero-line");
        require(ilks[ilk].pip != address(0), "RwaOracle/unknown-ilk");
        ilks[ilk].toc = uint48(block.timestamp);
        emit Tell(ilk);
    }

    // --- remediation ---
    function cure(bytes32 ilk) external auth {
        require(ilks[ilk].pip != address(0), "RwaOracle/unknown-ilk");
        require(ilks[ilk].toc > 0, "RwaOracle/not-in-remediation");
        ilks[ilk].toc = 0;
        emit Cure(ilk);
    }

    // --- write-off ---
    function cull(bytes32 ilk, address urn) external auth {
        require(ilks[ilk].pip != address(0), "RwaOracle/unknown-ilk");
        require(block.timestamp >= add(ilks[ilk].toc, ilks[ilk].tau), "RwaOracle/early-cull");

        DSValue(ilks[ilk].pip).poke(bytes32(uint256(0)));

        (uint256 ink, uint256 art) = vat.urns(ilk, urn);
        require(ink <= 2**255, "RwaOracle/overflow");
        require(art <= 2**255, "RwaOracle/overflow");

        vat.grab(ilk, address(urn), address(this), address(vow), -int256(ink), -int256(art));
        emit Cull(ilk, urn);
    }

    // --- liquidation check ---
    // to be called by off-chain parties (e.g. a trustee) to check the standing of the loan
    function good(bytes32 ilk) external view returns (bool) {
        require(ilks[ilk].pip != address(0), "RwaOracle/unknown-ilk");
        // tell not called or still in remediation period
        return (ilks[ilk].toc == 0 || block.timestamp < add(ilks[ilk].toc, ilks[ilk].tau));
    }
}
