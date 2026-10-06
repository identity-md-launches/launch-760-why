// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Why (WHY)
/// @notice Fixed-supply ERC-20: one billion tokens, with 18 decimals, minted to the deployer.
/// @dev No privileged roles, fees, post-construction minting, burning, or upgrade mechanism.
contract Why is ERC20 {
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice Assign the entire supply to the immediate creator (including a factory).
    constructor() ERC20("Why", "WHY") {
        _mint(msg.sender, INITIAL_SUPPLY);
    }
}
