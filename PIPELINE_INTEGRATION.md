# PRISM Pipeline Integration Guide

This document is for the pipeline engineer integrating PRISM verification → on-chain attestation.

## What you get
- A single backend endpoint that returns an on-chain transaction hash + a deterministic proof hash.
- A deployed smart contract (`PRISMRegistry`) that stores the attestation and mints a soulbound token (SBT).

## Components
- **Smart contract:** `contracts/src/PRISMRegistry.sol`
- **Backend (Spring Boot):** `security-core`
- **Primary endpoint:** `POST /api/verify/human`

---

## Smart contract
### Network / Address
- **Network:** Sepolia (chainId `11155111`)
- **Contract:** `PRISMRegistry`
- **Address:** `0xD96fF6ba63E803C877c82999C0C7DD829C3415B8`

### Core rules (important)
- **Soulbound:** transfer is disabled.
- **No renewal before expiry:** attempting to mint for a wallet that is already verified (not expired) reverts.
- **Deterministic tokenId:** `tokenId = uint256(uint160(userAddress))`.

### Functions used by the pipeline
- **Mint (server/admin paid):** `mintAttestation(address user, bytes32 proofHash, uint16 confidenceBps)`
- **Revoke (admin/owner only):** `revoke(address user)`
- **Query:** `isHuman(address user) -> bool`

ABI is stored at:
- `contracts/artifacts/PRISMRegistry.abi.json`

Handoff metadata is stored at:
- `contracts/artifacts/PIPELINE_HANDOFF.json`

---

## Backend API
### Endpoint
- Method/path: `POST /api/verify/human`
- Header auth: `X-API-KEY: <python.api.key>`

### Request body
JSON schema (scores are `0..1`):

```json
{
  "wallet": "0x...",
  "sessionId": "string",
  "eyeScore": 0.95,
  "skinScore": 0.95,
  "pulseScore": 0.95,
  "flashScore": 0.95
}
```

### Query params
- `force` (boolean, default `false`)
  - `false`: mints only if wallet is not currently verified.
  - `true`: if wallet is already verified, backend will automatically call `revoke(wallet)` then mint.

Example:
- `POST /api/verify/human?force=true`

### Response
On success:

```json
{
  "status": "VERIFIED",
  "confidenceScore": 0.95,
  "blockchainTx": "0x...",
  "proofHash": "0x...",
  "expiresAtEpochSec": 1768823455,
  "tokenId": "7179..."
}
```

Notes:
- `confidenceScore` is computed by `DecisionEngine.calculateScore(request)`.
- Verification threshold is currently `>= 0.75`.

---

## Proof hash (pipeline contract binding)
Backend computes:
- `confidenceBps = round(clamp(confidenceScore, 0..1) * 10000)`
- `expiresAtEpochSec = now + prism.attestation.ttlSeconds`
- `proofMaterial = sessionId:wallet_lowercase:confidenceBps:expiresAtEpochSec`
- `proofHash = sha256(proofMaterial)`

This `proofHash` is what gets written on-chain.

Implementation reference:
- `security-core/src/main/java/com/prism/security_core/blockchain/BlockchainService.java`

---

## Required runtime configuration
The backend reads all chain settings from environment variables (recommended), mapped by Spring:

- `WEB3_RPC_URL` → `web3.rpc.url`
- `WEB3_CONTRACT_ADDRESS` → `web3.contract.address`
- `WEB3_WALLET_PRIVATEKEY` → `web3.wallet.privateKey`

Also used:
- `PRISM_ATTESTATION_TTLSECONDS` → `prism.attestation.ttlSeconds` (default `604800`)

Security:
- `python.api.key` is read from `security-core/src/main/resources/application.properties`.

---

## Minimal on-chain smoke checks (cast)
Assuming:

```bash
RPC="https://sepolia.infura.io/v3/<PROJECT_ID>"
CONTRACT="0xD96fF6ba63E803C877c82999C0C7DD829C3415B8"
USER="0x..."
```

Check verification status:

```bash
cast call "$CONTRACT" "isHuman(address)(bool)" "$USER" --rpc-url "$RPC"
```

Revoke (owner/admin only):

```bash
cast send "$CONTRACT" "revoke(address)" "$USER" --rpc-url "$RPC" --private-key "$WEB3_WALLET_PRIVATEKEY"
```

---

## Common pipeline failure modes
### 1) `execution reverted` during mint
Most common cause: wallet is already verified (not expired).
- Fix: call the API with `?force=true`, or use a fresh wallet.

### 2) `401 Unauthorized`
- Fix: ensure `X-API-KEY` header matches `python.api.key`.

### 3) `FAILED_TO_WRITE` in API response
- Fix: check backend logs for web3j error; verify env vars are set and wallet has enough Sepolia ETH.
