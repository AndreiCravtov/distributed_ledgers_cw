// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {IHumanResources} from "./IHumanResources.sol";

contract HumanResources is IHumanResources {
    // HR manager functions
    // Only the address returned by the 'hrManager' below is able to call these functions
    // If anyone else tries to call them, the transaction must revert with the 'NotAuthorized' error above

    /// Registers an employee in the HR system
    /// @param employee address of the employee
    /// @param weeklyUsdSalary salary of the employee in USD scaled with 18 decimals
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external override {}

    /// Terminates the contract of a given an employee.
    /// The salary of the employee will stop being accumulated.
    /// @param employee address of the employee
    function terminateEmployee(address employee) external override {}

    // Employee functions
    // These are only be callabale by employees
    // If anyone else tries to call them, the transaction shall revert with the 'NotAuthorized' error above

    /// Withdraws the salary of the employee
    /// This sends either USDC or ETH to the employee, depending on the employee's preference
    /// The salary accumulates with time (regardless of nights, weekends, and other non working hours) according to the employee weekly salary
    function withdrawSalary() external override {}

    /// Switches the currency in which the employee receives the salary
    /// By default, the salary is paid in USDC
    /// If the employee calls this function, future salary payment will be in ETH
    /// If he calls it again, future salary payment will be in USDC again
    function switchCurrency() external override {}

    // Views

    /// Returns the salary available for withdrawal for a given employee
    /// This returns the amount in the currency the employee prefers (USDC or ETH)
    /// The amount must be scaled with the correct number of decimals for the currency
    /// @param employee the address of the employee
    function salaryAvailable(address employee) external view override returns (uint256) {}

    /// Returns the address of the HR manager
    function hrManager() external view override returns (address) {}

    /// Returns the number of active employees registered in the HR system
    function getActiveEmployeeCount() external view override returns (uint256) {}

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
    {}
}
