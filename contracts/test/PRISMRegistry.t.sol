// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {PRISMRegistry} from "../src/PRISMRegistry.sol";

contract PRISMRegistryTest is Test {
    PRISMRegistry reg;

    address owner = address(0xA11CE);
    address issuer = address(0xB0B);
    address user = address(0xCAFE);

    function setUp() public {
        vm.prank(owner);
        reg = new PRISMRegistry(issuer, uint64(7 days));
    }

    function testAdminMintCreatesAttestationAndToken() public {
        bytes32 proofHash = keccak256("proof");
        uint16 conf = 9200;

        vm.prank(owner);
        reg.mintAttestation(user, proofHash, conf);

        (uint64 issuedAt, uint64 expiresAt, bytes32 storedHash, uint16 storedConf, address storedIssuer) = reg.attestations(user);
        assertGt(issuedAt, 0);
        assertGt(expiresAt, uint64(block.timestamp));
        assertEq(storedHash, proofHash);
        assertEq(storedConf, conf);
        assertEq(storedIssuer, owner);

        uint256 tid = reg.tokenIdFor(user);
        assertEq(reg.ownerOf(tid), user);
        assertTrue(reg.locked(tid));
        assertTrue(reg.isHuman(user));
    }

    function testCannotRenewBeforeExpiry() public {
        bytes32 proofHash = keccak256("proof");

        vm.prank(owner);
        reg.mintAttestation(user, proofHash, 9000);

        vm.prank(owner);
        vm.expectRevert(PRISMRegistry.AlreadyVerified.selector);
        reg.mintAttestation(user, proofHash, 9000);
    }

    function testCanRenewAfterExpiry() public {
        vm.prank(owner);
        reg.setAttestationTtl(uint64(1 days));

        vm.prank(owner);
        reg.mintAttestation(user, keccak256("p1"), 8000);

        vm.warp(block.timestamp + 2 days);

        vm.prank(owner);
        reg.mintAttestation(user, keccak256("p2"), 8500);

        (, uint64 expiresAt, bytes32 storedHash, uint16 storedConf, address storedIssuer) = reg.attestations(user);
        assertEq(storedHash, keccak256("p2"));
        assertEq(storedConf, 8500);
        assertEq(storedIssuer, owner);
        assertGt(expiresAt, uint64(block.timestamp));
    }

    function testSoulboundRevertsTransfer() public {
        vm.prank(owner);
        reg.mintAttestation(user, keccak256("proof"), 9000);

        uint256 tid = reg.tokenIdFor(user);
        vm.prank(user);
        vm.expectRevert(PRISMRegistry.Soulbound.selector);
        reg.transferFrom(user, address(0xDEAD), tid);
    }
}
