// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {HumanResources} from "@/HumanResources.sol";
import {IHumanResources} from "@/IHumanResources.sol";
import {Util} from "@/Util.sol";
import {AggregatorV3Interface} from "@chainlink/shared/interfaces/AggregatorV3Interface.sol";

/// @dev Used for a nested withdrawal attempt or a rejected ETH payment.
contract EmployeeReceiver {
    IHumanResources private immutable hr;
    bool private immutable rejectPayment;
    uint256 public receiveCalls;
    uint256 public received;

    constructor(IHumanResources target, bool rejectEthPayment) {
        hr = target;
        rejectPayment = rejectEthPayment;
    }

    receive() external payable {
        require(!rejectPayment, "Employee rejects ETH");
        receiveCalls++;
        received += msg.value;
        if (receiveCalls == 1) {
            // Either a successful no-op or an inner revert is safe; paying twice is not.
            try hr.withdrawSalary() {} catch {}
        }
    }
}

/// @dev Shared fork fixture and assertions for the HR specification tests.
abstract contract TestUtil is Test {
    struct EmployeeSnapshot {
        uint256 weeklyUsdSalary;
        uint256 employedSince;
        uint256 terminatedAt;
        uint256 availableSalary;
    }

    struct PaymentSnapshot {
        EmployeeSnapshot employee;
        uint256 hrUsdc;
        uint256 employeeUsdc;
        uint256 hrWeth;
        uint256 employeeWeth;
        uint256 hrEth;
        uint256 employeeEth;
        uint256 routerAllowance;
    }

    uint256 internal constant FORK_BLOCK = 159584076;
    uint256 internal constant WEEKLY_SALARY_USD18 = 700e18;
    uint256 internal constant USD18_PER_USDC_UNIT = 1e12;
    bytes32 internal constant WITHDRAWAL_EVENT = keccak256("SalaryWithdrawn(address,bool,uint256)");

    IHumanResources internal hr;
    address internal manager;
    address internal alice;
    address internal bob;
    address internal outsider;

    // After expectEmit, test-side emits define the expected HR event.
    event EmployeeRegistered(address indexed employee, uint256 weeklyUsdSalary);
    event EmployeeTerminated(address indexed employee);
    event CurrencySwitched(address indexed employee, bool isEth);

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("RPC_URL"), FORK_BLOCK);
        manager = makeAddr("coursework-hr-test-manager");
        alice = makeAddr("coursework-hr-test-alice");
        bob = makeAddr("coursework-hr-test-bob");
        outsider = makeAddr("coursework-hr-test-outsider");
        hr = new HumanResources(manager, 3000);
    }

    // Shared fixtures and assertions. Expected values do not call production Util helpers.
    function _registerEmployee(address employee, uint256 salary) internal {
        _registerEmployee(manager, employee, salary);
    }

    /// @dev Explicit caller overload for authorization tests.
    function _registerEmployee(address caller, address employee, uint256 salary) internal {
        vm.prank(caller);
        hr.registerEmployee(employee, salary);
    }

    function _terminateEmployee(address employee) internal {
        _terminateEmployee(manager, employee);
    }

    /// @dev Explicit caller overload for authorization tests.
    function _terminateEmployee(address caller, address employee) internal {
        vm.prank(caller);
        hr.terminateEmployee(employee);
    }

    function _switchCurrency(address employee) internal {
        vm.prank(employee);
        hr.switchCurrency();
    }

    function _withdrawSalary(address employee) internal {
        vm.prank(employee);
        hr.withdrawSalary();
    }

    function _prepareFundedOneDaySalary(address employee, bool ethMode) internal {
        _registerEmployee(employee, WEEKLY_SALARY_USD18);
        if (ethMode) _switchCurrency(employee);
        skip(1 days);
        deal(address(Util.USDC), address(hr), 1000e6);
    }

    function _expectedEthForUsd18(uint256 usd18) internal view returns (uint256) {
        (, int256 price,,,) = Util.ETH_USDC.latestRoundData();
        assertGt(price, 0);
        return usd18 * (10 ** Util.ETH_USDC.decimals()) / uint256(price);
    }

    function _mockEthUsdPrice(int256 price) internal {
        vm.mockCall(
            address(Util.ETH_USDC),
            abi.encodeCall(AggregatorV3Interface.latestRoundData, ()),
            abi.encode(uint80(1), price, vm.getBlockTimestamp(), vm.getBlockTimestamp(), uint80(1))
        );
    }

    function _assertEmployeeInfo(
        address employee,
        uint256 expectedWeeklyUsdSalary,
        uint256 expectedEmployedSince,
        uint256 expectedTerminatedAt
    ) internal view {
        (uint256 actualSalary, uint256 actualSince, uint256 actualTerminated) = hr.getEmployeeInfo(employee);
        assertEq(actualSalary, expectedWeeklyUsdSalary, "Weekly USD salary");
        assertEq(actualSince, expectedEmployedSince, "Employment start timestamp");
        assertEq(actualTerminated, expectedTerminatedAt, "Termination timestamp");
    }

    function _snapshotEmployeeState(address employee) internal view returns (EmployeeSnapshot memory state) {
        (state.weeklyUsdSalary, state.employedSince, state.terminatedAt) = hr.getEmployeeInfo(employee);
        state.availableSalary = hr.salaryAvailable(employee);
    }

    function _assertEmployeeStateUnchanged(address employee, EmployeeSnapshot memory beforeState) internal view {
        _assertEmployeeInfo(employee, beforeState.weeklyUsdSalary, beforeState.employedSince, beforeState.terminatedAt);
        assertEq(hr.salaryAvailable(employee), beforeState.availableSalary, "Available salary changed");
    }

    function _snapshotPaymentState(address employee) internal view returns (PaymentSnapshot memory state) {
        state.employee = _snapshotEmployeeState(employee);
        state.hrUsdc = Util.USDC.balanceOf(address(hr));
        state.employeeUsdc = Util.USDC.balanceOf(employee);
        state.hrWeth = Util.WETH9.balanceOf(address(hr));
        state.employeeWeth = Util.WETH9.balanceOf(employee);
        state.hrEth = address(hr).balance;
        state.employeeEth = employee.balance;
        state.routerAllowance = Util.USDC.allowance(address(hr), address(Util.UNISWAP_ROUTER));
    }

    function _assertPaymentStateUnchanged(address employee, PaymentSnapshot memory beforeState) internal view {
        _assertEmployeeStateUnchanged(employee, beforeState.employee);
        assertEq(Util.USDC.balanceOf(address(hr)), beforeState.hrUsdc, "HR USDC changed");
        assertEq(Util.USDC.balanceOf(employee), beforeState.employeeUsdc, "Employee USDC changed");
        assertEq(Util.WETH9.balanceOf(address(hr)), beforeState.hrWeth, "HR WETH changed");
        assertEq(Util.WETH9.balanceOf(employee), beforeState.employeeWeth, "Employee WETH changed");
        assertEq(address(hr).balance, beforeState.hrEth, "HR ETH changed");
        assertEq(employee.balance, beforeState.employeeEth, "Employee ETH changed");
        assertEq(
            Util.USDC.allowance(address(hr), address(Util.UNISWAP_ROUTER)),
            beforeState.routerAllowance,
            "Router allowance changed"
        );
    }

    function _assertActiveEmployeeCountAsOutsider(uint256 expected) internal {
        vm.prank(outsider);
        assertEq(hr.getActiveEmployeeCount(), expected, "Active employee count");
    }

    function _withdrawSalaryAndAssertUsdcPayout(address employee, uint256 amount) internal {
        uint256 hrBefore = Util.USDC.balanceOf(address(hr));
        uint256 employeeBefore = Util.USDC.balanceOf(employee);
        uint256 ethBefore = employee.balance;
        vm.recordLogs();
        _withdrawSalary(employee);
        _assertSalaryWithdrawnEvent(vm.getRecordedLogs(), employee, false, amount);
        assertEq(Util.USDC.balanceOf(address(hr)), hrBefore - amount, "HR USDC after payout");
        assertEq(Util.USDC.balanceOf(employee), employeeBefore + amount, "Employee USDC after payout");
        assertEq(employee.balance, ethBefore, "USDC payout must not send ETH");
    }

    /// @dev Checks the native USDC spent and returns the actual ETH received.
    function _withdrawSalaryAndAssertEthPayout(address employee, uint256 expectedUsdcSpent)
        internal
        returns (uint256 paid)
    {
        uint256 hrBefore = Util.USDC.balanceOf(address(hr));
        uint256 employeeUsdcBefore = Util.USDC.balanceOf(employee);
        uint256 employeeWethBefore = Util.WETH9.balanceOf(employee);
        uint256 ethBefore = employee.balance;
        uint256 expectedEth = _expectedEthForUsd18(expectedUsdcSpent * USD18_PER_USDC_UNIT);
        uint256 minimumEth = (expectedEth * 98 + 99) / 100; // 98% rounded upward.
        assertEq(address(hr).balance, 0, "Fixture starts without HR ETH");
        assertEq(Util.WETH9.balanceOf(address(hr)), 0, "Fixture starts without HR WETH");
        vm.recordLogs();
        _withdrawSalary(employee);
        paid = employee.balance - ethBefore;
        _assertSalaryWithdrawnEvent(vm.getRecordedLogs(), employee, true, paid);
        assertGt(paid, 0, "Employee receives ETH");
        assertGe(paid, minimumEth, "ETH payout meets oracle minimum");
        assertEq(Util.USDC.balanceOf(address(hr)), hrBefore - expectedUsdcSpent, "USDC spent on ETH payout");
        assertEq(Util.USDC.balanceOf(employee), employeeUsdcBefore, "ETH payout must not send USDC");
        assertEq(Util.WETH9.balanceOf(employee), employeeWethBefore, "ETH payout must not send WETH");
        assertEq(Util.WETH9.balanceOf(address(hr)), 0, "No WETH left after payout");
        assertEq(address(hr).balance, 0, "No ETH left after payout");
        assertEq(Util.USDC.allowance(address(hr), address(Util.UNISWAP_ROUTER)), 0, "Swap consumes allowance");
    }

    function _withdrawSalaryAndAssertNoPayment(address employee) internal {
        PaymentSnapshot memory beforeState = _snapshotPaymentState(employee);
        vm.recordLogs();
        _withdrawSalary(employee);
        _assertNoSalaryWithdrawnEvents(vm.getRecordedLogs());
        _assertPaymentStateUnchanged(employee, beforeState);
    }

    function _assertSalaryWithdrawnEvent(Vm.Log[] memory logs, address employee, bool isEth, uint256 amount)
        internal
        view
    {
        uint256 count;
        for (uint256 i; i < logs.length; ++i) {
            if (!_isSalaryWithdrawnLog(logs[i])) continue;
            assertEq(logs[i].topics.length, 2, "Withdrawal event topic count");
            assertEq(logs[i].topics[1], bytes32(uint256(uint160(employee))), "Withdrawal event employee");
            (bool actualIsEth, uint256 actualAmount) = abi.decode(logs[i].data, (bool, uint256));
            assertEq(actualIsEth, isEth, "Withdrawal event currency");
            assertEq(actualAmount, amount, "Withdrawal event amount");
            ++count;
        }
        assertEq(count, 1, "Exactly one SalaryWithdrawn event");
    }

    function _assertNoSalaryWithdrawnEvents(Vm.Log[] memory logs) internal view {
        for (uint256 i; i < logs.length; ++i) {
            assertFalse(_isSalaryWithdrawnLog(logs[i]), "Unexpected SalaryWithdrawn event");
        }
    }

    function _isSalaryWithdrawnLog(Vm.Log memory entry) private view returns (bool) {
        return entry.emitter == address(hr) && entry.topics.length > 0 && entry.topics[0] == WITHDRAWAL_EVENT;
    }
}
