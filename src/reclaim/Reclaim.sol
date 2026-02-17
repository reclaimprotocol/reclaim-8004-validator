// SPDX-License-Identifier: MIT
// Vendored from @reclaimprotocol/verifier-solidity-sdk (pragma relaxed for Foundry compat)
pragma solidity >=0.8.4 <0.9.0;

import "./Claims.sol";
import "./Random.sol";
import "./StringUtils.sol";
import "./BytesUtils.sol";

contract Reclaim {
	struct Witness {
		address addr;
		string host;
	}

	struct Epoch {
		uint32 id;
		uint32 timestampStart;
		uint32 timestampEnd;
		Witness[] witnesses;
		uint8 minimumWitnessesForClaimCreation;
	}

	struct Proof {
		Claims.ClaimInfo claimInfo;
		Claims.SignedClaim signedClaim;
	}

	Epoch[] public epochs;
	uint32 public epochDurationS;
	uint32 public currentEpoch;

	event EpochAdded(Epoch epoch);

	address public owner;

	constructor() {
		epochDurationS = 1 days;
		currentEpoch = 0;
		owner = msg.sender;
	}

	modifier onlyOwner() {
		require(owner == msg.sender, "Only Owner");
		_;
	}

	function fetchEpoch(uint32 epoch) public view returns (Epoch memory) {
		if (epoch == 0) {
			return epochs[epochs.length - 1];
		}
		return epochs[epoch - 1];
	}

	function fetchWitnessesForClaim(
		uint32 epoch,
		bytes32 identifier,
		uint32 timestampS
	) public view returns (Witness[] memory) {
		Epoch memory epochData = fetchEpoch(epoch);
		bytes memory completeInput = abi.encodePacked(
			StringUtils.bytes2str(abi.encodePacked(identifier)),
			"\n",
			StringUtils.uint2str(epoch),
			"\n",
			StringUtils.uint2str(epochData.minimumWitnessesForClaimCreation),
			"\n",
			StringUtils.uint2str(timestampS)
		);
		bytes memory completeHash = abi.encodePacked(keccak256(completeInput));

		Witness[] memory witnessesLeftList = epochData.witnesses;
		Witness[] memory selectedWitnesses = new Witness[](
			epochData.minimumWitnessesForClaimCreation
		);
		uint witnessesLeft = witnessesLeftList.length;

		uint byteOffset = 0;
		for (uint32 i = 0; i < epochData.minimumWitnessesForClaimCreation; i++) {
			uint randomSeed = BytesUtils.bytesToUInt(completeHash, byteOffset);
			uint witnessIndex = randomSeed % witnessesLeft;
			selectedWitnesses[i] = witnessesLeftList[witnessIndex];
			witnessesLeftList[witnessIndex] = epochData.witnesses[witnessesLeft - 1];
			byteOffset = (byteOffset + 4) % completeHash.length;
			witnessesLeft -= 1;
		}

		return selectedWitnesses;
	}

	function verifyProof(Proof memory proof) public view {
		require(proof.signedClaim.signatures.length > 0, "No signatures");
		Claims.SignedClaim memory signed = Claims.SignedClaim(
			proof.signedClaim.claim,
			proof.signedClaim.signatures
		);

		bytes32 hashed = Claims.hashClaimInfo(proof.claimInfo);
		require(proof.signedClaim.claim.identifier == hashed);

		Witness[] memory expectedWitnesses = fetchWitnessesForClaim(
			proof.signedClaim.claim.epoch,
			proof.signedClaim.claim.identifier,
			proof.signedClaim.claim.timestampS
		);
		address[] memory signedWitnesses = Claims.recoverSignersOfSignedClaim(signed);
		require(
			signedWitnesses.length == expectedWitnesses.length,
			"Number of signatures not equal to number of witnesses"
		);

		for (uint256 i = 0; i < signed.signatures.length; i++) {
			bool found = false;
			for (uint j = 0; j < expectedWitnesses.length; j++) {
				if (signedWitnesses[i] == expectedWitnesses[j].addr) {
					found = true;
					break;
				}
			}
			require(found, "Signature not appropriate");
		}
	}

	function addNewEpoch(
		Witness[] calldata witnesses,
		uint8 requisiteWitnessesForClaimCreate
	) external onlyOwner {
		if (epochDurationS == 0) { epochDurationS = 1 days; }
		if (epochs.length > 0) {
			epochs[epochs.length - 1].timestampEnd = uint32(block.timestamp);
		}
		currentEpoch += 1;
		Epoch storage epoch = epochs.push();
		epoch.id = currentEpoch;
		epoch.timestampStart = uint32(block.timestamp);
		epoch.timestampEnd = uint32(block.timestamp + epochDurationS);
		epoch.minimumWitnessesForClaimCreation = requisiteWitnessesForClaimCreate;
		for (uint256 i = 0; i < witnesses.length; i++) {
			epoch.witnesses.push(witnesses[i]);
		}
		emit EpochAdded(epochs[epochs.length - 1]);
	}

	function uintDifference(uint256 a, uint256 b) internal pure returns (uint256) {
		if (a > b) { return a - b; }
		return b - a;
	}
}
