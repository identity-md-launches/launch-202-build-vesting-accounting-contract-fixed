// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @dev Independent, checked-arithmetic binary long division. No production math, assembly,
/// mulmod, 512-bit multiplication, or modular inverse is used by this oracle.
library ReferenceModel {
    function vested(uint256 grant, uint256 start, uint256 cliff, uint256 duration, uint256 timestamp)
        internal
        pure
        returns (uint256 quotient)
    {
        if (timestamp < start) return 0;
        uint256 elapsed = timestamp - start;
        if (elapsed < cliff) return 0;
        if (elapsed >= duration) return grant;

        uint256 remainder;
        // Extend the processed grant prefix one bit at a time. Maintain
        // prefix * elapsed = quotient * duration + remainder, with remainder < duration.
        for (uint256 bit = 256; bit > 0;) {
            --bit;
            quotient *= 2;
            if (remainder >= duration - remainder) {
                remainder -= duration - remainder;
                ++quotient;
            } else {
                remainder += remainder;
            }
            if (((grant >> bit) & 1) != 0) {
                if (remainder >= duration - elapsed) {
                    remainder -= duration - elapsed;
                    ++quotient;
                } else {
                    remainder += elapsed;
                }
            }
        }
    }
}
