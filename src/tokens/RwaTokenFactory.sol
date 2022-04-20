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

import {RwaToken} from "./RwaToken.sol";

/**
 * @author Nazar Duchak <nazar@clio.finance>
 * @title A Factory for RWA Tokens.
 */
contract RwaTokenFactory {
    uint256 internal constant WAD = 10**18;

    /// @notice registry for RWA tokens. `tokenAddresses[symbol]`
    mapping(bytes32 => address) public tokenAddresses;
    /// @notice list of created RWA token symbols.
    bytes32[] public tokens;

    /**
     * @notice RWA Token created.
     * @param name Token name.
     * @param symbol Token symbol.
     * @param recipient Token address recipient.
     */
    event RwaTokenCreated(string name, string indexed symbol, address indexed recipient);

    /**
     * @notice Deploy an RWA Token and mint `1 * WAD` to recipient address.
     * @dev History of created tokens are stored in `tokenData` which is publicly accessible
     * @param name Token name.
     * @param symbol Token symbol.
     * @param recipient Recipient address.
     */
    function createRwaToken(
        string calldata name,
        string calldata symbol,
        address recipient
    ) public returns (RwaToken) {
        require(recipient != address(0), "RwaTokenFactory/recipient-not-set");
        require(bytes(name).length != 0, "RwaTokenFactory/name-not-set");
        require(bytes(symbol).length != 0, "RwaTokenFactory/symbol-not-set");

        bytes32 _symbol = stringToBytes32(symbol);
        require(tokenAddresses[_symbol] == address(0), "RwaTokenFactory/symbol-already-exists");

        RwaToken token = new RwaToken(name, symbol);
        tokenAddresses[_symbol] = address(token);
        tokens.push(_symbol);

        token.transfer(recipient, 1 * WAD);

        emit RwaTokenCreated(name, symbol, recipient);
        return token;
    }

    /**
     * @notice Gets the number of RWA Tokens created by this factory.
     */
    function count() external view returns (uint256) {
        return tokens.length;
    }

    /**
     * @notice Gets the list of symbols of all RWA Tokens created by this factory.
     */
    function list() external view returns (bytes32[] memory) {
        return tokens;
    }

    /**
     * @notice Helper function for converting string to bytes32.
     * @dev If `source` is longer than 32 bytes (i.e.: 32 ASCII chars), then it will be truncated.
     * @param source String to convert.
     * @return result The numeric ASCII representation of `source`, up to 32 chars long.
     */
    function stringToBytes32(string calldata source) public pure returns (bytes32 result) {
        bytes memory sourceAsBytes = bytes(source);
        if (sourceAsBytes.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(sourceAsBytes, 32))
        }
    }
}
