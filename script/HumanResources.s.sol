// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {HumanResources} from "../src/HumanResources.sol";
import {IHumanResources} from "../src/IHumanResources.sol";

interface SubmissionManager {
    event Submission(address indexed submitter, address indexed submission);

    function submit(address submission) external;
}

contract HumanResourcesScript is Script {
    event SenderAddr(address addr);

    address public constant HR_MANAGER = 0xD8dF905F4a6db962a6a07226E60467829C7342c7;
    SubmissionManager public constant SUBMISSION_MANAGER =
        SubmissionManager(0x1e767Af5D01be07FA0Aa4367d8473957e58FAc4E);

    IHumanResources public humanResources;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        // create contract and submit it (ensure HR manager is deployer)
        emit SenderAddr(msg.sender);
        assert(msg.sender == HR_MANAGER);
        humanResources = new HumanResources(HR_MANAGER);
        SUBMISSION_MANAGER.submit(address(humanResources));

        vm.stopBroadcast();
    }
}
