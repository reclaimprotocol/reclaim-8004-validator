// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

import "./reclaim/Reclaim.sol";
import "./reclaim/Claims.sol";

/// @notice ERC-8004 Validation Registry interface (only the function we call).
interface IValidationRegistry {
    function validationResponse(
        bytes32 requestHash,
        uint8 response,
        string calldata responseUri,
        bytes32 responseHash,
        bytes32 tag
    ) external;
}

/// @notice ERC-8004 Identity Registry interface (only the function we call).
interface IIdentityRegistry {
    function ownerOf(bytes32 agentId) external view returns (address);
}

/// @title ReclaimValidator8004
/// @notice Verifies Reclaim ZK proofs on-chain and posts results to the ERC-8004 Validation Registry.
contract ReclaimValidator8004 {
    // ---------------------------------------------------------------
    // State
    // ---------------------------------------------------------------
    address public owner;
    Reclaim public reclaimVerifier;
    IValidationRegistry public validationRegistry;
    IIdentityRegistry public identityRegistry;

    /// @notice provider hash => allowed
    mapping(bytes32 => bool) public allowedProviders;

    /// @notice requestHash => true once used (replay prevention)
    mapping(bytes32 => bool) public processedRequests;

    /// @notice agentId => providerHash => last validation timestamp
    mapping(bytes32 => mapping(bytes32 => uint256)) public agentProviderTimestamp;

    // ---------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------
    event ProofVerified(
        bytes32 indexed requestHash,
        bytes32 indexed agentId,
        string provider,
        uint8 response
    );
    event ProviderAllowed(string provider, bytes32 providerHash);
    event ProviderRemoved(string provider, bytes32 providerHash);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    // ---------------------------------------------------------------
    // Modifiers
    // ---------------------------------------------------------------
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------
    constructor(
        address _reclaimVerifier,
        address _validationRegistry,
        address _identityRegistry
    ) {
        owner = msg.sender;
        reclaimVerifier = Reclaim(_reclaimVerifier);
        validationRegistry = IValidationRegistry(_validationRegistry);
        identityRegistry = IIdentityRegistry(_identityRegistry);
    }

    // ---------------------------------------------------------------
    // Admin
    // ---------------------------------------------------------------
    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Zero address");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function addProvider(string calldata provider) external onlyOwner {
        bytes32 h = keccak256(abi.encodePacked(provider));
        allowedProviders[h] = true;
        emit ProviderAllowed(provider, h);
    }

    function removeProvider(string calldata provider) external onlyOwner {
        bytes32 h = keccak256(abi.encodePacked(provider));
        allowedProviders[h] = false;
        emit ProviderRemoved(provider, h);
    }

    // ---------------------------------------------------------------
    // Core: verify proof & post validation response
    // ---------------------------------------------------------------

    /// @notice Verify a Reclaim proof and post the result to the ERC-8004 Validation Registry.
    /// @param proof        The Reclaim proof (claimInfo + signedClaim).
    /// @param requestHash  The ERC-8004 request hash this validation responds to.
    /// @param agentId      Identifier of the agent requesting validation.
    /// @param responseUri  URI pointing to off-chain evidence / metadata.
    /// @param tag          Arbitrary tag for the validation response.
    function validateWithProof(
        Reclaim.Proof calldata proof,
        bytes32 requestHash,
        bytes32 agentId,
        string calldata responseUri,
        bytes32 tag
    ) external {
        // 1. Replay prevention
        require(!processedRequests[requestHash], "Request already processed");
        processedRequests[requestHash] = true;

        // 2. Provider allow-list check
        bytes32 providerHash = keccak256(abi.encodePacked(proof.claimInfo.provider));
        require(allowedProviders[providerHash], "Provider not allowed");

        // 3. Proof ownership: the proof must belong to the caller
        require(
            proof.signedClaim.claim.owner == msg.sender,
            "Proof owner != msg.sender"
        );

        // 4. Agent ownership: caller must own the agent in the Identity Registry
        require(
            identityRegistry.ownerOf(agentId) == msg.sender,
            "Caller is not agent owner"
        );

        // 5. Verify the Reclaim proof on-chain (reverts on failure)
        reclaimVerifier.verifyProof(proof);

        // 6. Record agent -> provider -> timestamp
        agentProviderTimestamp[agentId][providerHash] = block.timestamp;

        // 7. Build response hash from proof data
        bytes32 responseHash = keccak256(
            abi.encodePacked(
                proof.claimInfo.provider,
                proof.claimInfo.parameters,
                proof.signedClaim.claim.identifier,
                proof.signedClaim.claim.timestampS
            )
        );

        // 8. Post to ERC-8004 Validation Registry (response = 1 means "validated / approved")
        uint8 response = 1;
        validationRegistry.validationResponse(
            requestHash,
            response,
            responseUri,
            responseHash,
            tag
        );

        emit ProofVerified(requestHash, agentId, proof.claimInfo.provider, response);
    }

    // ---------------------------------------------------------------
    // View helpers
    // ---------------------------------------------------------------

    function isProviderAllowed(string calldata provider) external view returns (bool) {
        return allowedProviders[keccak256(abi.encodePacked(provider))];
    }

    function isRequestProcessed(bytes32 requestHash) external view returns (bool) {
        return processedRequests[requestHash];
    }

    function getAgentProviderTimestamp(
        bytes32 agentId,
        string calldata provider
    ) external view returns (uint256) {
        return agentProviderTimestamp[agentId][keccak256(abi.encodePacked(provider))];
    }
}
