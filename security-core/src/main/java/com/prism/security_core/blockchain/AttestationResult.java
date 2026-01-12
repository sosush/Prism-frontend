package com.prism.security_core.blockchain;

import java.math.BigInteger;

public record AttestationResult(
        String txHash,
        String proofHashHex,
        long expiresAtEpochSec,
        BigInteger tokenId) {
}
