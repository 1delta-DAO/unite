// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ExtensionLib} from "@1inch/lo/libraries/ExtensionLib.sol";

/**
 * @title ExtensionEncoderLib
 * @notice Library for encoding extension data for the Limit Order Protocol.
 * @dev This library provides functions to encode different extension fields into the proper format
 * with offsets for efficient decoding.
 */
contract ExtensionEncoderLib {
    using ExtensionLib for bytes;

    /**
     * @notice Encodes extension data with all fields.
     * @param makerAssetSuffix Additional data for maker asset transfer
     * @param takerAssetSuffix Additional data for taker asset transfer
     * @param makingAmountData Data for calculating making amount
     * @param takingAmountData Data for calculating taking amount
     * @param predicate Order predicate/conditions
     * @param makerPermit Maker's permit data
     * @param preInteractionData Pre-interaction target and data
     * @param postInteractionData Post-interaction target and data
     * @param customData Extra suffix data
     * @return encodedExtension The encoded extension data
     */
    function encodeExtension(
        bytes memory makerAssetSuffix,
        bytes memory takerAssetSuffix,
        bytes memory makingAmountData,
        bytes memory takingAmountData,
        bytes memory predicate,
        bytes memory makerPermit,
        bytes memory preInteractionData,
        bytes memory postInteractionData,
        bytes memory customData
    ) internal pure returns (bytes memory encodedExtension) {
        // Calculate cumulative lengths for offsets
        uint256[] memory lengths = new uint256[](9);
        lengths[0] = makerAssetSuffix.length;
        lengths[1] = takerAssetSuffix.length;
        lengths[2] = makingAmountData.length;
        lengths[3] = takingAmountData.length;
        lengths[4] = predicate.length;
        lengths[5] = makerPermit.length;
        lengths[6] = preInteractionData.length;
        lengths[7] = postInteractionData.length;
        lengths[8] = customData.length;

        // Calculate cumulative offsets
        uint256[] memory offsets = new uint256[](9);
        uint256 cumulativeLength = 0;
        for (uint256 i = 0; i < 9; i++) {
            cumulativeLength += lengths[i];
            offsets[i] = cumulativeLength;
        }

        // Pack offsets into 32 bytes (each offset is 4 bytes)
        uint256 packedOffsets = 0;
        for (uint256 i = 0; i < 8; i++) {
            // Only pack first 8 offsets (32 bytes)
            packedOffsets |= (offsets[i] << (i * 32));
        }

        // Calculate total length for the encoded extension
        uint256 totalLength = 32 + cumulativeLength; // 32 bytes for offsets + data

        encodedExtension = new bytes(totalLength);

        // Write packed offsets to first 32 bytes
        assembly {
            mstore(add(encodedExtension, 32), packedOffsets)
        }

        // Write concatenated data after offsets
        uint256 dataOffset = 32;
        uint256 writeOffset = 32;

        // Write each field in order
        _writeBytes(encodedExtension, writeOffset, makerAssetSuffix);
        writeOffset += makerAssetSuffix.length;

        _writeBytes(encodedExtension, writeOffset, takerAssetSuffix);
        writeOffset += takerAssetSuffix.length;

        _writeBytes(encodedExtension, writeOffset, makingAmountData);
        writeOffset += makingAmountData.length;

        _writeBytes(encodedExtension, writeOffset, takingAmountData);
        writeOffset += takingAmountData.length;

        _writeBytes(encodedExtension, writeOffset, predicate);
        writeOffset += predicate.length;

        _writeBytes(encodedExtension, writeOffset, makerPermit);
        writeOffset += makerPermit.length;

        _writeBytes(encodedExtension, writeOffset, preInteractionData);
        writeOffset += preInteractionData.length;

        _writeBytes(encodedExtension, writeOffset, postInteractionData);
        writeOffset += postInteractionData.length;

        _writeBytes(encodedExtension, writeOffset, customData);
    }

    /**
     * @notice Encodes extension data with only specific fields.
     * @param fields Array of field data in the order: [makerAssetSuffix, takerAssetSuffix, makingAmountData, takingAmountData, predicate, makerPermit, preInteractionData, postInteractionData, customData]
     * @return encodedExtension The encoded extension data
     */
    function encodeExtensionFields(
        bytes[] calldata fields
    ) internal pure returns (bytes memory encodedExtension) {
        require(fields.length == 9, "ExtensionEncoder: Invalid fields length");

        return
            encodeExtension(
                fields[0], // makerAssetSuffix
                fields[1], // takerAssetSuffix
                fields[2], // makingAmountData
                fields[3], // takingAmountData
                fields[4], // predicate
                fields[5], // makerPermit
                fields[6], // preInteractionData
                fields[7], // postInteractionData
                fields[8] // customData
            );
    }

    /**
     * @notice Encodes a minimal extension with only custom data.
     * @param customData Extra suffix data
     * @return encodedExtension The encoded extension data
     */
    function encodeCustomDataOnly(
        bytes calldata customData
    ) internal pure returns (bytes memory encodedExtension) {
        return
            encodeExtension(
                new bytes(0), // makerAssetSuffix
                new bytes(0), // takerAssetSuffix
                new bytes(0), // makingAmountData
                new bytes(0), // takingAmountData
                new bytes(0), // predicate
                new bytes(0), // makerPermit
                new bytes(0), // preInteractionData
                new bytes(0), // postInteractionData
                customData
            );
    }

    /**
     * @notice Encodes extension with interactions only.
     * @param preInteractionData Pre-interaction target and data
     * @param postInteractionData Post-interaction target and data
     * @return encodedExtension The encoded extension data
     */
    function encodeInteractionsOnly(
        bytes calldata preInteractionData,
        bytes calldata postInteractionData
    ) internal pure returns (bytes memory encodedExtension) {
        return
            encodeExtension(
                new bytes(0), // makerAssetSuffix
                new bytes(0), // takerAssetSuffix
                new bytes(0), // makingAmountData
                new bytes(0), // takingAmountData
                new bytes(0), // predicate
                new bytes(0), // makerPermit
                preInteractionData,
                postInteractionData,
                new bytes(0) // customData
            );
    }

    /**
     * @notice Writes bytes to a specific offset in the encoded extension.
     * @param target The target bytes array to write to
     * @param offset The offset to write at
     * @param data The data to write
     */
    function _writeBytes(
        bytes memory target,
        uint256 offset,
        bytes memory data
    ) private pure {
        if (data.length > 0) {
            assembly {
                let dataStart := add(data, 32)
                let targetStart := add(target, add(32, offset))
                let dataLength := mload(data)

                mcopy(targetStart, dataStart, dataLength)
            }
        }
    }

    /**
     * @notice Validates that an encoded extension can be decoded properly.
     * @param encodedExtension The encoded extension to validate
     * @return isValid True if the extension is valid
     */
    function validateEncodedExtension(
        bytes calldata encodedExtension
    ) internal view returns (bool isValid) {
        if (encodedExtension.length < 32) {
            return false;
        }

        // Try to decode each field to ensure offsets are correct
        try this.decodeAllFields(encodedExtension) {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * @notice Decodes all fields from an encoded extension (for validation).
     * @param encodedExtension The encoded extension to decode
     * @return fields Array of decoded fields
     */
    function decodeAllFields(
        bytes calldata encodedExtension
    ) public pure returns (bytes[] memory fields) {
        fields = new bytes[](9);

        fields[0] = encodedExtension.makerAssetSuffix();
        fields[1] = encodedExtension.takerAssetSuffix();
        fields[2] = encodedExtension.makingAmountData();
        fields[3] = encodedExtension.takingAmountData();
        fields[4] = encodedExtension.predicate();
        fields[5] = encodedExtension.makerPermit();
        fields[6] = encodedExtension.preInteractionTargetAndData();
        fields[7] = encodedExtension.postInteractionTargetAndData();
        fields[8] = encodedExtension.customData();

        return fields;
    }
}
