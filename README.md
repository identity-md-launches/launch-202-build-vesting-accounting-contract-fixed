# Vesting accounting

A standalone Solidity **0.8.24** / Foundry project for one immutable vesting schedule.
It records abstract units. It creates no token, holds no intended funds, and makes no
payments or external calls when units are claimed.

## Exact behavior

Constructor argument order:

```solidity
constructor(address beneficiary_, uint256 grant_, uint256 start_, uint256 cliff_, uint256 duration_)
```

- `beneficiary` is fixed and must be nonzero. It may be an EOA or a contract capable of calling `claim()`.
- `grant` is an integer number of abstract units, from zero through `2**256 - 1`. There are no implied decimals.
- `start` is a Unix timestamp in seconds. Past, present, and future starts are valid.
- `cliff` is an offset in seconds **from start**, not a timestamp. Zero is valid.
- `duration` is measured from start, must be positive, and must be at least `cliff`.
- `start + duration` must fit in uint256. This also guarantees that `start + cliff` fits.
- All schedule values are immutable. The deployment caller receives no administrative power.

For a timestamp `t`, vested units are:

```text
0                                  if t < start + cliff
grant                              if t >= start + duration
floor(grant * (t - start)/duration)  otherwise
```

The cliff delays availability; it does not restart the linear schedule. At the exact
cliff timestamp, the accumulated amount since start becomes available. If the cliff
equals the duration, the entire grant becomes available at the end. A zero cliff
starts the linear schedule immediately, with zero units at the exact start.
Rounding is always down; the exact end releases all remaining dust. Intermediate
multiplication uses full precision, so maximum grants and durations are supported.

Public interface:

| Function / getter | Meaning |
| --- | --- |
| `beneficiary()`, `grant()`, `start()`, `cliff()`, `duration()`, `end()` | Immutable schedule, with `end = start + duration` |
| `vestedAt(uint256 t)` | Vested amount at any supplied timestamp, independent of previous claims |
| `vested()` | `vestedAt(block.timestamp)` |
| `claimed()` | Cumulative units recorded as claimed |
| `claimable()` | `max(vested() - claimed, 0)` |
| `claim()` | Beneficiary-only; record all claimable units and return the amount |

A positive claim emits `Claimed(beneficiary, amount, totalClaimed)`. A zero claim
succeeds without changing state or emitting an event. Authorization is checked even
for zero claims. There are no partial claims, beneficiary transfers, revocation,
upgrades, owner privileges, or recovery functions. Repeated claims cannot increase
the cumulative total beyond the grant. Artificial backwards clock movement never
decreases `claimed`; `claimable` saturates at zero until vesting catches up.

Constructor failures use `InvalidBeneficiary`, `ZeroDuration`, `CliffBeyondDuration`,
or `TimestampOverflow`, in that validation order. Unauthorized claims use
`Unauthorized`. The constructor and all callable functions are nonpayable. Plain ETH
transfers and unknown selectors revert.

For example, grant `101`, start `1000`, cliff `3`, duration `7` yields zero through
timestamp `1002`, then `43` at `1003`, `57` at `1004`, `86` at `1006`, and exactly
`101` at `1007`. Claiming at each of `1003`, `1004`, and `1007` records `43`, `14`,
and `44`, respectively.

## Offline build and reproduction

Prerequisites: Foundry (`forge`; `cast` for deployment operations) and the official
Solidity `0.8.24+commit.e11b9ed9` compiler already installed in Foundry's compiler cache.
Validation used Forge 1.7.1, commit `4072e48705af9d93e3c0f6e29e93b5e9a40caed8`.
The toolchain is the only preinstalled dependency. No `forge install`, npm packages,
submodules, or fetched test libraries are needed.

```bash
forge build
forge test
forge fmt --check
```

`foundry.toml` sets `offline = true`, so these commands require no network. Equivalent
explicit commands are `forge build --offline` and `forge test --offline`. The compiler
is pinned by version, with Shanghai EVM, optimizer enabled at 200 runs, and no bytecode
metadata. FFI and filesystem permissions are disabled. The production full-precision
math source and its MIT license are included as ordinary files; see
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Tests define only the cheatcodes they
need locally.

In this assignment's environment the installed compiler cache is at
`/tmp/quorum-data/svm`, so the exact validation commands are:

```bash
SVM_HOME=/tmp/quorum-data/svm forge build --offline
SVM_HOME=/tmp/quorum-data/svm forge test --offline
forge fmt --check
```

Other environments should use their own installed compiler cache, not that temporary
path. No compiler executable or cache path is embedded in project configuration.

The default suite runs six fuzz tests with 1,000 cases each using seed
`0x56455354494e47`. To select a different reproducible seed:

```bash
forge test --offline --fuzz-runs 1000 --fuzz-seed 0x1234
```

The independent [reference model](test/support/ReferenceModel.sol) uses checked binary
long division, without importing production math, using assembly, or computing a
modular inverse. Full-width fuzzing compares it with the contract at random timestamps,
exact cliff/end boundaries, and interior times. Separate tests cross-check the model
against ordinary multiplication where the product fits in uint256. Sequence tests
make twelve advancing claims with immediate retries and a final end claim, checking
conservation against the model throughout.

Deterministic cases include zero/tiny grants, non-divisible durations, cliff zero and
cliff equal to duration, a one-second schedule, maximum valid start/end/cliff/grant/
duration, 512-bit intermediate products, authorization failures, invalid constructors,
events, nonpayable beneficiaries, rejected ETH, unsolicited balances, and backwards
test time. Deployment tests exercise the same constructor path as the script, its demo
arguments, rejection of mainnet, and a runtime size/forbidden-opcode scan.

## Sepolia deployment (ON)

Deployment is **ON** in [DemoConfig.sol](script/DemoConfig.sol) and
[deployment/sepolia.json](deployment/sepolia.json). The
[deployment script](script/DeploySepolia.s.sol) requires chain ID **11155111**, rejecting
mainnet and every other chain before any broadcast starts. It deploys exactly one
`VestingAccounting` instance using the tested constructor and the following fixed
demo parameters:

| Argument | Value |
| --- | --- |
| `beneficiary_` | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (public Anvil test account #1) |
| `grant_` | `1000003` abstract units |
| `start_` | `1800000000` (2027-01-15 08:00:00 UTC) |
| `cliff_` | `604800` seconds (7 days; cliff at 2027-01-22 08:00:00 UTC) |
| `duration_` | `2592000` seconds (30 days; end at 2027-02-14 08:00:00 UTC) |

The beneficiary is a deliberately public test identity; anyone with the standard
Anvil development credentials can claim its demo units. No private keys are included
or read by the script. The gas-paying deployer is a separate operator-supplied funded
Sepolia test account; it has no special authority over the deployed contract.
Unit tests use `0x000000000000000000000000000000000000bEEF` as a mocked beneficiary
and `0x000000000000000000000000000000000000cafE` as an unauthorized caller, using
Foundry impersonation with no real signatures or funds.

The full `run()` script was also exercised successfully in an offline local EVM,
using the public Anvil test account #0 as the simulated deployer:

```bash
SEPOLIA_DEPLOYER=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 \
  forge script script/DeploySepolia.s.sol:DeploySepolia --offline \
  --chain-id 11155111 --sender 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
```

Use the compiler-cache override above if needed. This command uses no RPC, signer,
or `--broadcast`; its returned address exists only in the local simulation.

**Deployment status: not broadcast.** This environment has no supplied Sepolia RPC,
funded deployment signer, or Foundry keystore. Thus there is currently no contract
address, deployment transaction hash, or explorer link to report. Those fields are
explicitly `null` in the deployment record. A local deployment test is not evidence
of a Sepolia transaction.

With an accessible RPC and a funded named Foundry test keystore, the operator can run
the following commands, replacing the public address/RPC/account placeholders. Provide
any keystore password through Foundry's interactive prompt, never through repository
files or command-line password arguments.

```bash
export SEPOLIA_RPC_URL='https://YOUR-SEPOLIA-RPC'
export SEPOLIA_DEPLOYER='0xYOUR_PUBLIC_DEPLOYER_ADDRESS'
export SEPOLIA_ACCOUNT='YOUR_SEPOLIA_TEST_KEYSTORE_NAME'

# Must output 11155111. The script independently enforces this constraint.
cast chain-id --rpc-url "$SEPOLIA_RPC_URL"

# Online simulation; no transaction is broadcast without --broadcast.
forge script script/DeploySepolia.s.sol:DeploySepolia \
  --rpc-url "$SEPOLIA_RPC_URL" --sender "$SEPOLIA_DEPLOYER"

# Actual Sepolia deployment, signed by the selected funded test account.
forge script script/DeploySepolia.s.sol:DeploySepolia \
  --rpc-url "$SEPOLIA_RPC_URL" --sender "$SEPOLIA_DEPLOYER" \
  --account "$SEPOLIA_ACCOUNT" --broadcast --slow
```

Offline compilation remains enabled during deployment; the RPC is used for simulation
and sending the transaction. `run()` reads only the public `SEPOLIA_DEPLOYER` address,
then uses `deployDemo()`, which is called directly by the offline tests. Tests never
read deployment environment variables or use `vm.setEnv`.

After broadcast, inspect
`broadcast/DeploySepolia.s.sol/11155111/run-latest.json` and confirm a successful receipt
on the RPC. Record its deployed `contractAddress` and deployment `transactionHash` in
`deployment/sepolia.json`; set `status` to `deployed`, clear `reason`, and add
`https://sepolia.etherscan.io/address/<contractAddress>` as `explorerLink` (the transaction
link is `https://sepolia.etherscan.io/tx/<deploymentTransactionHash>`). Do not fill these
fields from a simulation or a predicted address. Useful verification commands are:

```bash
cast receipt "$DEPLOYMENT_TX_HASH" --rpc-url "$SEPOLIA_RPC_URL"
cast code "$CONTRACT_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'beneficiary()(address)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'grant()(uint256)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'start()(uint256)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'cliff()(uint256)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'duration()(uint256)' --rpc-url "$SEPOLIA_RPC_URL"
cast call "$CONTRACT_ADDRESS" 'end()(uint256)' --rpc-url "$SEPOLIA_RPC_URL"

# ABI-encoded constructor arguments, including for explorer source verification:
cast abi-encode 'constructor(address,uint256,uint256,uint256,uint256)' \
  0x70997970C51812dc3A010C7d01b50e0d17dc79C8 1000003 1800000000 604800 2592000
```

## Assumptions, responsibilities, and incomplete checks

- The chain supplies the clock. Block timestamps have the chain's normal precision and
  ordering limits; this contract does not supply a wall-clock oracle. An account that
  loses access to the beneficiary cannot reassign it. Operators must check the schedule
  and beneficiary before deployment, keep control of any non-demo beneficiary, and pay
  gas for deployment and claims.
- A claim is only an accounting record. Any organization treating these units as an
  entitlement must implement and reconcile its own settlement outside this contract.
  Nothing here guarantees payment. There is no escrow, allowance, token, or withdrawal.
- Normal ETH deposits are rejected, but unsolicited ETH can still be forced onto any
  address. Such a balance is irrelevant to the schedule and cannot be recovered here.
  The balance test models this with `vm.deal`; it does not execute a self-destructing
  funding contract. Do not send assets to this contract.
- Fuzzing samples inputs; it is not exhaustive or a formal proof. The math oracle is
  structurally independent but remains test code. No independent security audit,
  fork test, live signer test, Sepolia receipt validation, or explorer source
  verification has been completed. The remaining deployment checks require the missing
  RPC and funded signer.
- The supplied pinned `Project.protected.t.sol` and `Token.protected.t.sol` are generic
  token/project-launch baseline inputs, compiled for 0.8.26 and requiring forge-std and
  launch environment variables. They specify no vesting API. They were read, left
  unchanged, and not counted as passing project tests. This task explicitly requires
  0.8.24 and no token, so no launch token or token-factory workflow is created. A local
  application runtime baseline is included, but it does not claim to replace any
  independent protected verifier.

Local evidence: `forge build --offline`, `forge test --offline`, and
`forge fmt --check` pass; the suite contains 30 tests with no skips. All submitted tests
and supporting source are outside `test/scratch/`.
