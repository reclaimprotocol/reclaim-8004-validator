// SPDX-License-Identifier: MIT
// Vendored from @reclaimprotocol/verifier-solidity-sdk (pragma relaxed for Foundry compat)
pragma solidity >=0.8.4 <0.9.0;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./StringUtils.sol";

library Claims {
    struct CompleteClaimData {
        bytes32 identifier;
        address owner;
        uint32 timestampS;
        uint32 epoch;
    }

    struct ClaimInfo {
        string provider;
        string parameters;
        string context;
    }

    struct SignedClaim {
        CompleteClaimData claim;
        bytes[] signatures;
    }

    function assertValidSignedClaim(
        SignedClaim memory self,
        address[] memory expectedWitnessAddresses
    ) internal pure {
        require(self.signatures.length > 0, "No signatures");
        address[] memory signedWitnesses = recoverSignersOfSignedClaim(self);
        for (uint256 i = 0; i < expectedWitnessAddresses.length; i++) {
            bool found = false;
            for (uint256 j = 0; j < signedWitnesses.length; j++) {
                if (signedWitnesses[j] == expectedWitnessAddresses[i]) {
                    found = true;
                    break;
                }
            }
            require(found, "Missing witness signature");
        }
    }

    function recoverSignersOfSignedClaim(
        SignedClaim memory self
    ) internal pure returns (address[] memory) {
        bytes memory serialised = serialise(self.claim);
        address[] memory signers = new address[](self.signatures.length);
        for (uint256 i = 0; i < self.signatures.length; i++) {
            signers[i] = verifySignature(serialised, self.signatures[i]);
        }
        return signers;
    }

    function serialise(
        CompleteClaimData memory self
    ) internal pure returns (bytes memory) {
        return
            abi.encodePacked(
                StringUtils.bytes2str(abi.encodePacked(self.identifier)),
                "\n",
                StringUtils.address2str(self.owner),
                "\n",
                StringUtils.uint2str(self.timestampS),
                "\n",
                StringUtils.uint2str(self.epoch)
            );
    }

    function verifySignature(
        bytes memory content,
        bytes memory signature
    ) internal pure returns (address signer) {
        bytes32 signedHash = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                StringUtils.uint2str(content.length),
                content
            )
        );
        return ECDSA.recover(signedHash, signature);
    }

    function hashClaimInfo(
        ClaimInfo memory claimInfo
    ) internal pure returns (bytes32) {
        bytes memory serialised = abi.encodePacked(
            claimInfo.provider,
            "\n",
            claimInfo.parameters,
            "\n",
            claimInfo.context
        );
        return keccak256(serialised);
    }

    function extractFieldFromContext(
        string memory data,
        string memory target
    ) public pure returns (string memory) {
        bytes memory dataBytes = bytes(data);
        bytes memory targetBytes = bytes(target);
        require(dataBytes.length >= targetBytes.length, "target is longer than data");
        uint start = 0;
        bool foundStart = false;
        for (uint i = 0; i <= dataBytes.length - targetBytes.length; i++) {
            bool isMatch = true;
            for (uint j = 0; j < targetBytes.length && isMatch; j++) {
                if (dataBytes[i + j] != targetBytes[j]) {
                    isMatch = false;
                }
            }
            if (isMatch) {
                start = i + targetBytes.length;
                foundStart = true;
                break;
            }
        }
        if (!foundStart) { return ""; }
        uint end = start;
        while (
            end < dataBytes.length &&
            !(dataBytes[end] == '"' && dataBytes[end - 1] != "\\")
        ) { end++; }
        if (
            end <= start ||
            !(dataBytes[end] == '"' && dataBytes[end - 1] != "\\")
        ) { return ""; }
        bytes memory contextMessage = new bytes(end - start);
        for (uint i = start; i < end; i++) {
            contextMessage[i - start] = dataBytes[i];
        }
        return string(contextMessage);
    }
}
