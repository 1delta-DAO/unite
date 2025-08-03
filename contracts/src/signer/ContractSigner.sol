// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import "../Errors.sol";

/**
 * Simple wrapped contract signer contract that validates a user signature.
 *
 * There are key differences to how contract signers are used for user-owned contracts
 *
 * We provide signature AND epected user as single bytes (the user is in the last 20 bytes)
 * This can only be done based on a contract logic that always guarantees that the bytes have this layout (to prevent bad signatures)
 * 
 * This is illustrated in the `MarginSettler` contract where in `takeOrder`, we pass the correct calldata to the 1inch router.
 */
abstract contract ContractSigner is IERC1271 {
    function isValidSignature(
        bytes32 orderHash,
        bytes calldata signature
    ) external pure returns (bytes4) {
        return _isValidSignature(orderHash, signature);
    }

    /// @notice this is executed when the 1inch router tries to validate the sig
    function _isValidSignature(
        bytes32 orderHash,
        bytes calldata signature
    ) internal pure returns (bytes4) {
        // 32 r, 32 s, 1 v, 20 signer,
        if (signature.length != 85) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;
        address signer;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 0x20))
            v := shr(248, calldataload(add(signature.offset, 0x40)))
            // the signer is at the end
            signer := shr(96, calldataload(add(signature.offset, 65)))
        }
        address recoveredSigner = ECDSA.recover(orderHash, v, r, s);
        if (recoveredSigner == signer && recoveredSigner != address(0)) {
            return IERC1271.isValidSignature.selector;
        }
        return 0xffffffff;
    }

    /// @notice a simple utility function for testing
    function _recoverSigner(
        bytes32 orderHash,
        bytes memory signature
    ) internal pure returns (address) {
        if (signature.length != 65) revert InvalidSignatureLength();

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            let offset := add(signature, 0x20)
            r := mload(offset)
            s := mload(add(offset, 0x20))
            v := shr(248, mload(add(offset, 0x40)))
        }

        return ECDSA.recover(orderHash, v, r, s);
    }
}
