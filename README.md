# HumanResources

A payroll contract implementing `IHumanResources` on Optimism. Salary accrues continuously in USD, including nights and weekends, at the weekly salary rate multiplied by elapsed seconds divided by `604800`.

## Interface implementation

| Function | Implementation |
| --- | --- |
| `registerEmployee(employee, weeklyUsdSalary)` | Manager only. Registers the employee, starts accrual, and defaults to USDC. Rehiring preserves unpaid salary, resets the preference, and starts a new employment period. Active duplicates revert. |
| `terminateEmployee(employee)` | Manager only. Records termination, stops accrual, and preserves unpaid salary for withdrawal. Unknown or already terminated employees revert. |
| `withdrawSalary()` | Current and former employees withdraw in their preferred currency. Accounting is updated before external transfers; failed payments revert. A zero payable balance returns without payment. |
| `switchCurrency()` | Active employees toggle USDC/ETH without withdrawing. Existing unpaid salary follows the new preference. |
| `salaryAvailable(employee)` | Returns unpaid salary in the preferred currency, using the current oracle price for ETH. Unknown addresses return zero. |
| `hrManager()` | Returns the manager fixed at construction. |
| `getActiveEmployeeCount()` | Returns the number of active employees, updated on registration and termination. |
| `getEmployeeInfo(employee)` | Returns weekly USD salary, latest registration time, and termination time (zero while active). Unknown addresses return three zeros. |

Actions emit the corresponding interface events and use the specified authorization and employee-state errors.

Salary inputs and internal accounting use 18 decimals. USDC salary views, payments, and withdrawal events use 6 decimals; ETH uses 18 decimals (wei). Fractions below one native USDC unit are retained for later payment.

## Oracle and AMM integration

The contracts are defined in `src/Util.sol`. Chainlink's ETH/USD answer and its decimal precision convert USD salary into an ETH estimate. For ETH payments, Uniswap V3 swaps USDC for WETH with a minimum output of 98% of that estimate, rounded upward. HR unwraps the WETH and sends native ETH. OpenZeppelin helpers handle token transfers, approvals, and ETH delivery.

The deployment script selects the available USDC/WETH pool with the greatest active liquidity among the common fee tiers, passes its fee to HR, and submits the deployed address. Deployment metadata is in `deployed-address.txt` and `submit-transaction.txt`.

## Build and test

Dependencies are included in `lib/`; Solidity is pinned to `0.8.38`. With Foundry installed:

```sh
forge build
forge test -vv
```

Alternatively, enter `nix develop` first to use the included development environment. Tests read `RPC_URL` from the root `.env` and fork Optimism at block `159584076`. The submission configuration is:

```dotenv
RPC_URL=https://mainnet.optimism.io
```
