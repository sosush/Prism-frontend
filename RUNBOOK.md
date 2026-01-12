# PRISM Runbook (Foolproof)

This is a step-by-step guide to run the PRISM security-core backend + Sepolia smart contract integration.

If you follow this exactly, you should be able to:
1) Start the backend
2) Call `POST /api/verify/human`
3) Get a **real** `blockchainTx` transaction hash
4) Confirm on-chain that `isHuman(wallet) == true`

---

## 0) Prereqs
- Linux/macOS recommended
- Java (project currently runs on a recent JDK; your setup shows Java 25)
- Sepolia ETH for the sponsor/minter wallet
- MariaDB running locally (unless you override DB config)
- Foundry installed (optional for contract testing / `cast` commands)
  - `cast` and `forge` should be available

---

## 1) Smart contract (already deployed)
This repo already has `PRISMRegistry` deployed on Sepolia.

- **Contract:** `PRISMRegistry`
- **Address:** `0xD96fF6ba63E803C877c82999C0C7DD829C3415B8`
- **Chain:** Sepolia (11155111)

### Quick chain sanity check

```bash
RPC="https://sepolia.infura.io/v3/<PROJECT_ID>"
CONTRACT="0xD96fF6ba63E803C877c82999C0C7DD829C3415B8"
cast call "$CONTRACT" "issuer()(address)" --rpc-url "$RPC"
cast call "$CONTRACT" "owner()(address)" --rpc-url "$RPC"
```

---

## 2) Database (MariaDB) setup
The Spring Boot app uses MySQL/MariaDB.

### Option A (recommended): create a dedicated DB user
Run these in MariaDB (adjust password):

```sql
CREATE DATABASE IF NOT EXISTS prism_db;
CREATE USER IF NOT EXISTS 'prism'@'localhost' IDENTIFIED BY '<CHOOSE_A_PASSWORD>';
GRANT ALL PRIVILEGES ON prism_db.* TO 'prism'@'localhost';
FLUSH PRIVILEGES;
```

Then set runtime env vars when running the backend:

```bash
export SPRING_DATASOURCE_URL="jdbc:mysql://localhost:3306/prism_db"
export SPRING_DATASOURCE_USERNAME="prism"
export SPRING_DATASOURCE_PASSWORD="<CHOOSE_A_PASSWORD>"
```

### Option B: use root
This often fails on Linux distros due to auth plugins (e.g. `Access denied for user 'root'@'localhost'`).
If you see that error, use Option A.

---

## 3) Backend configuration (required)
The backend MUST have these env vars to write to chain:

```bash
export WEB3_RPC_URL="https://sepolia.infura.io/v3/<PROJECT_ID>"
export WEB3_CONTRACT_ADDRESS="0xD96fF6ba63E803C877c82999C0C7DD829C3415B8"
export WEB3_WALLET_PRIVATEKEY="0x<SEPOLIA_MINTER_PRIVATE_KEY>"
```

Notes:
- Do not commit real keys. Keep them in your shell env or a local `.env` that is gitignored.
- Make sure the minter wallet has enough Sepolia ETH.

Optional:

```bash
export PRISM_ATTESTATION_TTLSECONDS=604800
```

---

## 4) Start the backend
From repo root:

```bash
./security-core/mvnw -f security-core/pom.xml spring-boot:run
```

If it fails:
- Check DB env vars are set
- Check MariaDB is running

---

## 5) Call the verification endpoint
### A) Normal mode

```bash
curl -i -X POST "http://localhost:8080/api/verify/human" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: prism-python-secret" \
  -d '{
    "wallet": "0x7dC0B644bBd9bbaeEC62bE50CAE3472919A7a653",
    "sessionId": "demo-sepolia-1",
    "eyeScore": 0.95,
    "skinScore": 0.95,
    "pulseScore": 0.95,
    "flashScore": 0.95
  }'
```

### B) Force mode (recommended for repeated demos with SAME wallet)
If you keep using the same wallet, mint will revert when already verified.
Use `force=true` to automatically revoke then mint.

```bash
curl -i -X POST "http://localhost:8080/api/verify/human?force=true" \
  -H "Content-Type: application/json" \
  -H "X-API-KEY: prism-python-secret" \
  -d '{
    "wallet": "0x7dC0B644bBd9bbaeEC62bE50CAE3472919A7a653",
    "sessionId": "demo-sepolia-1",
    "eyeScore": 0.95,
    "skinScore": 0.95,
    "pulseScore": 0.95,
    "flashScore": 0.95
  }'
```

Expected response fields:
- `status: VERIFIED`
- `blockchainTx: 0x...` (real tx hash)
- `proofHash: 0x...`
- `expiresAtEpochSec: <unix seconds>`
- `tokenId: <string>`

---

## 6) Verify on-chain

```bash
RPC="https://sepolia.infura.io/v3/<PROJECT_ID>"
CONTRACT="0xD96fF6ba63E803C877c82999C0C7DD829C3415B8"
USER="0x7dC0B644bBd9bbaeEC62bE50CAE3472919A7a653"

cast call "$CONTRACT" "isHuman(address)(bool)" "$USER" --rpc-url "$RPC"
```

Should return `true`.

To inspect the attestation struct:

```bash
cast call "$CONTRACT" "attestations(address)(uint64,uint64,bytes32,uint16,address)" "$USER" --rpc-url "$RPC"
```

---

## Troubleshooting
### 1) `FAILED_TO_WRITE` returned in response
- Ensure `WEB3_RPC_URL`, `WEB3_CONTRACT_ADDRESS`, `WEB3_WALLET_PRIVATEKEY` are set.
- Ensure the minter has Sepolia ETH.
- Ensure RPC is reachable.

### 2) `execution reverted`
- Most common: wallet already verified and not expired.
  - Use `/api/verify/human?force=true`.

### 3) `401 Unauthorized`
- Ensure header `X-API-KEY` matches `python.api.key`.

### 4) DB error: `Access denied for user 'root'@'localhost'`
- Use the dedicated `prism` DB user (Section 2 Option A).

---

## Implementation references
- Endpoint: `security-core/src/main/java/com/prism/security_core/verification/VerificationController.java`
- Chain write: `security-core/src/main/java/com/prism/security_core/blockchain/BlockchainService.java`
- Web3 wrapper: `security-core/src/main/java/com/prism/security_core/blockchain/PrismVerificationContract.java`
- Contract: `contracts/src/PRISMRegistry.sol`
