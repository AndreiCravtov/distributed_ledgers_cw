# HumanResources

A Solidity payroll contract implementing the coursework `IHumanResources` interface on Optimism. The manager registers and terminates employees; employees withdraw continuously accrued salary in USDC or ETH.

## Recorded deployment

- Network: Optimism mainnet, chain ID `10`.
- HumanResources: `0x116C9778fa96454A99FD864dF145C58c52C15837`.
- HR manager: `0xD8dF905F4a6db962a6a07226E60467829C7342c7`.
- Selected USDC/WETH pool fee: `3000` (0.3%).
- Submission transaction: `0xf4284d0f3fd970b5f7c2b2bffc8f2cec5c5b09a6498444fb0743240c29158397`.

The root files `deployed-address.txt` and `submit-transaction.txt` contain the address and submission hash respectively.

## Interface implementation

| Function | Behavior |
| --- | --- |
| `registerEmployee(employee, weeklyUsdSalary)` | Manager only. Starts accrual, records the registration timestamp, defaults payment to USDC, and emits `EmployeeRegistered`. Active duplicates revert with `EmployeeAlreadyRegistered`. Rehiring preserves unpaid salary, excludes the employment gap, resets the currency, and records a new start timestamp. |
| `terminateEmployee(employee)` | Manager only. Accrues salary through the termination timestamp, freezes further accrual, decreases the active count, and emits `EmployeeTerminated`. Unknown or already terminated employees revert with `EmployeeNotRegistered`. |
| `withdrawSalary()` | Available to current and former employees. Pays accrued salary in the selected currency and emits `SalaryWithdrawn` with the actual payment amount. If no native USDC unit is payable, it returns without payment or a withdrawal event. |
| `switchCurrency()` | Active employees only. Toggles USDC/ETH and emits `CurrencySwitched`. It does not withdraw or alter the underlying USD debt. |
| `salaryAvailable(employee)` | Public view of accrued salary in the employee's preferred currency. Unknown addresses return zero. Terminated employees retain their frozen unpaid balance. ETH values use the current oracle answer. |
| `hrManager()` | Public getter for the manager fixed at construction. |
| `getActiveEmployeeCount()` | Public count of active employees. Termination decreases it and re-registration increases it. |
| `getEmployeeInfo(employee)` | Public getter for weekly USD salary, latest registration timestamp, and termination timestamp (zero while active). Unknown employees return `(0, 0, 0)`. |

Unauthorized restricted calls revert with `NotAuthorized`, before other validation. The manager and registered employee addresses must be nonzero.

Salary accrues linearly for all elapsed seconds, including nights and weekends: `elapsedSeconds * weeklyUsdSalary / 604800`. `Math.mulDiv` avoids intermediate multiplication overflow. Withdrawal commits accounting before external calls, preventing callbacks from withdrawing the same salary twice. Failed transfers or swaps revert the entire withdrawal.

## Units and rounding

| Value | Units |
| --- | --- |
| Salary inputs, internal USD debt, weekly salary metadata, registration event salary | USD with 18 decimals |
| USDC salary view, actual transfer, withdrawal event amount | USDC with 6 decimals |
| ETH salary view, actual transfer, withdrawal event amount | Wei, with 18 decimals |
| Counts and timestamps | Ordinary integers and Unix seconds |

Inputs are already scaled: pass `700e18` for $700 per week. One USD is assumed equal to one USDC, as stipulated by the coursework. Conversion to native USDC units truncates fractions below `1e-6` USDC; the remaining USD18 debt is retained for a later payment. The ETH view converts the full USD18 balance, so a small remainder may appear as ETH dust after a withdrawal. Accrual checkpoints truncate fractions below one USD18 unit.

## Oracle and AMM integration

`src/Util.sol` defines the Optimism contracts used:

| Contract | Address |
| --- | --- |
| Canonical USDC | `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85` |
| WETH9 | `0x4200000000000000000000000000000000000006` |
| Chainlink ETH/USD feed | `0x13e3Ee699D1909E989722E753853AE30b17e08c5` |
| Uniswap V3 swap router | `0xE592427A0AEce92De3Edee1F18E0157C05861564` |

The ETH/USD oracle answer is USD per ETH, scaled by the feed's `decimals()`. ETH wei are calculated as `usd18 * 10**feedDecimals / answer`; nonpositive answers revert. Oracle freshness checks are omitted as permitted by the coursework.

For an ETH withdrawal, HR approves only the native USDC amount needed, swaps it for WETH, unwraps the returned WETH, and sends ETH using OpenZeppelin `Address.sendValue`. USDC transfers and approvals use `SafeERC20`. The router's minimum output is 98% of the oracle estimate, rounded upward, enforcing the 2% shortfall limit. `sqrtPriceLimitX96 = 0` leaves the router's normal price range; the minimum output still protects the swap.

The deployment script examines fee tiers `100`, `500`, `3000`, and `10000`, chooses the available pool with the greatest active liquidity, and supplies its fee to the constructor. Salary withdrawals reuse that fee.

## Build and tests

The included Nix flake supplies Foundry and Solidity. From the project root:

```sh
nix develop
forge build
forge test -vv
```

Without Nix, use a compatible Foundry installation. Solidity is pinned to `0.8.38`, with the optimizer, via IR, and the Osaka EVM target configured in `foundry.toml`. Dependencies are included under `lib/`.

Foundry reads the root `.env`, which contains:

```dotenv
RPC_URL=https://mainnet.optimism.io
```

An exported `RPC_URL` can override this for local testing. The tests require RPC access and use Optimism block `159584076` for reproducibility.

`test/HumanResources.t.sol` contains 34 tests, including 256 fuzz runs, in specification order. `test/TestUtil.sol` holds shared fixtures and assertions. The suite covers interface behavior, required errors, all four events, units, real USDC transfers and ETH swaps, exact router minimum output, adverse pricing, callback withdrawal attempts, rollback, retained remainders, and overflow regressions. `test/test_plan.md` maps the scenarios to the specification.

## Deployment workflow

`script/HumanResources.s.sol` discovers the pool, deploys HR, and calls `submit(newHrAddress)` on `0x1e767Af5D01be07FA0Aa4367d8473957e58FAc4E`. It checks that the sender is the configured manager. Use the same wallet that claimed the coursework faucet funds. Do not verify the contract.

To simulate with the existing account, after exporting `RPC_URL`:

```sh
forge script script/HumanResources.s.sol:HumanResourcesScript --rpc-url "$RPC_URL" --account metamask_main -vvvv
```

Adding `--broadcast` deploys and submits; the command above only simulates. After a future deployment, update both root metadata files and keep the submitted production source and compiler settings consistent with that deployment.

The submission ZIP must explicitly include `.env` and the full dependency contents under `lib/`; `.env` is Git-ignored. Exclude Git metadata, local credentials, `.envrc`, and unnecessary build/cache files.
