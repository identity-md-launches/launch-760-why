# Why (WHY)

WHY is an immutable, fixed-supply ERC-20 implemented in `src/Why.sol` using the
vendored OpenZeppelin Contracts v5.4.0 ERC20 implementation.

| Parameter | Value |
| --- | --- |
| Contract identifier | `src/Why.sol:Why` |
| Name / symbol | `Why` / `WHY` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; ABI encoding `0x`) |
| Deployment value | `0` |
| Initial recipient | Immediate deployer, `msg.sender` |
| Post-deployment initialization | None |

## Behavior and assumptions

The constructor mints the entire supply once and emits the standard
`Transfer(address(0), deployer, supply)` event. A factory deploying WHY receives
all tokens itself; the transaction origin or requester does not receive them
automatically. There is no external mint, burn, owner, pause, blacklist, seizure,
upgrade, fee, rebase, permit, or token-recovery function. Supply remains constant.

Transfers deliver their exact amount and return `true` on success. Zero-value
and self-transfers are supported. Invalid addresses, insufficient balances, and
insufficient allowances revert with OpenZeppelin ERC-20 custom errors. Transfers
to the zero address and approvals to the zero spender are rejected.

`approve` replaces the allowance; `transferFrom` consumes finite allowances.
An allowance of `type(uint256).max` is unlimited and is not reduced. `approve`
emits `Approval`; spending allowance does not emit a new `Approval` event in
this OpenZeppelin version. Integrators should read `allowance` when needed.
WHY makes no external calls during token operations and has no receiver callbacks.

## Build and check

Install Foundry and Solidity **0.8.26** in the build environment. All Solidity
dependencies and their licenses are ordinary files under `lib/`; no package
installation or submodule initialization is needed. `DEPENDENCIES.json` records
the upstream tags, exact commits, and SHA-256 hashes of all vendored files.

```sh
forge build
forge test
forge fmt --check
```

`foundry.toml` pins solc 0.8.26, the Cancun EVM target, optimizer enabled with
200 runs, and `bytecode_hash = "none"`. Deployment must target a chain supporting
Cancun. FFI and filesystem permissions are disabled. Once Foundry and the pinned
compiler are installed, builds and tests need no network, RPC, wallet, or
environment configuration.

Tests cover metadata, mint events, arbitrary deployers, CREATE2 factory receipt,
exact distributor and pool-address transfers, allowance replacement/revocation,
finite and unlimited allowances, event emission, zero/self/full-balance transfers,
invalid transfers and their rollback, absent privileged APIs, and forbidden
runtime opcodes. Fuzz tests use 256 cases each. A stateful invariant uses 128
sequences of 64 operations to check fixed supply, balance conservation, and an
independent allowance model. Each test constructs fresh state and uses no
environment-variable cheatcodes.

The local factory test models token transfers, not Uniswap initialization or
swaps. The supplied protected launch harness needs the network's factory/pool
contracts, resolved bytecode, and launch parameters; it is a separate integration
check and is not copied into this standalone project.

## Deployment and operational responsibilities

The constructor needs no chain addresses or linked libraries. A direct creator
uses `new Why()`; a CREATE2 creator uses `new Why{salt: salt}()`. Both receive the
whole supply. Creation bytecode and ABI can be inspected without sending a
transaction:

```sh
forge inspect src/Why.sol:Why bytecode
forge inspect src/Why.sol:Why abi
```

For the IdentityMD custom-token launch, the token metadata above is the input to
the network's separate manifest/deployment process. No application contracts are
required. The factory owns the initial supply and is responsible for the swarm
distribution, liquidity allocation, and requester remainder. These allocations
are not performed by WHY's constructor. The token has no exemptions because all
transfers already deliver the exact amount. The test's sample pool allocation is
only a fixture, not a proposed economic parameter.

The launch operator must supply and review the target chain, factory, pool
manager, paired currency, launch salt/number, pool parameters, economic parameters,
and recipient addresses in that separate process. None were specified here.
Before release, verify the built bytecode/settings, initial recipient, metadata,
total supply, and full launch/distributor/swap flow in the target environment;
after deployment, verify the source on the explorer. This project does not hold
keys or broadcast transactions.

The initial holder controls distribution, so custody of that holder is an
operational trust assumption. Subsequent holders control their balances and
allowances; the deployer has no special rights. Users should grant only needed
allowances and revoke obsolete approvals. When replacing a nonzero allowance,
first revoke it and confirm that transaction to reduce the standard ERC-20
approval race; already-authorized spending can still happen before revocation.

There is no administrator or recovery mechanism: mistaken transfers to WHY
itself or to inaccessible addresses cannot be recovered. Ordinary native-currency
payments revert, but native currency forcibly delivered to WHY is also
unrecoverable. No keepers, oracles, maintenance transactions, or ongoing minting
are needed. Contract changes require a new deployment.

See `SECURITY.md` for the review scope and validation limits.
