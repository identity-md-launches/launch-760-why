// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Why} from "../../src/Why.sol";

/// @dev Local test fixture only; models the immediate CREATE2 caller.
contract TokenFactory {
    function deploy(bytes32 salt) external returns (Why) {
        return new Why{salt: salt}();
    }
}
