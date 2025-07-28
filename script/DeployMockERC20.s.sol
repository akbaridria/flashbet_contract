// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/mock-tokens/MockERC20.sol";

contract HiveDeployment is Script {
    function run() public {
        vm.startBroadcast();
        MockERC20 usdToken = new MockERC20(msg.sender, msg.sender, "USD Coin", "USDC", 6);
        console.log("USDC Token deployed at:", address(usdToken));
        vm.stopBroadcast();
    }
}
