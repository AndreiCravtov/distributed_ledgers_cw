// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {HumanResources} from "@/HumanResources.sol";
import {IHumanResources} from "@/IHumanResources.sol";

contract HumanResourcesTest is Test {
    event ManagerAddress(address indexed addr);

    IHumanResources humanResources;

    function setUp() public {
        emit ManagerAddress(msg.sender);
        humanResources = new HumanResources(msg.sender);
    }

    // function test_Increment() public {
    //     counter.increment();
    //     assertEq(counter.number(), 1);
    // }

    // function testFuzz_SetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
