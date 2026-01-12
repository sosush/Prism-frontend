// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC5192} from "./interfaces/IERC5192.sol";
import {IZKVerifier} from "./interfaces/IZKVerifier.sol";

/// @notice Minimal PRISM SBT + attestation registry.
/// @dev Intentionally minimal (no OpenZeppelin dependency) to keep repo lightweight.
contract PRISMRegistry is IERC5192 {
    // -------------------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------------------

    error NotOwner();
    error AlreadyVerified();
    error NotVerified();
    error ZeroAddress();
    error InvalidSignature();
    error SignatureExpired();
    error ZkVerifierNotSet();
    error ZkProofInvalid();
    error Soulbound();

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event Attested(address indexed user, bytes32 proofHash, uint64 expiresAt, uint16 confidenceBps);
    event Revoked(address indexed user);

    // ERC-721-ish minimal events
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // -------------------------------------------------------------------------
    // Structs / Storage
    // -------------------------------------------------------------------------

    struct Attestation {
        uint64 issuedAt;
        uint64 expiresAt;
        bytes32 proofHash;
        uint16 confidenceBps; // 0-10000
        address issuer;
    }

    mapping(address => Attestation) public attestations;

    // Minimal ERC721 token ownership
    mapping(uint256 => address) private _ownerOf;
    mapping(address => uint256) private _balanceOf;
    mapping(uint256 => address) private _getApproved;
    mapping(address => mapping(address => bool)) private _isApprovedForAll;

    address public owner;
    address public issuer; // trusted signer for EIP-712

    /// @dev Default TTL for attestations (seconds). 7 days by default.
    uint64 public attestationTtl;

    IZKVerifier public zkVerifier;

    // -------------------------------------------------------------------------
    // EIP-712
    // -------------------------------------------------------------------------

    bytes32 public immutable DOMAIN_SEPARATOR;

    // keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)")
    bytes32 private constant _DOMAIN_TYPEHASH =
        0x8b73c3c69bb8fe3d512ecc4cf759cc79239f7b179b0ffacaa9a75d522b39400f;

    bytes32 private constant _NAME_HASH = keccak256("PRISMRegistry");
    bytes32 private constant _VERSION_HASH = keccak256("1");

    // keccak256("MintAttestation(address user,bytes32 proofHash,uint16 confidenceBps,uint64 expiresAt,uint256 deadline)")
    bytes32 public constant MINT_TYPEHASH =
        keccak256(
            "MintAttestation(address user,bytes32 proofHash,uint16 confidenceBps,uint64 expiresAt,uint256 deadline)"
        );

    // -------------------------------------------------------------------------
    // Constructor / Admin
    // -------------------------------------------------------------------------

    constructor(address _issuer, uint64 _attestationTtl) {
        owner = msg.sender;
        if (_issuer == address(0)) revert ZeroAddress();
        issuer = _issuer;
        attestationTtl = _attestationTtl == 0 ? uint64(7 days) : _attestationTtl;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                _DOMAIN_TYPEHASH,
                _NAME_HASH,
                _VERSION_HASH,
                block.chainid,
                address(this)
            )
        );
    }

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        owner = newOwner;
    }

    function setIssuer(address newIssuer) external onlyOwner {
        if (newIssuer == address(0)) revert ZeroAddress();
        issuer = newIssuer;
    }

    function setAttestationTtl(uint64 ttl) external onlyOwner {
        // ttl can be set to any value; pipeline decides policy.
        attestationTtl = ttl;
    }

    function setZkVerifier(address verifier) external onlyOwner {
        zkVerifier = IZKVerifier(verifier);
    }

    // -------------------------------------------------------------------------
    // Public read
    // -------------------------------------------------------------------------

    function isHuman(address user) external view returns (bool) {
        return attestations[user].expiresAt > uint64(block.timestamp);
    }

    function tokenIdFor(address user) public pure returns (uint256) {
        return uint256(uint160(user));
    }

    // -------------------------------------------------------------------------
    // Minting flows
    // -------------------------------------------------------------------------

    /// @notice Admin-paid minting flow.
    /// @dev `msg.sender` must be owner (your Java issuer) in the MVP default.
    function mintAttestation(address user, bytes32 proofHash, uint16 confidenceBps) external onlyOwner {
        _mintForUser(user, proofHash, confidenceBps, uint64(block.timestamp) + attestationTtl, msg.sender);
    }

    /// @notice EIP-712 signature-based flow (user pays gas, issuer signs).
    /// @dev This allows the pipeline to move away from holding a hot minter key.
    function verifyAndMint(
        address user,
        bytes32 proofHash,
        uint16 confidenceBps,
        uint64 expiresAt,
        uint256 deadline,
        bytes calldata signature
    ) external {
        if (block.timestamp > deadline) revert SignatureExpired();

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(MINT_TYPEHASH, user, proofHash, confidenceBps, expiresAt, deadline))
            )
        );

        address recovered = _recoverSigner(digest, signature);
        if (recovered != issuer) revert InvalidSignature();

        _mintForUser(user, proofHash, confidenceBps, expiresAt, recovered);
    }

    /// @notice ZK-proof based flow (future EZKL integration).
    /// @dev Default policy: only mint if the verifier validates.
    function verifyWithZkProof(
        bytes calldata proof,
        bytes32[] calldata publicInputs,
        bytes32 proofHash,
        uint16 confidenceBps
    ) external {
        if (address(zkVerifier) == address(0)) revert ZkVerifierNotSet();
        bool ok = zkVerifier.verify(proof, publicInputs);
        if (!ok) revert ZkProofInvalid();

        _mintForUser(msg.sender, proofHash, confidenceBps, uint64(block.timestamp) + attestationTtl, msg.sender);
    }

    function revoke(address user) external onlyOwner {
        Attestation memory att = attestations[user];
        if (att.expiresAt == 0) revert NotVerified();

        delete attestations[user];

        uint256 tid = tokenIdFor(user);
        if (_ownerOf[tid] != address(0)) {
            _burn(tid);
        }

        emit Revoked(user);
    }

    // -------------------------------------------------------------------------
    // ERC-721 minimal (soulbound)
    // -------------------------------------------------------------------------

    function name() external pure returns (string memory) {
        return "PRISM Human";
    }

    function symbol() external pure returns (string memory) {
        return "PRISM-HUMAN";
    }

    function balanceOf(address user) external view returns (uint256) {
        if (user == address(0)) revert ZeroAddress();
        return _balanceOf[user];
    }

    function ownerOf(uint256 tokenId) external view returns (address) {
        address o = _ownerOf[tokenId];
        if (o == address(0)) revert NotVerified();
        return o;
    }

    function getApproved(uint256 tokenId) external view returns (address) {
        return _getApproved[tokenId];
    }

    function isApprovedForAll(address user, address operator) external view returns (bool) {
        return _isApprovedForAll[user][operator];
    }

    function approve(address, uint256) external pure {
        // Soulbound: approvals are meaningless because transfers are blocked.
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) external pure {
        revert Soulbound();
    }

    function transferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert Soulbound();
    }

    // -------------------------------------------------------------------------
    // ERC-5192
    // -------------------------------------------------------------------------

    function locked(uint256) external pure returns (bool) {
        return true;
    }

    // -------------------------------------------------------------------------
    // Internals
    // -------------------------------------------------------------------------

    function _mintForUser(
        address user,
        bytes32 proofHash,
        uint16 confidenceBps,
        uint64 expiresAt,
        address attIssuer
    ) internal {
        if (user == address(0)) revert ZeroAddress();
        if (attestations[user].expiresAt > uint64(block.timestamp)) revert AlreadyVerified();

        attestations[user] = Attestation({
            issuedAt: uint64(block.timestamp),
            expiresAt: expiresAt,
            proofHash: proofHash,
            confidenceBps: confidenceBps,
            issuer: attIssuer
        });

        uint256 tid = tokenIdFor(user);
        if (_ownerOf[tid] == address(0)) {
            _mint(user, tid);
        }

        emit Attested(user, proofHash, expiresAt, confidenceBps);
    }

    function _mint(address to, uint256 tokenId) internal {
        _ownerOf[tokenId] = to;
        _balanceOf[to] += 1;
        emit Transfer(address(0), to, tokenId);
        emit Locked(tokenId);
    }

    function _burn(uint256 tokenId) internal {
        address from = _ownerOf[tokenId];
        _ownerOf[tokenId] = address(0);
        _balanceOf[from] -= 1;
        delete _getApproved[tokenId];
        emit Transfer(from, address(0), tokenId);
    }

    function _recoverSigner(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        if (sig.length != 65) revert InvalidSignature();

        bytes32 r;
        bytes32 s;
        uint8 v;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            r := calldataload(sig.offset)
            s := calldataload(add(sig.offset, 32))
            v := byte(0, calldataload(add(sig.offset, 64)))
        }

        if (v < 27) v += 27;
        if (v != 27 && v != 28) revert InvalidSignature();

        address signer = ecrecover(digest, v, r, s);
        if (signer == address(0)) revert InvalidSignature();
        return signer;
    }
}
