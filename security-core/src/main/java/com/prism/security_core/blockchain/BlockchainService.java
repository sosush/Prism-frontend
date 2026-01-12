package com.prism.security_core.blockchain;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Arrays;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.web3j.crypto.Credentials;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.tx.RawTransactionManager;

@Service
public class BlockchainService {

    private final Web3j web3j;

    /**
     * IMPORTANT: never commit real private keys.
     *
     * Defaulted to empty so local dev must set it explicitly.
     */
    @Value("${web3.wallet.privateKey:}")
    private String privateKey;

    @Value("${web3.contract.address:}")
    private String contractAddress;

    /**
     * Default TTL used by the on-chain contract; we still return expiry to clients
     * for UX. Use 7 days to match docs.
     */
    @Value("${prism.attestation.ttlSeconds:604800}")
    private long ttlSeconds;

    public BlockchainService(Web3j web3j) {
        this.web3j = web3j;
    }

    public AttestationResult mintAttestation(
            String wallet,
            String sessionId,
            double confidenceScore,
            boolean force) throws Exception {

        if (wallet == null || wallet.isBlank()) {
            throw new IllegalArgumentException("wallet is required");
        }
        if (privateKey == null || privateKey.isBlank()) {
            throw new IllegalStateException("web3.wallet.privateKey is not configured");
        }
        if (contractAddress == null || contractAddress.isBlank()) {
            throw new IllegalStateException("web3.contract.address is not configured");
        }

        // confidenceScore in API is 0..1; convert to basis points
        int confidenceBps = (int) Math.round(Math.max(0.0, Math.min(1.0, confidenceScore)) * 10_000.0);

        long nowSec = System.currentTimeMillis() / 1000L;
        long expiresAt = nowSec + ttlSeconds;

        // Stable, structured proof hash (doesn't leak biometrics, just binds claim)
        // Include: sessionId, wallet, confidenceBps, expiresAt
        String proofMaterial = String.join(":",
                sessionId == null ? "" : sessionId,
                wallet.toLowerCase(),
                Integer.toString(confidenceBps),
                Long.toString(expiresAt));

        byte[] proofHash = sha256Bytes32(proofMaterial);

        Credentials creds = Credentials.create(privateKey);
        RawTransactionManager txManager = new RawTransactionManager(web3j, creds);

        PrismVerificationContract contract = PrismVerificationContract.load(
                contractAddress,
                web3j,
                txManager,
                new PolygonGasProvider());

        if (force) {
            Boolean currentlyHuman = contract.isHuman(wallet).send();
            if (Boolean.TRUE.equals(currentlyHuman)) {
                contract.revoke(wallet).send();
            }
        }

        TransactionReceipt receipt = contract.mintAttestation(wallet, proofHash, confidenceBps).send();
        String txHash = receipt.getTransactionHash();

        BigInteger tokenId = contract.tokenIdFor(wallet).send();

        return new AttestationResult(
                txHash,
                "0x" + toHex(proofHash),
                expiresAt,
                tokenId);
    }

    /**
     * Legacy method kept for compatibility with earlier demos.
     */
    public String storeProof(String data) throws Exception {

        byte[] bytes32 = sha256Bytes32(data);

        Credentials creds = Credentials.create(privateKey);
        RawTransactionManager txManager = new RawTransactionManager(web3j, creds);

        PrismVerificationContract contract = PrismVerificationContract.load(
                contractAddress,
                web3j,
                txManager,
                new PolygonGasProvider());

        TransactionReceipt receipt = contract.storeVerification(bytes32).send();
        return receipt.getTransactionHash();
    }

    private static byte[] sha256Bytes32(String input) throws Exception {
        MessageDigest md = MessageDigest.getInstance("SHA-256");
        byte[] hashBytes = md.digest(input.getBytes(StandardCharsets.UTF_8));
        return Arrays.copyOf(hashBytes, 32);
    }

    private static String toHex(byte[] bytes) {
        StringBuilder sb = new StringBuilder(bytes.length * 2);
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
