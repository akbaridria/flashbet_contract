// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/FlashBet.sol";

contract DeployFlashBet is Script {
    function run() external {
        // Replace with actual addresses and priceId
        address usdc = vm.envAddress("USDC_ADDRESS");
        address pyth = vm.envAddress("PYTH_ADDRESS");
        bytes32 priceId = vm.envBytes32("PRICE_ID");

        vm.startBroadcast();
        FlashBet flashBet = new FlashBet(usdc, pyth, priceId);
        vm.stopBroadcast();

        console.log("FlashBet deployed at:", address(flashBet));
    }
}
