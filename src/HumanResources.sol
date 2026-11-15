// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {IHumanResources} from "./IHumanResources.sol";

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
    mapping(address => EmployeeInfo) private employees;
    uint256 private activeEmployeeCount;

    /// Creates an new HumanResources contract instance
    /// @param managerAddress address of the HR manager that will control this HR contract
    constructor(address managerAddress) {
        assert(managerAddress != address(0));
        manager = managerAddress;
    }

    /// @dev Throws if the sender is not the manager
    modifier onlyManager() {
        if (msg.sender != manager) {
            revert NotAuthorized();
        }
        _;
    }

    /// @dev Throws if the sender is not an employee
    modifier onlyEmployee() {
        if (!employees[msg.sender].exists) {
            revert NotAuthorized();
        }
        _;
    }

    /// Computes the accrued salary which was not already added to the salary total,
    /// from the timestamp the employee should be accruing salary.
    /// @param e the employee record
    function accruedSalary(EmployeeInfo memory e) internal view returns (uint256) {
        return ((block.timestamp - e.accrueFrom_sec) * e.weeklyUsdSalary_18x) / 1 weeks;
    }

    // HR manager functions
    // Only the address returned by the 'hrManager' below is able to call these functions
    // If anyone else tries to call them, the transaction must revert with the 'NotAuthorized' error above

    /// Registers an employee in the HR system
    /// @param employee address of the employee
    /// @param weeklyUsdSalary salary of the employee in USD scaled with 18 decimals
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external override onlyManager {
        // get employee
        assert(employee != address(0));
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
        assert(employee != address(0));
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
        emit EmployeeTerminated(employee);
    }

    // Employee functions
    // These are only be callabale by employees
    // If anyone else tries to call them, the transaction shall revert with the 'NotAuthorized' error above

    /// Withdraws the salary of the employee
    /// This sends either USDC or ETH to the employee, depending on the employee's preference
    /// The salary accumulates with time (regardless of nights, weekends, and other non working hours) according to the employee weekly salary
    function withdrawSalary() external override onlyEmployee {
        // ! ---- !
        // ! TODO !
        // ! ---- !
    }

    /// Switches the currency in which the employee receives the salary
    /// By default, the salary is paid in USDC
    /// If the employee calls this function, future salary payment will be in ETH
    /// If he calls it again, future salary payment will be in USDC again
    function switchCurrency() external override onlyEmployee {
        employees[msg.sender].prefersUsd = !employees[msg.sender].prefersUsd;
        emit CurrencySwitched(msg.sender, !employees[msg.sender].prefersUsd);
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

        return usdSalary_18x;
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
