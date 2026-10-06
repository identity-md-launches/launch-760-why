# Security review notes

The production change is a constructor-only specialization of the pinned
OpenZeppelin ERC20. Its only mint is internal and called during construction.
There is no callable mint/burn path or privileged control over holders. Token
operations update internal storage without external interactions, so there is no
callback or reentrancy surface. No proxy, delegatecall, selfdestruct, oracle,
randomness, signature verification, or arbitrary execution is used.

The exact supply is `10^27` minor units, well below the uint256 limit. The
inherited checked balance/allowance logic and guarded unchecked arithmetic
preserve supply; the WHY contract adds no custom transfer arithmetic. Metadata
and decimals are fixed by construction and the inherited implementation.

The supplied security reference was reviewed as background. Relevant cases are
covered by unit, fuzz, and stateful invariant tests, including unauthorized
spending, allowance rollback on failure, zero addresses, maximum amounts,
fee-free transfers, minting authority, and runtime opcode restrictions. Native
payments are tested as rejected; forced funds and accidental token transfers
have no recovery path.

Local validation uses `forge build`, `forge test`, and `forge fmt --check` with
Solidity 0.8.26. The dependencies are pinned and vendored for offline verification.
Slither, Mythril, a production-chain fork, and the external protected Uniswap
launch harness are not part of these local checks. Tests are not an independent
security audit. The release operator remains responsible for separate adversarial
review and launch integration verification before managing other people's funds.
