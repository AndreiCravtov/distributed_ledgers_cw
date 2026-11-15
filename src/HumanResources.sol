// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {IHumanResources} from "@/IHumanResources.sol";
import {Util} from "@/Util.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

/// @notice Represents the employee information for the HR contract
struct EmployeeInfo {
    /// Salary in USD, scaled by 18 decimal points
    uint256 weeklyUsdSalary_18x;
    /// Employee salary preference: USD or ETH
    bool prefersUsd;
    /// Status of the employee: active or terminated
    bool isActive;
    /// Does this employee exist or not
    bool exists;
    /// UNIX Timestamp from which to accrue salary
    uint256 accrueFrom_sec;
    /// Salary in USD, scaled by 18 decimal points
    uint256 usdSalary_18x;
    /// UNIX Timestamp from which the employee was registered/re-registered
    uint256 employedSince_sec;
    /// UNIX Timestamp from which the employee was terminated
    uint256 terminatedAt_sec;
}

/// @notice This contract implements the functions specified by the IHumanResources interface
/// The contract is able to register employees, terminate them, and allows employees to withdraw their salary
/// The contract is funded using only USDC but will pay the employees in USDC or ETH
contract HumanResources is IHumanResources {
    /// The manager of this HR contract
    address private manager;
    uint24 private _poolFee;
    mapping(address => EmployeeInfo) private employees;
    uint256 private activeEmployeeCount;

    /// Creates an new HumanResources contract instance
    /// @param managerAddress address of the HR manager that will control this HR contract
    /// @param poolFee the pool fee to use for swapping USDC to WETH9, for salary conversions
    constructor(address managerAddress, uint24 poolFee) {
        require(managerAddress != address(0), "Null address cannot be manager");
        manager = managerAddress;
        _poolFee = poolFee;
    }

    /// @dev Throws if the sender is not the manager
    modifier onlyManager() {
        if (msg.sender != manager) {
            revert NotAuthorized();
        }
        _;
    }

    receive() external payable {}

    /// Computes the accrued salary which was not already added to the salary total,
    /// from the timestamp the employee should be accruing salary.
    /// @param e the employee record
    function accruedSalary(EmployeeInfo memory e) internal view returns (uint256) {
        return Math.mulDiv(block.timestamp - e.accrueFrom_sec, e.weeklyUsdSalary_18x, 1 weeks);
    }

    // HR manager functions
    // Only the address returned by the 'hrManager' below is able to call these functions
    // If anyone else tries to call them, the transaction must revert with the 'NotAuthorized' error above

    /// Registers an employee in the HR system
    /// @param employee address of the employee
    /// @param weeklyUsdSalary salary of the employee in USD scaled with 18 decimals
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external override onlyManager {
        // get employee
        require(employee != address(0), "Cannot register null address as employee");
        EmployeeInfo memory e = employees[employee];

        // guard against adding already-active employees
        if (e.isActive) {
            revert EmployeeAlreadyRegistered();
        }

        // NOTE: accrued salary preserved
        e.weeklyUsdSalary_18x = weeklyUsdSalary;
        e.prefersUsd = true;
        e.isActive = true;
        e.exists = true;
        e.accrueFrom_sec = block.timestamp;
        e.employedSince_sec = block.timestamp;
        e.terminatedAt_sec = 0;

        // add new employee, or re-instate terminated employee
        employees[employee] = e;
        activeEmployeeCount += 1;
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    /// Terminates the contract of a given an employee.
    /// The salary of the employee will stop being accumulated.
    /// @param employee address of the employee
    function terminateEmployee(address employee) external override onlyManager {
        // get employee
        EmployeeInfo memory e = employees[employee];

        // guard against terminating non(-active) employees
        if (!e.isActive) {
            revert EmployeeNotRegistered();
        }

        // count accrued salary & disable accrual
        e.usdSalary_18x += accruedSalary(e);
        e.accrueFrom_sec = 0;
        e.isActive = false;
        e.terminatedAt_sec = block.timestamp;

        // perform termination
        employees[employee] = e;
        activeEmployeeCount -= 1;

        // Accrual logic above makes no external calls.
        // forge-lint: disable-next-line(reentrancy-events)
        emit EmployeeTerminated(employee);
    }

    // Employee functions
    // These are only be callabale by employees
    // If anyone else tries to call them, the transaction shall revert with the 'NotAuthorized' error above

    /// Withdraws the salary of the employee
    /// This sends either USDC or ETH to the employee, depending on the employee's preference
    /// The salary accumulates with time (regardless of nights, weekends, and other non working hours) according to the employee weekly salary
    function withdrawSalary() external override {
        EmployeeInfo memory e = employees[msg.sender];

        // both active and terminated employees can call this
        if (!e.exists) {
            revert NotAuthorized();
        }

        // if active employee: count accrued salary & update accrual timestamp
        if (e.isActive) {
            e.usdSalary_18x += accruedSalary(e);
            e.accrueFrom_sec = block.timestamp;
        }

        // get salary to withdraw + update stored salary/keep remainder
        (uint256 usdSalary, uint256 rem_x18) = Util.usdc18x_toNative(e.usdSalary_18x);
        if (usdSalary == 0) {
            // if no salary to withdraw, do nothing (as per spec)
            employees[msg.sender] = e;
            return;
        } else {
            e.usdSalary_18x = rem_x18;
        }

        employees[msg.sender] = e; // NOTE: do CEI pattern to prevent reentrancy attack

        // pay based on currency preference
        if (e.prefersUsd) {
            SafeERC20.safeTransfer(Util.USDC, msg.sender, usdSalary);

            // Accounting state already committed before transfer.
            // forge-lint: disable-next-line(reentrancy-events)
            emit SalaryWithdrawn(msg.sender, !e.prefersUsd, usdSalary); // TODO: check EdStem for scaling clarifications
        } else {
            // calculate minimum out based on spec percentage
            uint256 expectedEth_x18x = Util.usdcToEth_18x(Util.usdcNative_to18x(usdSalary));
            uint256 amountOutMinimum = Math.mulDiv(expectedEth_x18x, 98, 100, Math.Rounding.Ceil);

            // get WETH9 from the swap
            SafeERC20.forceApprove(Util.USDC, address(Util.UNISWAP_ROUTER), usdSalary);
            uint256 amountOut = Util.UNISWAP_ROUTER
                .exactInputSingle(
                    ISwapRouter.ExactInputSingleParams({
                        tokenIn: address(Util.USDC),
                        tokenOut: address(Util.WETH9),
                        fee: _poolFee,
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: usdSalary,
                        amountOutMinimum: amountOutMinimum,
                        sqrtPriceLimitX96: 0
                    })
                );
            require(amountOut >= amountOutMinimum, "Could not get minimum required amount of WETH9");

            // Unwrap the WETH9 and send ETH to employee
            Util.WETH9.withdraw(amountOut);
            Address.sendValue(payable(msg.sender), amountOut);

            // Accounting state already committed before transfer.
            // forge-lint: disable-next-line(reentrancy-events)
            emit SalaryWithdrawn(msg.sender, true, amountOut); // TODO: check EdStem for scaling clarifications
        }
    }

    /// Switches the currency in which the employee receives the salary
    /// By default, the salary is paid in USDC
    /// If the employee calls this function, future salary payment will be in ETH
    /// If he calls it again, future salary payment will be in USDC again
    function switchCurrency() external override {
        EmployeeInfo memory e = employees[msg.sender];

        // as per spec, only active employees allowed to call this
        if (!e.isActive) {
            revert NotAuthorized();
        }

        e.prefersUsd = !e.prefersUsd;
        employees[msg.sender] = e;
        emit CurrencySwitched(msg.sender, !e.prefersUsd);
    }

    // Views

    /// Returns the salary available for withdrawal for a given employee
    /// This returns the amount in the currency the employee prefers (USDC or ETH)
    /// The amount must be scaled with the correct number of decimals for the currency
    /// @param employee the address of the employee
    function salaryAvailable(address employee) external view override returns (uint256) {
        EmployeeInfo memory e = employees[employee];

        // guard against addresses never registered
        if (!e.exists) {
            return 0;
        }

        uint256 usdSalary_18x = e.usdSalary_18x;

        // active employees keep accruing, so add un-accrued value in calculation
        if (e.isActive) {
            usdSalary_18x += accruedSalary(e);
        }

        // salary preference
        if (e.prefersUsd) {
            // TODO: check EdStem for scaling clarifications
            return usdSalary_18x;
        } else {
            return Util.usdcToEth_18x(usdSalary_18x);
        }
    }

    /// Returns the address of the HR manager
    function hrManager() external view override returns (address) {
        return manager;
    }

    /// Returns the number of active employees registered in the HR system
    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }

    /// Returns information about an employee
    /// If the employee does not exist, the function does not revert but all values returned must be 0
    /// @param employee the address of the employee
    /// @return weeklyUsdSalary the weekly salary of the employee in USD, scaled with 18 decimals
    /// @return employedSince the timestamp at which the employee was registered
    /// @return terminatedAt the timestamp at which the employee was terminated (or 0 if the employee is still active)
    function getEmployeeInfo(address employee)
        external
        view
        override
        returns (uint256 weeklyUsdSalary, uint256 employedSince, uint256 terminatedAt)
    {
        EmployeeInfo memory e = employees[employee];

        // guard against addresses never registered
        if (!e.exists) {
            return (0, 0, 0);
        }

        return (e.weeklyUsdSalary_18x, e.employedSince_sec, e.terminatedAt_sec);
    }
}
