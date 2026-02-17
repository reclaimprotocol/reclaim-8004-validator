// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13 <0.9.0;

import "forge-std/Script.sol";
import "../src/ReclaimValidator8004.sol";

contract DeployReclaimValidator8004 is Script {
    // Polygon Amoy addresses
    address constant RECLAIM_VERIFIER = 0xcd94A4f7F85dFF1523269C52D0Ab6b85e9B22866;
    address constant VALIDATION_REGISTRY = 0x8004C11C213ff7BaD36489bcBDF947ba5eee289B;
    address constant IDENTITY_REGISTRY = 0x8004ad19E14B9e0654f73353e8a0B600D46C2898;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        ReclaimValidator8004 validator = new ReclaimValidator8004(
            RECLAIM_VERIFIER,
            VALIDATION_REGISTRY,
            IDENTITY_REGISTRY
        );

        // Log the deployed address
        console.log("ReclaimValidator8004 deployed at:", address(validator));
        console.log("Reclaim Verifier:", RECLAIM_VERIFIER);
        console.log("Validation Registry:", VALIDATION_REGISTRY);
        console.log("Identity Registry:", IDENTITY_REGISTRY);

        vm.stopBroadcast();
    }
}
