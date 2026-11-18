// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IHumanResources} from "@/IHumanResources.sol";
import {Util} from "@/Util.sol";
import {TestUtil, EmployeeReceiver} from "./TestUtil.sol";

/// @notice Each test starts from the same Optimism block.
contract HumanResourcesTest is TestUtil {
    // Assumptions: ordinary funding with canonical Util.USDC.
    function test_FundThroughNormalUsdcTransfer() public {
        deal(address(Util.USDC), manager, 1000e6);
        vm.prank(manager);
        assertTrue(Util.USDC.transfer(address(hr), 1000e6));
        assertEq(Util.USDC.balanceOf(address(hr)), 1000e6);
        assertEq(Util.USDC.balanceOf(manager), 0);
    }

    // Contract setup and role management.
    function test_ManagerGetterIsPublic() public {
        vm.prank(outsider);
        assertEq(hr.hrManager(), manager);
    }

    function test_ManagerOnlyActionsAndErrorPrecedence() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        EmployeeSnapshot memory beforeState = _snapshotEmployeeState(alice);
        address[2] memory callers = [outsider, alice];
        for (uint256 i; i < callers.length; ++i) {
            vm.expectRevert(IHumanResources.NotAuthorized.selector);
            _registerEmployee(callers[i], bob, WEEKLY_SALARY_USD18);

            vm.expectRevert(IHumanResources.NotAuthorized.selector);
            _registerEmployee(callers[i], alice, 1);

            vm.expectRevert(IHumanResources.NotAuthorized.selector);
            _registerEmployee(callers[i], address(0), 1);

            vm.expectRevert(IHumanResources.NotAuthorized.selector);
            _terminateEmployee(callers[i], alice);

            vm.expectRevert(IHumanResources.NotAuthorized.selector);
            _terminateEmployee(callers[i], bob);
        }
        _assertEmployeeStateUnchanged(alice, beforeState);
        _assertEmployeeInfo(bob, 0, 0, 0);
        assertEq(hr.getActiveEmployeeCount(), 1);
    }

    function test_ManagerRemainsUnchanged() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        assertEq(hr.hrManager(), manager);
        _terminateEmployee(alice);
        assertEq(hr.hrManager(), manager);
        _registerEmployee(alice, 1400e18);
        assertEq(hr.hrManager(), manager);
    }

    // Registering and managing employees.
    function test_RegisterMetadataAndEvent() public {
        uint256 registeredAt = vm.getBlockTimestamp();

        vm.expectEmit(true, false, false, true, address(hr));
        emit EmployeeRegistered(alice, WEEKLY_SALARY_USD18);
        _registerEmployee(alice, WEEKLY_SALARY_USD18);

        _assertEmployeeInfo(alice, WEEKLY_SALARY_USD18, registeredAt, 0);
        assertEq(hr.getActiveEmployeeCount(), 1);
        assertEq(hr.salaryAvailable(alice), 0);
    }

    function test_DuplicateRegistrationPreservesState() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        EmployeeSnapshot memory beforeState = _snapshotEmployeeState(alice);

        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        _registerEmployee(alice, 1400e18);

        _assertEmployeeStateUnchanged(alice, beforeState);
        assertEq(hr.getActiveEmployeeCount(), 1);
    }

    function test_RehirePreservesDebtAndExcludesEmploymentGap() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        _terminateEmployee(alice);
        skip(1 weeks);
        uint256 rehiredAt = vm.getBlockTimestamp();
        vm.expectEmit(true, false, false, true, address(hr));
        emit EmployeeRegistered(alice, 1400e18);
        _registerEmployee(alice, 1400e18);
        _assertEmployeeInfo(alice, 1400e18, rehiredAt, 0);
        assertEq(hr.salaryAvailable(alice), 100e6);
        skip(1 days);
        assertEq(hr.salaryAvailable(alice), 300e6);
        deal(address(Util.USDC), address(hr), 1000e6);
        _withdrawSalaryAndAssertUsdcPayout(alice, 300e6);
    }

    function test_RehireResetsEthPreferenceToUsdc() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        _switchCurrency(alice);
        _terminateEmployee(alice);
        skip(1 weeks);
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        assertEq(hr.salaryAvailable(alice), 100e6);
        deal(address(Util.USDC), address(hr), 1000e6);
        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
    }

    function test_TerminationFreezesDebtAndEmitsEvent() public {
        uint256 registeredAt = vm.getBlockTimestamp();
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        uint256 terminatedAt = vm.getBlockTimestamp();

        vm.expectEmit(true, false, false, true, address(hr));
        emit EmployeeTerminated(alice);
        _terminateEmployee(alice);

        _assertEmployeeInfo(alice, WEEKLY_SALARY_USD18, registeredAt, terminatedAt);
        assertEq(hr.getActiveEmployeeCount(), 0);
        assertEq(hr.salaryAvailable(alice), 100e6);

        skip(1 weeks);
        assertEq(hr.salaryAvailable(alice), 100e6);
    }

    function test_UnknownAndRepeatedTerminationRevert() public {
        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        _terminateEmployee(alice);
        assertEq(hr.getActiveEmployeeCount(), 0);

        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        _terminateEmployee(alice);
        EmployeeSnapshot memory beforeState = _snapshotEmployeeState(alice);

        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        _terminateEmployee(alice);

        _assertEmployeeStateUnchanged(alice, beforeState);
        assertEq(hr.getActiveEmployeeCount(), 0);
    }

    function test_TerminatedEmployeeWithdrawsUsdc() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: false});
        _terminateEmployee(alice);
        skip(1 weeks);
        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
        assertEq(hr.salaryAvailable(alice), 0);
    }

    function test_TerminatedEmployeeWithdrawsEth() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: true});
        _terminateEmployee(alice);
        uint256 frozenEth = hr.salaryAvailable(alice);
        skip(1 weeks);
        assertEq(hr.salaryAvailable(alice), frozenEth);
        _withdrawSalaryAndAssertEthPayout(alice, 100e6);
        assertEq(hr.salaryAvailable(alice), 0);
    }

    // Accumulation, withdrawal, and currency switching.
    function test_AccrualAtSecondDayWeekAndPartialWeek() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        uint256 start = vm.getBlockTimestamp();
        uint256[4] memory elapsed = [uint256(1), 1 days, 1 weeks, 8 days];
        for (uint256 i; i < elapsed.length; ++i) {
            vm.warp(start + elapsed[i]);
            assertEq(hr.salaryAvailable(alice), WEEKLY_SALARY_USD18 * elapsed[i] / 1 weeks / USD18_PER_USDC_UNIT);
        }
    }

    function test_AccrualIncludesNightsAndWeekend() public {
        vm.warp(1730480400); // Friday 2024-11-01, 17:00 UTC.
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(64 hours);
        assertEq(hr.salaryAvailable(alice), WEEKLY_SALARY_USD18 * 64 / 168 / USD18_PER_USDC_UNIT);
    }

    function test_ActiveUsdcPayoutAndEvent() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: false});
        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
        assertEq(hr.salaryAvailable(alice), 0);

        skip(1 days);
        assertEq(hr.salaryAvailable(alice), 100e6);
    }

    function test_ActiveEthPayoutUsesRealSwapAndEvent() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: true});
        _withdrawSalaryAndAssertEthPayout(alice, 100e6);
        assertEq(hr.salaryAvailable(alice), 0);
    }

    function test_OutsiderWithdrawalChecksAuthorizationFirst() public {
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        _withdrawSalary(outsider);
        assertEq(Util.USDC.balanceOf(address(hr)), 0);
        assertEq(Util.USDC.balanceOf(outsider), 0);
        assertEq(hr.salaryAvailable(outsider), 0);
    }

    function test_ZeroAndRepeatedWithdrawalsDoNotPayOrEmit() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        deal(address(Util.USDC), address(hr), 1000e6);
        _withdrawSalaryAndAssertNoPayment(alice);

        skip(1 days);
        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
        _withdrawSalaryAndAssertNoPayment(alice);

        _switchCurrency(alice);
        _withdrawSalaryAndAssertNoPayment(alice);

        skip(1 days);
        _withdrawSalaryAndAssertEthPayout(alice, 100e6);
        _withdrawSalaryAndAssertNoPayment(alice);
    }

    function test_CallbackCannotWithdrawSalaryTwice() public {
        EmployeeReceiver receiver = new EmployeeReceiver({target: hr, rejectEthPayment: false});
        _prepareFundedOneDaySalary({employee: address(receiver), ethMode: true});

        uint256 paid = _withdrawSalaryAndAssertEthPayout(address(receiver), 100e6);

        assertEq(receiver.receiveCalls(), 1);
        assertEq(receiver.received(), paid);
        assertEq(hr.salaryAvailable(address(receiver)), 0);
        _withdrawSalaryAndAssertNoPayment(address(receiver));
    }

    function test_SwitchTwiceChangesViewsAndEmitsEvents() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        assertEq(hr.salaryAvailable(alice), 100e6);

        vm.expectEmit(true, false, false, true, address(hr));
        emit CurrencySwitched(alice, true);
        _switchCurrency(alice);
        assertEq(hr.salaryAvailable(alice), _expectedEthForUsd18(100e18));

        vm.expectEmit(true, false, false, true, address(hr));
        emit CurrencySwitched(alice, false);
        _switchCurrency(alice);
        assertEq(hr.salaryAvailable(alice), 100e6);
    }

    function test_OnlyActiveEmployeesCanSwitch() public {
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        _switchCurrency(outsider);

        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        _terminateEmployee(alice);
        EmployeeSnapshot memory beforeState = _snapshotEmployeeState(alice);

        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        _switchCurrency(alice);
        _assertEmployeeStateUnchanged(alice, beforeState);
    }

    function test_SwitchDoesNotPayAndOldDebtUsesNewCurrency() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: false});
        uint256 usdcBefore = Util.USDC.balanceOf(address(hr));
        uint256 ethBefore = alice.balance;

        vm.recordLogs();
        _switchCurrency(alice);

        _assertNoSalaryWithdrawnEvents(vm.getRecordedLogs());
        assertEq(Util.USDC.balanceOf(address(hr)), usdcBefore);
        assertEq(Util.USDC.balanceOf(alice), 0);
        assertEq(Util.WETH9.balanceOf(alice), 0);
        assertEq(alice.balance, ethBefore);
        assertEq(hr.salaryAvailable(alice), _expectedEthForUsd18(100e18));

        _withdrawSalaryAndAssertEthPayout(alice, 100e6);
    }

    function test_UnpaidSalaryRepricesAtCurrentOraclePrice() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);
        _switchCurrency(alice);

        _mockEthUsdPrice(2000e8);
        assertEq(hr.salaryAvailable(alice), 0.05 ether);

        _mockEthUsdPrice(4000e8);
        assertEq(hr.salaryAvailable(alice), 0.025 ether);

        _switchCurrency(alice);
        assertEq(hr.salaryAvailable(alice), 100e6);
    }

    // Real oracle and AMM integration.
    function test_ActualChainlinkAnswerAndDecimalScaling() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days + 1 seconds);
        _switchCurrency(alice);
        uint256 usd18 = WEEKLY_SALARY_USD18 * (1 days + 1 seconds) / 1 weeks;
        assertEq(hr.salaryAvailable(alice), _expectedEthForUsd18(usd18));
    }

    function test_AdverseOraclePriceRevertsRealSwapAndRollsBack() public {
        _prepareFundedOneDaySalary({employee: alice, ethMode: true});
        (, int256 actualPrice,,,) = Util.ETH_USDC.latestRoundData();
        assertGt(actualPrice, 0);
        // Halving ETH/USD doubles the expected ETH; the unchanged pool cannot meet the minimum.
        _mockEthUsdPrice(actualPrice / 2);
        PaymentSnapshot memory beforeState = _snapshotPaymentState(alice);

        vm.expectRevert(bytes("Too little received"));
        _withdrawSalary(alice);

        _assertPaymentStateUnchanged(alice, beforeState);
    }

    // Public views and independent employee records.
    function test_PublicSalaryViewsForKnownAndUnknownAddresses() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        skip(1 days);

        vm.prank(outsider);
        assertEq(hr.salaryAvailable(alice), 100e6);

        vm.prank(outsider);
        assertEq(hr.salaryAvailable(bob), 0);
    }

    function test_ActiveCountAndEmployeeIndependence() public {
        _assertActiveEmployeeCountAsOutsider(0);
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        _assertActiveEmployeeCountAsOutsider(1);
        _registerEmployee(bob, 1400e18);
        _assertActiveEmployeeCountAsOutsider(2);

        skip(1 days);
        EmployeeSnapshot memory bobBefore = _snapshotEmployeeState(bob);

        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        _registerEmployee(alice, 1);
        _assertActiveEmployeeCountAsOutsider(2);

        _terminateEmployee(alice);
        _assertActiveEmployeeCountAsOutsider(1);

        vm.expectRevert(IHumanResources.EmployeeNotRegistered.selector);
        _terminateEmployee(alice);
        _assertActiveEmployeeCountAsOutsider(1);

        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        _assertActiveEmployeeCountAsOutsider(2);
        _assertEmployeeStateUnchanged(bob, bobBefore);
        assertEq(hr.salaryAvailable(bob), 200e6);
    }

    function test_PublicMetadataForKnownAndUnknownAddresses() public {
        uint256 registeredAt = vm.getBlockTimestamp();
        _registerEmployee(alice, WEEKLY_SALARY_USD18);

        vm.prank(outsider);
        (uint256 salary, uint256 since, uint256 terminated) = hr.getEmployeeInfo(alice);
        assertEq(salary, WEEKLY_SALARY_USD18);
        assertEq(since, registeredAt);
        assertEq(terminated, 0);

        vm.prank(outsider);
        (salary, since, terminated) = hr.getEmployeeInfo(bob);
        assertEq(salary, 0);
        assertEq(since, 0);
        assertEq(terminated, 0);
    }

    // Payment failures, rounding, and arithmetic regressions.
    function test_RejectedEthRollsBackRealSwap() public {
        EmployeeReceiver receiver = new EmployeeReceiver({target: hr, rejectEthPayment: true});
        _prepareFundedOneDaySalary({employee: address(receiver), ethMode: true});
        PaymentSnapshot memory beforeState = _snapshotPaymentState(address(receiver));

        vm.expectRevert(bytes("Employee rejects ETH"));
        _withdrawSalary(address(receiver));

        _assertPaymentStateUnchanged(address(receiver), beforeState);
        assertEq(receiver.receiveCalls(), 0);
    }

    function test_InsufficientFundingPreservesDebtForBothCurrencies() public {
        _registerEmployee(alice, WEEKLY_SALARY_USD18);
        _registerEmployee(bob, WEEKLY_SALARY_USD18);
        _switchCurrency(bob);
        skip(1 days);

        address[2] memory employees = [alice, bob];
        for (uint256 i; i < employees.length; ++i) {
            PaymentSnapshot memory beforeState = _snapshotPaymentState(employees[i]);
            vm.expectRevert();
            _withdrawSalary(employees[i]);
            _assertPaymentStateUnchanged(employees[i], beforeState);
        }

        deal(address(Util.USDC), address(hr), 1000e6);
        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
        _withdrawSalaryAndAssertEthPayout(bob, 100e6);
    }

    function test_RemainderSurvivesPayoutAndAppearsAsEthDust() public {
        uint256 usd18Remainder = 123456789; // Less than one native USDC unit (1e12 USD18).
        _registerEmployee(alice, 100e18 + usd18Remainder);
        skip(1 weeks);
        deal(address(Util.USDC), address(hr), 1000e6);
        assertEq(hr.salaryAvailable(alice), 100e6);

        _withdrawSalaryAndAssertUsdcPayout(alice, 100e6);
        assertEq(hr.salaryAvailable(alice), 0);
        _withdrawSalaryAndAssertNoPayment(alice);

        _mockEthUsdPrice(2000e8);
        _switchCurrency(alice);
        uint256 expectedEthDust = usd18Remainder / 2000;
        assertEq(hr.salaryAvailable(alice), expectedEthDust);
    }

    function testFuzz_OrdinaryAccrualInBothCurrencies(uint96 rawSalary, uint32 rawElapsed) public {
        uint256 salary = bound(uint256(rawSalary), 0, 1_000_000e18);
        uint256 elapsed = bound(uint256(rawElapsed), 0, 52 weeks);
        _registerEmployee(alice, salary);
        skip(elapsed);
        uint256 usd18 = salary * elapsed / 1 weeks;
        assertEq(hr.salaryAvailable(alice), usd18 / USD18_PER_USDC_UNIT);
        _mockEthUsdPrice(2000e8);
        _switchCurrency(alice);
        assertEq(hr.salaryAvailable(alice), usd18 / 2000);
    }

    function test_LargeAccrualAvoidsIntermediateOverflow() public {
        uint256 salary = type(uint256).max / 2;
        _registerEmployee(alice, salary);
        skip(3 seconds);
        // Divide first and retain the remainder, independently avoiding overflow.
        uint256 usd18 = (salary / 1 weeks) * 3 + (salary % 1 weeks) * 3 / 1 weeks;
        assertEq(hr.salaryAvailable(alice), usd18 / USD18_PER_USDC_UNIT);
    }

    function test_LargeOracleConversionAvoidsIntermediateOverflow() public {
        uint256 usd18 = type(uint256).max / 1e8 + 1;
        _registerEmployee(alice, usd18);
        skip(1 weeks);
        _mockEthUsdPrice(2000e8);
        _switchCurrency(alice);
        assertEq(hr.salaryAvailable(alice), usd18 / 2000);
    }
}
