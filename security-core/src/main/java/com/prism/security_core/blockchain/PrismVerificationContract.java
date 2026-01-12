package com.prism.security_core.blockchain;

import java.math.BigInteger;
import java.util.Arrays;
import java.util.Collections;

import org.web3j.abi.datatypes.Address;
import org.web3j.abi.datatypes.Function;
import org.web3j.abi.datatypes.generated.Bytes32;
import org.web3j.abi.datatypes.generated.Uint16;
import org.web3j.abi.datatypes.generated.Uint256;
import org.web3j.protocol.Web3j;
import org.web3j.protocol.core.RemoteFunctionCall;
import org.web3j.protocol.core.methods.response.TransactionReceipt;
import org.web3j.tx.Contract;
import org.web3j.tx.TransactionManager;
import org.web3j.tx.gas.ContractGasProvider;

/**
 * Minimal Web3j wrapper for PRISMRegistry.
 *
 * NOTE: This is intentionally hand-written (not generated) to keep the repo light.
 */
public class PrismVerificationContract extends Contract {

    protected PrismVerificationContract(
            String contractAddress,
            Web3j web3j,
            TransactionManager transactionManager,
            ContractGasProvider gasProvider) {

        super("", contractAddress, web3j, transactionManager, gasProvider);
    }

    public static PrismVerificationContract load(
            String contractAddress,
            Web3j web3j,
            TransactionManager transactionManager,
            ContractGasProvider gasProvider) {

        return new PrismVerificationContract(contractAddress, web3j, transactionManager, gasProvider);
    }

    /**
     * Admin-paid flow: mintAttestation(address user, bytes32 proofHash, uint16 confidenceBps)
     */
    public RemoteFunctionCall<TransactionReceipt> mintAttestation(
            String user,
            byte[] proofHashBytes32,
            int confidenceBps) {

        Function function = new Function(
                "mintAttestation",
                Arrays.asList(
                        new Address(user),
                        new Bytes32(proofHashBytes32),
                        new Uint16(BigInteger.valueOf(confidenceBps))),
                Collections.emptyList());

        return executeRemoteCallTransaction(function);
    }

    /**
     * Legacy demo method (kept for compatibility): storeVerification(bytes32)
     */
    public RemoteFunctionCall<TransactionReceipt> storeVerification(byte[] hashBytes32) {

        Function function = new Function(
                "storeVerification",
                Arrays.asList(new Bytes32(hashBytes32)),
                Collections.emptyList());

        return executeRemoteCallTransaction(function);
    }

    /**
     * Read-only check: isHuman(address)
     */
    public RemoteFunctionCall<Boolean> isHuman(String user) {
        Function function = new Function(
                "isHuman",
                Arrays.asList(new Address(user)),
                Arrays.asList(new org.web3j.abi.TypeReference<org.web3j.abi.datatypes.Bool>() {
                }));

        return executeRemoteCallSingleValueReturn(function, Boolean.class);
    }

    /**
     * Owner/admin-only: revoke(address)
     */
    public RemoteFunctionCall<TransactionReceipt> revoke(String user) {
        Function function = new Function(
                "revoke",
                Arrays.asList(new Address(user)),
                Collections.emptyList());

        return executeRemoteCallTransaction(function);
    }

    /**
     * Read-only: tokenIdFor(address)
     */
    public RemoteFunctionCall<BigInteger> tokenIdFor(String user) {
        Function function = new Function(
                "tokenIdFor",
                Arrays.asList(new Address(user)),
                Arrays.asList(new org.web3j.abi.TypeReference<Uint256>() {
                }));

        return executeRemoteCallSingleValueReturn(function, BigInteger.class);
    }
}
