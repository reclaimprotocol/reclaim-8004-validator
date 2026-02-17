// SPDX-License-Identifier: MIT
// Vendored from @reclaimprotocol/verifier-solidity-sdk (pragma relaxed for Foundry compat)
pragma solidity >=0.8.4 <0.9.0;

library Random {
	function random(uint256 seed) internal view returns (uint) {
		return uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, seed)));
	}
}
