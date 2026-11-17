# HumanResources test plan

Follow [the specification](../70017_1_spec.pdf) in printed page order. **Only rows in a table headed Test / Covers / Scenario / Expected result are test cases.** Setup instructions, assumptions, coverage references, and manual submission tasks are labelled separately.

The core plan has **28 concrete cases**. Use shared helpers and add event assertions to the action tests; there is no need for a second set of event-only tests. Complete these before considering optional extras.

## Implemented suite and running it

[HumanResources.t.sol](HumanResources.t.sol) implements all 28 core cases and all five optional rows. X5 is split into two arithmetic regression tests, giving **34 test functions**, including one fuzz test with 256 runs. Function names contain the case IDs below. The source follows spec order, although Foundry sorts test output by function name.

[TestUtil.sol](TestUtil.sol) contains the shared fork setup, receiver contract, fixture state, and assertion helpers.

Run from the project root:

```sh
nix develop --command forge build
nix develop --command forge test -vv
```

Foundry reads `RPC_URL` from the root `.env`; `.env.example` provides the public submission value if the file needs recreating. An exported environment variable can override it for local runs. These fork tests need RPC access even when compiler artifacts are cached. `.env` is ignored by Git, so include it explicitly in the submission ZIP.

**Testing requirement assessment:** The suite covers all eight interface functions, successful actions, each specified access/state error, public views of unknown/terminated employees, all four events, and the clarified currency decimals. Fork cases exercise actual Optimism USDC transfers, Chainlink reads, Uniswap swaps, WETH unwrapping, ETH delivery, slippage rejection, and rollback. Callback, remainder, funding, fuzz, and overflow cases add a small set of edge cases. This meets the spec's stated test-suite requirements; final packaging and deployment checks remain the separate manual tasks below.

## General setup — instructions, not tests

- Use `test/HumanResources.t.sol`, one pinned Optimism fork, and manager, Alice, Bob, and outsider addresses.
- Read `RPC_URL` from `.env` with `vm.envString()`. The submission value should be `https://mainnet.optimism.io`.
- Block **159584076**, with pool fee **3000**, worked in the audit. Keep the block fixed for reproducibility.
- Deploy with the chosen manager. Use `vm.prank(manager)` for manager calls; the test contract's `msg.sender` is not necessarily the caller HR sees.
- Use `700e18/week` as the usual salary: one day earns `100e18` USD18. Use Forge `skip` and `deal` for time and funding; share contract-specific action and assertion helpers.
- Use canonical USDC at `0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85`. Foundry `deal(token, account, amount)` can supply fixture funds; A1 exercises a normal transfer into HR.
- Use Forge's inherited `skip(seconds)` for relative time advances. For absolute timestamps, use `vm.getBlockTimestamp()` around repeated `vm.warp()` calls; the aggressive optimizer can cache repeated `block.timestamp` expressions within a test transaction.
- Use the actual forked USDC, WETH, feed, and router. Only mock the oracle answer when a controlled price is needed. One small receiver helper is sufficient for the callback tests.
- In event assertions, check the HR emitter, indexed employee, currency flag where applicable, and amount. For ETH, record/decode the payout event and compare its amount with the recipient's ETH increase. Pool/router/token logs can coexist with HR logs.

### Staff clarifications — expectations used by the tests

Keep these confirmed units in one helper/constants area:

| Quantity | Current expectation |
| --- | --- |
| Weekly salary and internal USD | 18 decimals |
| `salaryAvailable()` in USDC / ETH mode | 6 / 18 decimals |
| Actual USDC / ETH payment | 6 / 18 decimals |
| `SalaryWithdrawn.amount` for USDC / ETH | 6 / 18 decimals |
| Counts and timestamps | Ordinary counts and Unix seconds |

**Rounding guidance:** Staff accepts retaining or discarding sub-USDC remainders. This implementation retains them internally: the USDC view truncates to 6 decimals, while the ETH view converts the full USD18 debt and may show dust after payment. ETH grading uses a small, unspecified tolerance; keep exact assertions for controlled oracle calculations and use the slippage bound for actual swap output. Preserve precision in intermediate calculations.

**Error guidance:** Additional custom errors, including library errors, are allowed. Where the spec requires a named error, assert that exact error and check authorization before other failure conditions. Incorporate these assertions into the access tests below.

## Assumptions and access clarification — pages 1–2

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| A1 — Fund HR with USDC | Funding by ordinary transfer; specified USDC version | Give the manager canonical USDC, then transfer `1000e6` from the manager to HR. | HR's USDC balance increases by exactly `1000e6`. |

**Fixture assumption:** One USD equals one USDC. No market-peg test is required.

**Coverage references:** Scaling is checked by registration, view, payment, and event assertions below. The access clarification is covered by 1B, 2G, 3D, 3G, and the public-view cases.

## 1. Contract setup and role management — page 2

**Setup instruction:** Use an `IHumanResources` reference and leave the supplied interface unchanged. Compilation checks interface compatibility; this is not a separate runtime test.

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 1A — Chosen manager | Constructor-set manager; public getter | Deploy with the manager address, then call `hrManager()` as an outsider. | Returns the chosen manager without reverting. |
| 1B — Manager-only actions | Registration/termination access; exact error and check order | As an outsider, attempt registration and termination. Repeat as a registered employee who is not manager. Include registration of an already-active employee and termination of an unknown address. | Every call reverts with `NotAuthorized`, taking precedence over employee-state errors; employee records/count remain unchanged. |
| 1C — Manager unchanged | Manager cannot change during normal operations | As manager, register, terminate, and re-register Alice; read `hrManager()` after each step. | Manager address is unchanged throughout. |

## 2. Registering and managing employees — page 2

### `registerEmployee`

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 2A — Register | USD18 salary input; registration metadata; registration event | Register Alice at `700e18`. | Salary `700e18`, `employedSince` equals registration time, `terminatedAt = 0`, active count `1`; emits `EmployeeRegistered(Alice, 700e18)`. |
| 2B — Duplicate registration | Already-active employee error | Register Alice again while she is active. | `EmployeeAlreadyRegistered`; salary, timestamps, and count are unchanged. |
| 2C — Rehire with unpaid debt | Rehire restarts accrual; gap earns nothing; unpaid debt survives | Alice earns one day at `700e18/week`, is terminated, waits a week, is rehired at `1400e18/week`, then works one day. Do not withdraw between periods. | USDC salary view is `300e6`; salary metadata is updated to `1400e18`; `employedSince` is the rehire time and `terminatedAt = 0`. |
| 2D — Rehire resets preference | Default USDC restored on re-registration | Alice earns a day, switches to ETH, is terminated and rehired, then immediately withdraws. | Her retained debt is shown as `100e6` in USDC mode and pays `100e6` USDC; no ETH payment. |

### `terminateEmployee`

**Coverage reference:** Manager-only termination is already tested in 1B.

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 2E — Terminate and freeze | Stop accrual; preserve debt; termination timestamp/event | Terminate Alice after one day; advance another week. | Emits `EmployeeTerminated(Alice)`; termination time is recorded; count becomes `0`; USDC salary view stays `100e6`. |
| 2F — Invalid termination | Unknown and already-terminated employee errors | Terminate an unknown address; also try terminating Alice twice. | Invalid calls revert with `EmployeeNotRegistered`; count remains correct. |
| 2G-USDC — Former employee withdraws USDC | Withdrawal after termination | Terminate Alice after one day's earnings, wait a week, then withdraw as Alice in USDC mode. | Pays `100e6` USDC with the correct withdrawal event; no gap accrual; remaining available balance is zero. |
| 2G-ETH — Former employee withdraws ETH | Withdrawal after termination in ETH mode | Switch Alice to ETH before terminating her after one day's earnings; wait a week and withdraw. | Pays ETH for only the earned `100e18` USD debt, meets the oracle minimum, emits the ETH withdrawal event, and clears the payable debt. |

**Coverage reference:** Preserving unpaid debt through rehire is already tested in 2C.

## 3. Salary accumulation and withdrawal — pages 2–3

### Accrual logic

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 3A — Seconds and weeks | Linear accrual over full and partial weeks; USDC view scaling | Register at `700e18/week`. Read after one second, one day, one week, and one week plus one day, without withdrawing between checkpoints. | Each USDC salary view equals `(700e18 * elapsed / 604800) / 1e12`, using integer division. |
| 3B — Overnight/weekend accrual | No working-hours or weekend exclusions | Register at a Friday 17:00 UTC fixture timestamp; advance 64 hours to Monday 09:00 UTC. | USDC salary view is `(700e18 * 64 / 168) / 1e12`, including all overnight and weekend hours. |

### `withdrawSalary`

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 3C-USDC — Active USDC payout | Default currency; native decimals; deduction/event | Fund HR, let active Alice earn one day, and withdraw without switching. | Alice gains `100e6` USDC; HR loses `100e6`; available salary becomes zero; emits one HR `SalaryWithdrawn(Alice, false, 100e6)`. |
| 3C-ETH — Active ETH payout | Preferred currency; real USDC swap; WETH unwrap; ETH/event | Fund HR with USDC only, switch Alice to ETH, let her earn a day, then withdraw through the real router. | HR spends `100e6` USDC; Alice gains ETH meeting the oracle minimum and gains no WETH; no payout WETH/ETH is left in HR; debt clears; the event records the actual ETH received. |
| 3D-access — Outsider withdrawal | Withdrawal restricted to current/former employees; auth check first | Call `withdrawSalary()` from a never-registered address while HR has no funds and that address has no salary. | Reverts with `NotAuthorized`, taking precedence over zero-salary or funding failures; no funds move. |
| 3D-zero — Zero and repeated withdrawal | No-payment behavior when nothing is payable | Withdraw immediately after registration. Separately, withdraw again immediately after a complete payout. | Current implementation returns without another payment; balances stay unchanged and no additional withdrawal event is emitted. |
| 3F — Callback withdrawal attempt | Reentrancy-safe ETH payment | Register a receiver contract that attempts one nested withdrawal from `receive()`; catch any inner revert so the outer payment can finish. | Original salary paid exactly once; no second payment or restored salary balance. |

**Coverage references:** The current oracle conversion is tested in 3I/4A and adverse swap pricing in 4C. The withdrawal-event and USDC-decimal requirements are assertions in 3C, not extra test functions.

### Currency switching

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 3G-toggle — Switch twice | USDC/ETH toggle and preference events | Active Alice switches USDC → ETH → USDC. | Views follow the selected currency; emits `CurrencySwitched(Alice, true)` then `CurrencySwitched(Alice, false)`. |
| 3G-access — Switching restrictions | Only active employees may switch | Attempt switching as an outsider and as a terminated employee. | Both revert with `NotAuthorized`. |
| 3H — Switch accumulated debt | No automatic withdrawal; old debt follows new preference | Accrue a day in default USDC mode, switch to ETH, then withdraw without advancing time. | Switching itself moves no funds and emits no withdrawal event; the next withdrawal pays the full previously earned debt in ETH. |
| 3I — Reprice unpaid salary | Current ETH price in views; internal USD accounting | Fix debt at `100e18` USD18; mock prices of $2,000 and $4,000 per ETH, reading the ETH view at each. Switch back to USDC without paying. | ETH views are `0.05 ether` and `0.025 ether`; USDC view is `100e6`. |

**Coverage references:** Default USDC is tested in 3C-USDC and preference reset in 2D. Test 4C changes the price before withdrawal to verify the payout protection also uses the current answer.

## 4. AMMs and oracles — pages 3–4

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 4A — Actual Chainlink conversion | Specified feed; oracle decimal scaling | At the pinned fork, read the actual ETH/USD feed's decimals and positive answer. Compare an ordinary employee's ETH salary view with an independent calculation. | View equals `USD18 * 10**feedDecimals / answer`. |
| 4C — Unfavorable swap pricing | Oracle protection; greater-than-2% shortfall reverts | With unpaid ETH-mode salary, mock only the oracle answer to half its real value, leaving the real pool unchanged. Capture balances and salary after installing the mock, then withdraw. | Swap reverts; available salary, HR/employee token and ETH balances, and router allowance equal their pre-call values. |

**Assertions to include in 3C-ETH (the Uniswap integration bullet):** Use the actual Optimism router, WETH, and native USDC contracts. Calculate the expected ETH from the USD value of USDC spent; check `paidEth >= ceil(expectedEth * 98 / 100)`. One validated fee tier is sufficient. Do not assert exact equality between AMM output and oracle estimate.

**Scope note:** The spec waives oracle freshness best practices. No freshness or sequencer test is needed for this plan.

## 5. Views and employee information — page 4

### `salaryAvailable`

**Coverage references:** Preferred-currency results are covered by 3C, 3G-toggle, and 4A. Frozen terminated balances before/after payment are covered by 2E/2G.

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 5A — Public salary views | Unknown address returns zero; unrestricted views | As an outsider, query an active employee's known accrued balance and a never-registered address. | Active balance is correct; unknown balance is zero; neither call is rejected. |

### `hrManager`

**Coverage reference:** 1A checks the public returned address; 1C checks it remains fixed.

### `getActiveEmployeeCount`

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 5B — Count across two employees | Active count; independent records | Register Alice, register Bob, terminate Alice, and rehire Alice. Include a failed duplicate registration and repeated termination at the relevant points. Read the count as an outsider. | Counts follow `0 → 1 → 2 → 1 → 2`; failed actions do not change them; Bob's record/debt remains correct. |

### `getEmployeeInfo`

**Coverage reference:** Exact salary and timestamps for active, terminated, and rehired employees are checked in 2A, 2E, and 2C.

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| 5C — Public employee metadata | Unknown record; unrestricted views | As an outsider, query Alice's known record and an address never registered. | Alice's values are correct; the unknown address returns `(0, 0, 0)`; neither call reverts. |

## 6. Events — page 4

**Coverage references, not additional tests:**

- `EmployeeRegistered`: 2A/2C; `EmployeeTerminated`: 2E; `SalaryWithdrawn`: 2G/3C; `CurrencySwitched`: 3G-toggle.
- These are the **four** interface events. Check their emitter and arguments in the corresponding action tests.
- Absence of a withdrawal event during switching is checked in 3H. Filter HR logs because swaps also emit token/router logs.
- Re-registration emits `EmployeeRegistered`; the automatic preference reset is not a separate employee toggle requiring another `CurrencySwitched` assertion.

## 7. Deployment and on-chain submission — page 4

**Manual/script tasks, not Solidity test cases:**

- Submit using the faucet-claiming wallet on Optimism and deploy without verification.
- Simulate the script with the correct sender/RPC and without `--broadcast`; inspect discovery, constructor arguments, and `submit(newHrAddress)`.
- After final deployment, check the submitted address and its manager, and ensure submitted source/compiler settings match the deployed version.

## Submission and testing requirements — pages 5–6

**Final review tasks, not extra test cases:**

- Confirm the action tests cover both successful and unauthorized/invalid calls.
- Retain the actual USDC/ETH and unfavorable-oracle tests as pinned fork tests reading the RPC from `.env`.
- Run `forge build` and `forge test` after extracting the final ZIP. Include dependencies, README, address, and submission transaction files; exclude private keys and `.git`.

**Reference note:** The interface listing on pages 7–8 repeats the covered functions; it does not call for a second suite.

## Optional extras — only after the direct spec cases pass

Pick a few if time remains. The full audit's large invariant campaigns are unnecessary here.

| Test | Covers | Scenario | Expected result |
| --- | --- | --- | --- |
| X1 — Rejected ETH | Payment failure rollback | Receiver contract rejects ETH after a real swap. | Withdrawal reverts; the preceding swap, salary deduction, and asset movements all roll back. |
| X2 — Insufficient funding | Debt survives a failed payment | Attempt payment with insufficient HR USDC; then fund HR and retry. | First attempt reverts without losing debt; retry pays successfully. |
| X3 — Remainder | Native-token rounding, repeated payouts, and accepted ETH dust | Earn `100e18 + 123456789` USD18. Without advancing time again, record the USDC view, withdraw twice, then switch to ETH with a mocked $2,000 price. | Initial USDC view is `100e6`; pays `100e6` once, retains `123456789` internally, then USDC view is zero and the second withdrawal pays nothing. The ETH view of the retained remainder is `123456789 / 2000 = 61728` wei. |
| X4 — Small accrual fuzz | Ordinary salary/time combinations | Fuzz ordinary salaries and elapsed times for about 256 cases. | USDC view matches independently calculated USD18 accrual divided by `1e12`; ETH view matches conversion of the full USD18 accrual. |
| X5 — Overflow regressions | Previously discovered arithmetic edge cases | Reuse the two short audit cases for a large representable accrual and USD-to-ETH conversion. | Correct representable results, without intermediate-overflow reverts. |

**Audit material to adapt:** `/tmp/hr-audit-v2-fork/test/ForkAudit.t.sol` has integration/rollback examples; `/tmp/hr-audit-v2-main/test/audit/Adversarial.t.sol` has the receiver helper; `/tmp/hr-audit-v2-state/test/WideAudit.t.sol` has arithmetic regressions. The saved audit ZIP also contains these harnesses if the temporary paths disappear. Copy only the small cases needed for this plan.
