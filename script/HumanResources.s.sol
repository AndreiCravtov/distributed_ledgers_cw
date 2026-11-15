// SPDX-License-Identifier: GPL -3.0
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {HumanResources} from "@/HumanResources.sol";
import {IHumanResources} from "@/IHumanResources.sol";
import {Util} from "@/Util.sol";

interface SubmissionManager {
    event Submission(address indexed submitter, address indexed submission);

    function submit(address submission) external;
}

contract HumanResourcesScript is Script {
    event SenderAddr(address indexed addr);
    event PoolDiscovered(address indexed pool, uint24 indexed fee);

    address public constant HR_MANAGER = 0xD8dF905F4a6db962a6a07226E60467829C7342c7;
    SubmissionManager public constant SUBMISSION_MANAGER =
        SubmissionManager(0x1e767Af5D01be07FA0Aa4367d8473957e58FAc4E);

    IHumanResources public humanResources;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();

        emit SenderAddr(msg.sender);

        // Discover a USDC/WETH9 pool + its fee (use common fee ranges as candidates)
        uint24[] memory fees = new uint24[](4);
        fees[0] = 100;
        fees[1] = 500;
        fees[2] = 3000;
        fees[3] = 10000;
        (address pool, uint24 fee) = Util.discoverPoolFee_UsdcWeth9(fees);
        emit PoolDiscovered(pool, fee);

        // create contract and submit it (ensure HR manager is deployer)
        assert(msg.sender == HR_MANAGER);
        humanResources = new HumanResources(HR_MANAGER, fee);
        SUBMISSION_MANAGER.submit(address(humanResources));

        vm.stopBroadcast();
    }
}
