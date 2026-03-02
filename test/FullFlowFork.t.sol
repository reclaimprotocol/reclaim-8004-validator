// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import "forge-std/Test.sol";
import "../src/ReclaimValidator8004.sol";
import "../src/reclaim/Reclaim.sol";
import "../src/reclaim/Claims.sol";
import "../src/reclaim/StringUtils.sol";

/// @title FullFlowForkTest
/// @notice Forks Polygon Amoy and exercises the complete ERC-8004 validation flow.
contract FullFlowForkTest is Test {
    // ── Live Amoy addresses ─────────────────────────────────────────────
    ReclaimValidator8004 constant validator =
        ReclaimValidator8004(0xe2056FA0661c7fCDE13E905D4240d27824ED249d);
    Reclaim constant reclaimVerifier =
        Reclaim(0xcd94A4f7F85dFF1523269C52D0Ab6b85e9B22866);
    address constant VALIDATION_REGISTRY = 0x8004C11C213ff7BaD36489bcBDF947ba5eee289B;
    address constant IDENTITY_REGISTRY   = 0x8004ad19E14B9e0654f73353e8a0B600D46C2898;
    address constant DEPLOYER            = 0x095FE93f3C1131f9d259468f0d3Fd6c736E83933;
    address constant RECLAIM_OWNER       = 0x3aF1D724044df4841fED6F8C35438f0cE6f3C7b9;

    uint256 constant AGENT_TOKEN_ID = 29;
    bytes32 constant AGENT_ID       = bytes32(uint256(29));

    // Test witness key-pair (Foundry/Anvil default #0)
    uint256 constant WITNESS_PK =
        0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    address witnessAddr;
    uint32 testEpoch;

    // ── setUp ───────────────────────────────────────────────────────────
    function setUp() public {
        vm.createSelectFork("https://rpc-amoy.polygon.technology");
        witnessAddr = vm.addr(WITNESS_PK);

        Reclaim.Witness[] memory w = new Reclaim.Witness[](1);
        w[0] = Reclaim.Witness({addr: witnessAddr, host: "test-witness.local"});
        vm.prank(RECLAIM_OWNER);
        reclaimVerifier.addNewEpoch(w, 1);
        testEpoch = reclaimVerifier.currentEpoch();

        vm.prank(DEPLOYER);
        validator.addProvider("http-test-provider");
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    function _sendValidationRequest(bytes32 tag) internal returns (bytes32 requestHash) {
        // Get the agent's validations count before the request
        (, bytes memory beforeData) = VALIDATION_REGISTRY.staticcall(
            abi.encodeWithSignature("getAgentValidations(uint256)", AGENT_TOKEN_ID)
        );

        vm.prank(DEPLOYER);
        (bool ok, ) = VALIDATION_REGISTRY.call(
            abi.encodeWithSignature(
                "validationRequest(address,uint256,string,bytes32)",
                address(validator),
                AGENT_TOKEN_ID,
                "ipfs://QmTestRequest",
                tag
            )
        );
        assertTrue(ok, "validationRequest call failed");

        // Get the agent's validations after the request to find the new requestHash
        (bool ok2, bytes memory afterData) = VALIDATION_REGISTRY.staticcall(
            abi.encodeWithSignature("getAgentValidations(uint256)", AGENT_TOKEN_ID)
        );
        assertTrue(ok2, "getAgentValidations call failed");

        // Decode the returned array to find the new requestHash
        // The return is an ABI-encoded dynamic array of uint256/bytes32
        emit log_named_bytes("beforeData", beforeData);
        emit log_named_bytes("afterData", afterData);

        // Decode as uint256[] and use the last element
        if (afterData.length > beforeData.length) {
            uint256[] memory validations = abi.decode(afterData, (uint256[]));
            requestHash = bytes32(validations[validations.length - 1]);
        } else {
            // Try decoding afterData regardless
            uint256[] memory validations = abi.decode(afterData, (uint256[]));
            require(validations.length > 0, "No validations found after request");
            requestHash = bytes32(validations[validations.length - 1]);
        }
    }

    function _buildTestProof() internal view returns (Reclaim.Proof memory) {
        Claims.ClaimInfo memory ci = Claims.ClaimInfo({
            provider:   "http-test-provider",
            parameters: '{"url":"https://example.com/api/verify","method":"GET"}',
            context:    '{"agentId":"29","test":"true"}'
        });
        Claims.CompleteClaimData memory cd = Claims.CompleteClaimData({
            identifier: Claims.hashClaimInfo(ci),
            owner:      DEPLOYER,
            timestampS: uint32(block.timestamp),
            epoch:      testEpoch
        });
        bytes memory sig = _signClaim(cd);
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = sig;
        return Reclaim.Proof({
            claimInfo: ci,
            signedClaim: Claims.SignedClaim({claim: cd, signatures: sigs})
        });
    }

    function _signClaim(Claims.CompleteClaimData memory c) internal pure returns (bytes memory) {
        bytes memory ser = abi.encodePacked(
            StringUtils.bytes2str(abi.encodePacked(c.identifier)),
            "\n",
            StringUtils.address2str(c.owner),
            "\n",
            StringUtils.uint2str(c.timestampS),
            "\n",
            StringUtils.uint2str(c.epoch)
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19Ethereum Signed Message:\n",
                StringUtils.uint2str(ser.length),
                ser
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(WITNESS_PK, digest);
        return abi.encodePacked(r, s, v);
    }

    function _submitProof(
        Reclaim.Proof memory proof,
        bytes32 requestHash,
        bytes32 tag
    ) internal {
        vm.prank(DEPLOYER);
        validator.validateWithProof(
            proof,
            requestHash,
            AGENT_ID,
            "ipfs://QmTestResponse",
            tag
        );
    }

    function _verifyProofVerifiedEvent(bytes32 requestHash) internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 sig = keccak256("ProofVerified(bytes32,bytes32,string,uint8)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (
                logs[i].topics.length >= 3 &&
                logs[i].topics[0] == sig &&
                logs[i].topics[1] == requestHash &&
                logs[i].topics[2] == AGENT_ID
            ) {
                return; // found
            }
        }
        revert("ProofVerified event not emitted");
    }

    // ── Full end-to-end test ────────────────────────────────────────────
    function testFullValidationFlow() public {
        bytes32 tag = keccak256("e2e-test");

        // STEP 1: Send validationRequest → get requestHash
        bytes32 requestHash = _sendValidationRequest(tag);
        emit log_named_bytes32("requestHash", requestHash);

        // STEP 2: Build cryptographically valid Reclaim proof
        Reclaim.Proof memory proof = _buildTestProof();

        // STEP 3: Submit proof through ReclaimValidator8004
        vm.recordLogs();
        _submitProof(proof, requestHash, tag);

        // STEP 4: Verify results
        assertTrue(validator.isRequestProcessed(requestHash), "request should be processed");

        uint256 ts = validator.getAgentProviderTimestamp(AGENT_ID, "http-test-provider");
        assertEq(ts, block.timestamp, "timestamp mismatch");

        assertTrue(validator.isProviderAllowed("http-test-provider"), "provider still allowed");

        _verifyProofVerifiedEvent(requestHash);

        // Check registry recorded the response
        (bool ok, bytes memory data) = VALIDATION_REGISTRY.staticcall(
            abi.encodeWithSignature("getValidationStatus(bytes32)", requestHash)
        );
        assertTrue(ok, "getValidationStatus should succeed");

        emit log("========================================");
        emit log("  FULL ERC-8004 VALIDATION FLOW: PASS  ");
        emit log("========================================");
        emit log_named_bytes32("  Request Hash  ", requestHash);
        emit log_named_uint  ("  Agent Token ID", AGENT_TOKEN_ID);
        emit log_named_uint  ("  Epoch         ", testEpoch);
        emit log_named_address("  Witness       ", witnessAddr);
        emit log_named_uint  ("  Timestamp     ", ts);
        emit log_named_bytes ("  Registry Data ", data);
    }

    // ── Test: replay prevention ─────────────────────────────────────────
    function testReplayPrevention() public {
        bytes32 tag = keccak256("replay-test");
        bytes32 requestHash = _sendValidationRequest(tag);

        Reclaim.Proof memory proof = _buildTestProof();

        // First call succeeds
        _submitProof(proof, requestHash, tag);

        // Second call with same requestHash reverts
        vm.expectRevert("Request already processed");
        vm.prank(DEPLOYER);
        validator.validateWithProof(proof, requestHash, AGENT_ID, "ipfs://r2", tag);
    }

    // ── Test: unknown provider reverts ──────────────────────────────────
    function testUnknownProviderReverts() public {
        Claims.ClaimInfo memory ci = Claims.ClaimInfo({
            provider: "unknown-provider", parameters: '{}', context: '{}'
        });
        Claims.CompleteClaimData memory cd = Claims.CompleteClaimData({
            identifier: Claims.hashClaimInfo(ci),
            owner: DEPLOYER,
            timestampS: uint32(block.timestamp),
            epoch: testEpoch
        });
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _signClaim(cd);

        Reclaim.Proof memory proof = Reclaim.Proof({
            claimInfo: ci,
            signedClaim: Claims.SignedClaim({claim: cd, signatures: sigs})
        });

        vm.expectRevert("Provider not allowed");
        vm.prank(DEPLOYER);
        validator.validateWithProof(proof, keccak256("x"), AGENT_ID, "", bytes32(0));
    }

    // ── Test: wrong proof owner reverts ─────────────────────────────────
    function testWrongProofOwnerReverts() public {
        Claims.ClaimInfo memory ci = Claims.ClaimInfo({
            provider: "http-test-provider", parameters: '{}', context: '{}'
        });
        Claims.CompleteClaimData memory cd = Claims.CompleteClaimData({
            identifier: Claims.hashClaimInfo(ci),
            owner: address(0xdead), // wrong owner
            timestampS: uint32(block.timestamp),
            epoch: testEpoch
        });
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _signClaim(cd);

        Reclaim.Proof memory proof = Reclaim.Proof({
            claimInfo: ci,
            signedClaim: Claims.SignedClaim({claim: cd, signatures: sigs})
        });

        vm.expectRevert("Proof owner != msg.sender");
        vm.prank(DEPLOYER);
        validator.validateWithProof(proof, keccak256("y"), AGENT_ID, "", bytes32(0));
    }
}
