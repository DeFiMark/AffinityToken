//SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title Owner
 * @dev Set & change owner
 */
contract Ownable {

    address private owner;
    
    // event for EVM logging
    event OwnerSet(address indexed oldOwner, address indexed newOwner);
    
    // modifier to check if caller is owner
    modifier onlyOwner() {
        // If the first argument of 'require' evaluates to 'false', execution terminates and all
        // changes to the state and to Ether balances are reverted.
        // This used to consume all gas in old EVM versions, but not anymore.
        // It is often a good idea to use 'require' to check if functions are called correctly.
        // As a second argument, you can also provide an explanation about what went wrong.
        require(msg.sender == owner, "Caller is not owner");
        _;
    }
    
    /**
     * @dev Set contract deployer as owner
     */
    constructor() {
        owner = msg.sender; // 'msg.sender' is sender of current call, contract deployer for a constructor
        emit OwnerSet(address(0), owner);
    }

    /**
     * @dev Change owner
     * @param newOwner address of new owner
     */
    function changeOwner(address newOwner) public onlyOwner {
        emit OwnerSet(owner, newOwner);
        owner = newOwner;
    }

    /**
     * @dev Return owner address 
     * @return address of owner
     */
    function getOwner() external view returns (address) {
        return owner;
    }
}

library BytesLib {
    function concat(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bytes memory) {
        bytes memory tempBytes;

        assembly {
            // Get a location of some free memory and store it in tempBytes as
            // Solidity does for memory variables.
            tempBytes := mload(0x40)

            // Store the length of the first bytes array at the beginning of
            // the memory for tempBytes.
            let length := mload(_preBytes)
            mstore(tempBytes, length)

            // Maintain a memory counter for the current write location in the
            // temp bytes array by adding the 32 bytes for the array length to
            // the starting location.
            let mc := add(tempBytes, 0x20)
            // Stop copying when the memory counter reaches the length of the
            // first bytes array.
            let end := add(mc, length)

            for {
                // Initialize a copy counter to the start of the _preBytes data,
                // 32 bytes into its memory.
                let cc := add(_preBytes, 0x20)
            } lt(mc, end) {
                // Increase both counters by 32 bytes each iteration.
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                // Write the _preBytes data into the tempBytes memory 32 bytes
                // at a time.
                mstore(mc, mload(cc))
            }

            // Add the length of _postBytes to the current length of tempBytes
            // and store it as the new length in the first 32 bytes of the
            // tempBytes memory.
            length := mload(_postBytes)
            mstore(tempBytes, add(length, mload(tempBytes)))

            // Move the memory counter back from a multiple of 0x20 to the
            // actual end of the _preBytes data.
            mc := end
            // Stop copying when the memory counter reaches the new combined
            // length of the arrays.
            end := add(mc, length)

            for {
                let cc := add(_postBytes, 0x20)
            } lt(mc, end) {
                mc := add(mc, 0x20)
                cc := add(cc, 0x20)
            } {
                mstore(mc, mload(cc))
            }

            // Update the free-memory pointer by padding our last write location
            // to 32 bytes: add 31 bytes to the end of tempBytes to move to the
            // next 32 byte block, then round down to the nearest multiple of
            // 32. If the sum of the length of the two arrays is zero then add
            // one before rounding down to leave a blank 32 bytes (the length block with 0).
            mstore(
                0x40,
                and(
                    add(add(end, iszero(add(length, mload(_preBytes)))), 31),
                    not(31) // Round down to the nearest 32 bytes.
                )
            )
        }

        return tempBytes;
    }

    function concatStorage(bytes storage _preBytes, bytes memory _postBytes) internal {
        assembly {
            // Read the first 32 bytes of _preBytes storage, which is the length
            // of the array. (We don't need to use the offset into the slot
            // because arrays use the entire slot.)
            let fslot := sload(_preBytes.slot)
            // Arrays of 31 bytes or less have an even value in their slot,
            // while longer arrays have an odd value. The actual length is
            // the slot divided by two for odd values, and the lowest order
            // byte divided by two for even values.
            // If the slot is even, bitwise and the slot with 255 and divide by
            // two to get the length. If the slot is odd, bitwise and the slot
            // with -1 and divide by two.
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)
            let newlength := add(slength, mlength)
            // slength can contain both the length and contents of the array
            // if length < 32 bytes so let's prepare for that
            // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
            switch add(lt(slength, 32), lt(newlength, 32))
            case 2 {
                // Since the new array still fits in the slot, we just need to
                // update the contents of the slot.
                // uint256(bytes_storage) = uint256(bytes_storage) + uint256(bytes_memory) + new_length
                sstore(
                    _preBytes.slot,
                    // all the modifications to the slot are inside this
                    // next block
                    add(
                        // we can just add to the slot contents because the
                        // bytes we want to change are the LSBs
                        fslot,
                        add(
                            mul(
                                div(
                                    // load the bytes from memory
                                    mload(add(_postBytes, 0x20)),
                                    // zero all bytes to the right
                                    exp(0x100, sub(32, mlength))
                                ),
                                // and now shift left the number of bytes to
                                // leave space for the length in the slot
                                exp(0x100, sub(32, newlength))
                            ),
                            // increase length by the double of the memory
                            // bytes length
                            mul(mlength, 2)
                        )
                    )
                )
            }
            case 1 {
                // The stored value fits in the slot, but the combined value
                // will exceed it.
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // The contents of the _postBytes array start 32 bytes into
                // the structure. Our first read should obtain the `submod`
                // bytes that can fit into the unused space in the last word
                // of the stored array. To get this, we read 32 bytes starting
                // from `submod`, so the data we read overlaps with the array
                // contents by `submod` bytes. Masking the lowest-order
                // `submod` bytes allows us to add that value directly to the
                // stored value.

                let submod := sub(32, slength)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(and(fslot, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00), and(mload(mc), mask)))

                for {
                    mc := add(mc, 0x20)
                    sc := add(sc, 1)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
            default {
                // get the keccak hash to get the contents of the array
                mstore(0x0, _preBytes.slot)
                // Start copying to the last used word of the stored array.
                let sc := add(keccak256(0x0, 0x20), div(slength, 32))

                // save new length
                sstore(_preBytes.slot, add(mul(newlength, 2), 1))

                // Copy over the first `submod` bytes of the new data as in
                // case 1 above.
                let slengthmod := mod(slength, 32)
                let mlengthmod := mod(mlength, 32)
                let submod := sub(32, slengthmod)
                let mc := add(_postBytes, submod)
                let end := add(_postBytes, mlength)
                let mask := sub(exp(0x100, submod), 1)

                sstore(sc, add(sload(sc), and(mload(mc), mask)))

                for {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } lt(mc, end) {
                    sc := add(sc, 1)
                    mc := add(mc, 0x20)
                } {
                    sstore(sc, mload(mc))
                }

                mask := exp(0x100, sub(mc, end))

                sstore(sc, mul(div(mload(mc), mask), mask))
            }
        }
    }

    function slice(
        bytes memory _bytes,
        uint _start,
        uint _length
    ) internal pure returns (bytes memory) {
        require(_length + 31 >= _length, "slice_overflow");
        require(_bytes.length >= _start + _length, "slice_outOfBounds");

        bytes memory tempBytes;

        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    function toAddress(bytes memory _bytes, uint _start) internal pure returns (address) {
        require(_bytes.length >= _start + 20, "toAddress_outOfBounds");
        address tempAddress;

        assembly {
            tempAddress := div(mload(add(add(_bytes, 0x20), _start)), 0x1000000000000000000000000)
        }

        return tempAddress;
    }

    function toUint8(bytes memory _bytes, uint _start) internal pure returns (uint8) {
        require(_bytes.length >= _start + 1, "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }

        return tempUint;
    }

    function toUint16(bytes memory _bytes, uint _start) internal pure returns (uint16) {
        require(_bytes.length >= _start + 2, "toUint16_outOfBounds");
        uint16 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x2), _start))
        }

        return tempUint;
    }

    function toUint32(bytes memory _bytes, uint _start) internal pure returns (uint32) {
        require(_bytes.length >= _start + 4, "toUint32_outOfBounds");
        uint32 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x4), _start))
        }

        return tempUint;
    }

    function toUint64(bytes memory _bytes, uint _start) internal pure returns (uint64) {
        require(_bytes.length >= _start + 8, "toUint64_outOfBounds");
        uint64 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x8), _start))
        }

        return tempUint;
    }

    function toUint96(bytes memory _bytes, uint _start) internal pure returns (uint96) {
        require(_bytes.length >= _start + 12, "toUint96_outOfBounds");
        uint96 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0xc), _start))
        }

        return tempUint;
    }

    function toUint128(bytes memory _bytes, uint _start) internal pure returns (uint128) {
        require(_bytes.length >= _start + 16, "toUint128_outOfBounds");
        uint128 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x10), _start))
        }

        return tempUint;
    }

    function toUint256(bytes memory _bytes, uint _start) internal pure returns (uint) {
        require(_bytes.length >= _start + 32, "toUint256_outOfBounds");
        uint tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x20), _start))
        }

        return tempUint;
    }

    function toBytes32(bytes memory _bytes, uint _start) internal pure returns (bytes32) {
        require(_bytes.length >= _start + 32, "toBytes32_outOfBounds");
        bytes32 tempBytes32;

        assembly {
            tempBytes32 := mload(add(add(_bytes, 0x20), _start))
        }

        return tempBytes32;
    }

    function equal(bytes memory _preBytes, bytes memory _postBytes) internal pure returns (bool) {
        bool success = true;

        assembly {
            let length := mload(_preBytes)

            // if lengths don't match the arrays are not equal
            switch eq(length, mload(_postBytes))
            case 1 {
                // cb is a circuit breaker in the for loop since there's
                //  no said feature for inline assembly loops
                // cb = 1 - don't breaker
                // cb = 0 - break
                let cb := 1

                let mc := add(_preBytes, 0x20)
                let end := add(mc, length)

                for {
                    let cc := add(_postBytes, 0x20)
                    // the next line is the loop condition:
                    // while(uint256(mc < end) + cb == 2)
                } eq(add(lt(mc, end), cb), 2) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    // if any of these checks fails then arrays are not equal
                    if iszero(eq(mload(mc), mload(cc))) {
                        // unsuccess:
                        success := 0
                        cb := 0
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }

    function equalStorage(bytes storage _preBytes, bytes memory _postBytes) internal view returns (bool) {
        bool success = true;

        assembly {
            // we know _preBytes_offset is 0
            let fslot := sload(_preBytes.slot)
            // Decode the length of the stored array like in concatStorage().
            let slength := div(and(fslot, sub(mul(0x100, iszero(and(fslot, 1))), 1)), 2)
            let mlength := mload(_postBytes)

            // if lengths don't match the arrays are not equal
            switch eq(slength, mlength)
            case 1 {
                // slength can contain both the length and contents of the array
                // if length < 32 bytes so let's prepare for that
                // v. http://solidity.readthedocs.io/en/latest/miscellaneous.html#layout-of-state-variables-in-storage
                if iszero(iszero(slength)) {
                    switch lt(slength, 32)
                    case 1 {
                        // blank the last byte which is the length
                        fslot := mul(div(fslot, 0x100), 0x100)

                        if iszero(eq(fslot, mload(add(_postBytes, 0x20)))) {
                            // unsuccess:
                            success := 0
                        }
                    }
                    default {
                        // cb is a circuit breaker in the for loop since there's
                        //  no said feature for inline assembly loops
                        // cb = 1 - don't breaker
                        // cb = 0 - break
                        let cb := 1

                        // get the keccak hash to get the contents of the array
                        mstore(0x0, _preBytes.slot)
                        let sc := keccak256(0x0, 0x20)

                        let mc := add(_postBytes, 0x20)
                        let end := add(mc, mlength)

                        // the next line is the loop condition:
                        // while(uint256(mc < end) + cb == 2)
                        for {

                        } eq(add(lt(mc, end), cb), 2) {
                            sc := add(sc, 1)
                            mc := add(mc, 0x20)
                        } {
                            if iszero(eq(sload(sc), mload(mc))) {
                                // unsuccess:
                                success := 0
                                cb := 0
                            }
                        }
                    }
                }
            }
            default {
                // unsuccess:
                success := 0
            }
        }

        return success;
    }
}

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```solidity
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 *
 * [WARNING]
 * ====
 * Trying to delete such a structure from storage will likely result in data corruption, rendering the structure
 * unusable.
 * See https://github.com/ethereum/solidity/pull/11843[ethereum/solidity#11843] for more info.
 *
 * In order to clean an EnumerableSet, you can either remove all elements one by one or create a fresh instance using an
 * array of EnumerableSet.
 * ====
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;
        // Position is the index of the value in the `values` array plus 1.
        // Position 0 is used to mean a value is not in the set.
        mapping(bytes32 => uint256) _positions;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._positions[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We cache the value's position to prevent multiple reads from the same storage slot
        uint256 position = set._positions[value];

        if (position != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 valueIndex = position - 1;
            uint256 lastIndex = set._values.length - 1;

            if (valueIndex != lastIndex) {
                bytes32 lastValue = set._values[lastIndex];

                // Move the lastValue to the index where the value to delete is
                set._values[valueIndex] = lastValue;
                // Update the tracked position of the lastValue (that was just moved)
                set._positions[lastValue] = position;
            }

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the tracked position for the deleted slot
            delete set._positions[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._positions[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        return set._values[index];
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function _values(Set storage set) private view returns (bytes32[] memory) {
        return set._values;
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(Bytes32Set storage set) internal view returns (bytes32[] memory) {
        bytes32[] memory store = _values(set._inner);
        bytes32[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(AddressSet storage set) internal view returns (address[] memory) {
        bytes32[] memory store = _values(set._inner);
        address[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }

    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

    /**
     * @dev Returns the value stored at position `index` in the set. O(1).
     *
     * Note that there are no guarantees on the ordering of values inside the
     * array, and it may change when more values are added or removed.
     *
     * Requirements:
     *
     * - `index` must be strictly less than {length}.
     */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
    }

    /**
     * @dev Return the entire set in an array
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function values(UintSet storage set) internal view returns (uint256[] memory) {
        bytes32[] memory store = _values(set._inner);
        uint256[] memory result;

        /// @solidity memory-safe-assembly
        assembly {
            result := store
        }

        return result;
    }
}

interface ILayerZeroUserApplicationConfig {
    // @notice set the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _configType - type of configuration. every messaging library has its own convention.
    // @param _config - configuration in the bytes. can encode arbitrary content.
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external;

    // @notice set the send() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setSendVersion(uint16 _version) external;

    // @notice set the lzReceive() LayerZero messaging library version to _version
    // @param _version - new messaging library version
    function setReceiveVersion(uint16 _version) external;

    // @notice Only when the UA needs to resume the message flow in blocking mode and clear the stored payload
    // @param _srcChainId - the chainId of the source chain
    // @param _srcAddress - the contract address of the source contract at the source chain
    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external;
}

interface ILayerZeroEndpoint is ILayerZeroUserApplicationConfig {
    // @notice send a LayerZero message to the specified address at a LayerZero endpoint.
    // @param _dstChainId - the destination chain identifier
    // @param _destination - the address on destination chain (in bytes). address length/format may vary by chains
    // @param _payload - a custom bytes payload to send to the destination contract
    // @param _refundAddress - if the source transaction is cheaper than the amount of value passed, refund the additional amount to this address
    // @param _zroPaymentAddress - the address of the ZRO token holder who would pay for the transaction
    // @param _adapterParams - parameters for custom functionality. e.g. receive airdropped native gas from the relayer on destination
    function send(
        uint16 _dstChainId,
        bytes calldata _destination,
        bytes calldata _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes calldata _adapterParams
    ) external payable;

    // @notice used by the messaging library to publish verified payload
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source contract (as bytes) at the source chain
    // @param _dstAddress - the address on destination chain
    // @param _nonce - the unbound message ordering nonce
    // @param _gasLimit - the gas limit for external contract execution
    // @param _payload - verified payload to send to the destination contract
    function receivePayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        address _dstAddress,
        uint64 _nonce,
        uint _gasLimit,
        bytes calldata _payload
    ) external;

    // @notice get the inboundNonce of a lzApp from a source chain which could be EVM or non-EVM chain
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function getInboundNonce(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (uint64);

    // @notice get the outboundNonce from this source chain which, consequently, is always an EVM
    // @param _srcAddress - the source chain contract address
    function getOutboundNonce(uint16 _dstChainId, address _srcAddress) external view returns (uint64);

    // @notice gets a quote in source native gas, for the amount that send() requires to pay for message delivery
    // @param _dstChainId - the destination chain identifier
    // @param _userApplication - the user app address on this EVM chain
    // @param _payload - the custom message to send over LayerZero
    // @param _payInZRO - if false, user app pays the protocol fee in native token
    // @param _adapterParam - parameters for the adapter service, e.g. send some dust native token to dstChain
    function estimateFees(
        uint16 _dstChainId,
        address _userApplication,
        bytes calldata _payload,
        bool _payInZRO,
        bytes calldata _adapterParam
    ) external view returns (uint nativeFee, uint zroFee);

    // @notice get this Endpoint's immutable source identifier
    function getChainId() external view returns (uint16);

    // @notice the interface to retry failed message on this Endpoint destination
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    // @param _payload - the payload to be retried
    function retryPayload(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        bytes calldata _payload
    ) external;

    // @notice query if any STORED payload (message blocking) at the endpoint.
    // @param _srcChainId - the source chain identifier
    // @param _srcAddress - the source chain contract address
    function hasStoredPayload(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool);

    // @notice query if the _libraryAddress is valid for sending msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getSendLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the _libraryAddress is valid for receiving msgs.
    // @param _userApplication - the user app address on this EVM chain
    function getReceiveLibraryAddress(address _userApplication) external view returns (address);

    // @notice query if the non-reentrancy guard for send() is on
    // @return true if the guard is on. false otherwise
    function isSendingPayload() external view returns (bool);

    // @notice query if the non-reentrancy guard for receive() is on
    // @return true if the guard is on. false otherwise
    function isReceivingPayload() external view returns (bool);

    // @notice get the configuration of the LayerZero messaging library of the specified version
    // @param _version - messaging library version
    // @param _chainId - the chainId for the pending config change
    // @param _userApplication - the contract address of the user application
    // @param _configType - type of configuration. every messaging library has its own convention.
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address _userApplication,
        uint _configType
    ) external view returns (bytes memory);

    // @notice get the send() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getSendVersion(address _userApplication) external view returns (uint16);

    // @notice get the lzReceive() LayerZero messaging library version
    // @param _userApplication - the contract address of the user application
    function getReceiveVersion(address _userApplication) external view returns (uint16);
}

interface ILayerZeroReceiver {
    // @notice LayerZero endpoint will invoke this function to deliver the message on the destination
    // @param _srcChainId - the source endpoint identifier
    // @param _srcAddress - the source sending contract address from the source chain
    // @param _nonce - the ordered message nonce
    // @param _payload - the signed payload is the UA bytes has encoded to be sent
    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) external;
}

/*
 * a generic LzReceiver implementation
 */
abstract contract LzApp is Ownable, ILayerZeroReceiver, ILayerZeroUserApplicationConfig {
    using BytesLib for bytes;

    // ua can not send payload larger than this by default, but it can be changed by the ua owner
    uint public constant DEFAULT_PAYLOAD_SIZE_LIMIT = 10000;

    ILayerZeroEndpoint public immutable lzEndpoint;
    mapping(uint16 => bytes) public trustedRemoteLookup;
    mapping(uint16 => mapping(uint16 => uint)) public minDstGasLookup;
    mapping(uint16 => uint) public payloadSizeLimitLookup;
    address public precrime;

    event SetPrecrime(address precrime);
    event SetTrustedRemote(uint16 _remoteChainId, bytes _path);
    event SetTrustedRemoteAddress(uint16 _remoteChainId, bytes _remoteAddress);
    event SetMinDstGas(uint16 _dstChainId, uint16 _type, uint _minDstGas);

    constructor(address _endpoint) {
        lzEndpoint = ILayerZeroEndpoint(_endpoint);
    }

    function lzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual override {
        // lzReceive must be called by the endpoint for security
        require(msg.sender == address(lzEndpoint), "LzApp: invalid endpoint caller");

        bytes memory trustedRemote = trustedRemoteLookup[_srcChainId];
        // if will still block the message pathway from (srcChainId, srcAddress). should not receive message from untrusted remote.
        require(
            _srcAddress.length == trustedRemote.length && trustedRemote.length > 0 && keccak256(_srcAddress) == keccak256(trustedRemote),
            "LzApp: invalid source sending contract"
        );

        _blockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    // abstract function - the default behaviour of LayerZero is blocking. See: NonblockingLzApp if you dont need to enforce ordered messaging
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;

    function _lzSend(
        uint16 _dstChainId,
        bytes memory _payload,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams,
        uint _nativeFee
    ) internal virtual {
        bytes memory trustedRemote = trustedRemoteLookup[_dstChainId];
        require(trustedRemote.length != 0, "LzApp: destination chain is not a trusted source");
        _checkPayloadSize(_dstChainId, _payload.length);
        lzEndpoint.send{value: _nativeFee}(_dstChainId, trustedRemote, _payload, _refundAddress, _zroPaymentAddress, _adapterParams);
    }

    function _checkGasLimit(
        uint16 _dstChainId,
        uint16 _type,
        bytes memory _adapterParams,
        uint _extraGas
    ) internal view virtual {
        uint providedGasLimit = _getGasLimit(_adapterParams);
        uint minGasLimit = minDstGasLookup[_dstChainId][_type];
        require(minGasLimit > 0, "LzApp: minGasLimit not set");
        require(providedGasLimit >= minGasLimit + _extraGas, "LzApp: gas limit is too low");
    }

    function _getGasLimit(bytes memory _adapterParams) internal pure virtual returns (uint gasLimit) {
        require(_adapterParams.length >= 34, "LzApp: invalid adapterParams");
        assembly {
            gasLimit := mload(add(_adapterParams, 34))
        }
    }

    function _checkPayloadSize(uint16 _dstChainId, uint _payloadSize) internal view virtual {
        uint payloadSizeLimit = payloadSizeLimitLookup[_dstChainId];
        if (payloadSizeLimit == 0) {
            // use default if not set
            payloadSizeLimit = DEFAULT_PAYLOAD_SIZE_LIMIT;
        }
        require(_payloadSize <= payloadSizeLimit, "LzApp: payload size is too large");
    }

    //---------------------------UserApplication config----------------------------------------
    function getConfig(
        uint16 _version,
        uint16 _chainId,
        address,
        uint _configType
    ) external view returns (bytes memory) {
        return lzEndpoint.getConfig(_version, _chainId, address(this), _configType);
    }

    // generic config for LayerZero user Application
    function setConfig(
        uint16 _version,
        uint16 _chainId,
        uint _configType,
        bytes calldata _config
    ) external override onlyOwner {
        lzEndpoint.setConfig(_version, _chainId, _configType, _config);
    }

    function setSendVersion(uint16 _version) external override onlyOwner {
        lzEndpoint.setSendVersion(_version);
    }

    function setReceiveVersion(uint16 _version) external override onlyOwner {
        lzEndpoint.setReceiveVersion(_version);
    }

    function forceResumeReceive(uint16 _srcChainId, bytes calldata _srcAddress) external override onlyOwner {
        lzEndpoint.forceResumeReceive(_srcChainId, _srcAddress);
    }

    // _path = abi.encodePacked(remoteAddress, localAddress)
    // this function set the trusted path for the cross-chain communication
    function setTrustedRemote(uint16 _remoteChainId, bytes calldata _path) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = _path;
        emit SetTrustedRemote(_remoteChainId, _path);
    }

    function setTrustedRemoteAddress(uint16 _remoteChainId, bytes calldata _remoteAddress) external onlyOwner {
        trustedRemoteLookup[_remoteChainId] = abi.encodePacked(_remoteAddress, address(this));
        emit SetTrustedRemoteAddress(_remoteChainId, _remoteAddress);
    }

    function getTrustedRemoteAddress(uint16 _remoteChainId) external view returns (bytes memory) {
        bytes memory path = trustedRemoteLookup[_remoteChainId];
        require(path.length != 0, "LzApp: no trusted path record");
        return path.slice(0, path.length - 20); // the last 20 bytes should be address(this)
    }

    function setPrecrime(address _precrime) external onlyOwner {
        precrime = _precrime;
        emit SetPrecrime(_precrime);
    }

    function setMinDstGas(
        uint16 _dstChainId,
        uint16 _packetType,
        uint _minGas
    ) external onlyOwner {
        minDstGasLookup[_dstChainId][_packetType] = _minGas;
        emit SetMinDstGas(_dstChainId, _packetType, _minGas);
    }

    // if the size is 0, it means default size limit
    function setPayloadSizeLimit(uint16 _dstChainId, uint _size) external onlyOwner {
        payloadSizeLimitLookup[_dstChainId] = _size;
    }

    //--------------------------- VIEW FUNCTION ----------------------------------------
    function isTrustedRemote(uint16 _srcChainId, bytes calldata _srcAddress) external view returns (bool) {
        bytes memory trustedSource = trustedRemoteLookup[_srcChainId];
        return keccak256(trustedSource) == keccak256(_srcAddress);
    }
}

library ExcessivelySafeCall {
    uint constant LOW_28_MASK = 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeCall(
        address _target,
        uint _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal returns (bool, bytes memory) {
        // set up for assembly call
        uint _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := call(
                _gas, // gas
                _target, // recipient
                0, // ether value
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /// @notice Use when you _really_ really _really_ don't trust the called
    /// contract. This prevents the called contract from causing reversion of
    /// the caller in as many ways as we can.
    /// @dev The main difference between this and a solidity low-level call is
    /// that we limit the number of bytes that the callee can cause to be
    /// copied to caller memory. This prevents stupid things like malicious
    /// contracts returning 10,000,000 bytes causing a local OOG when copying
    /// to memory.
    /// @param _target The address to call
    /// @param _gas The amount of gas to forward to the remote contract
    /// @param _maxCopy The maximum number of bytes of returndata to copy
    /// to memory.
    /// @param _calldata The data to send to the remote contract
    /// @return success and returndata, as `.call()`. Returndata is capped to
    /// `_maxCopy` bytes.
    function excessivelySafeStaticCall(
        address _target,
        uint _gas,
        uint16 _maxCopy,
        bytes memory _calldata
    ) internal view returns (bool, bytes memory) {
        // set up for assembly call
        uint _toCopy;
        bool _success;
        bytes memory _returnData = new bytes(_maxCopy);
        // dispatch message to recipient
        // by assembly calling "handle" function
        // we call via assembly to avoid memcopying a very large returndata
        // returned by a malicious contract
        assembly {
            _success := staticcall(
                _gas, // gas
                _target, // recipient
                add(_calldata, 0x20), // inloc
                mload(_calldata), // inlen
                0, // outloc
                0 // outlen
            )
            // limit our copy to 256 bytes
            _toCopy := returndatasize()
            if gt(_toCopy, _maxCopy) {
                _toCopy := _maxCopy
            }
            // Store the length of the copied bytes
            mstore(_returnData, _toCopy)
            // copy the bytes from returndata[0:_toCopy]
            returndatacopy(add(_returnData, 0x20), 0, _toCopy)
        }
        return (_success, _returnData);
    }

    /**
     * @notice Swaps function selectors in encoded contract calls
     * @dev Allows reuse of encoded calldata for functions with identical
     * argument types but different names. It simply swaps out the first 4 bytes
     * for the new selector. This function modifies memory in place, and should
     * only be used with caution.
     * @param _newSelector The new 4-byte selector
     * @param _buf The encoded contract args
     */
    function swapSelector(bytes4 _newSelector, bytes memory _buf) internal pure {
        require(_buf.length >= 4);
        uint _mask = LOW_28_MASK;
        assembly {
            // load the first word of
            let _word := mload(add(_buf, 0x20))
            // mask out the top 4 bytes
            // /x
            _word := and(_word, _mask)
            _word := or(_newSelector, _word)
            mstore(add(_buf, 0x20), _word)
        }
    }
}

/*
 * the default LayerZero messaging behaviour is blocking, i.e. any failed message will block the channel
 * this abstract class try-catch all fail messages and store locally for future retry. hence, non-blocking
 * NOTE: if the srcAddress is not configured properly, it will still block the message pathway from (srcChainId, srcAddress)
 */
abstract contract NonblockingLzApp is LzApp {
    using ExcessivelySafeCall for address;

    constructor(address _endpoint) LzApp(_endpoint) {}

    mapping(uint16 => mapping(bytes => mapping(uint64 => bytes32))) public failedMessages;

    event MessageFailed(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes _payload, bytes _reason);
    event RetryMessageSuccess(uint16 _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _payloadHash);

    // overriding the virtual function in LzReceiver
    function _blockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.nonblockingLzReceive.selector, _srcChainId, _srcAddress, _nonce, _payload)
        );
        if (!success) {
            _storeFailedMessage(_srcChainId, _srcAddress, _nonce, _payload, reason);
        }
    }

    function _storeFailedMessage(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload,
        bytes memory _reason
    ) internal virtual {
        failedMessages[_srcChainId][_srcAddress][_nonce] = keccak256(_payload);
        emit MessageFailed(_srcChainId, _srcAddress, _nonce, _payload, _reason);
    }

    function nonblockingLzReceive(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public virtual {
        // only internal transaction
        require(msg.sender == address(this), "NonblockingLzApp: caller must be LzApp");
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
    }

    //@notice override this function
    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual;

    function retryMessage(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes calldata _payload
    ) public payable virtual {
        // assert there is message to retry
        bytes32 payloadHash = failedMessages[_srcChainId][_srcAddress][_nonce];
        require(payloadHash != bytes32(0), "NonblockingLzApp: no stored message");
        require(keccak256(_payload) == payloadHash, "NonblockingLzApp: invalid payload");
        // clear the stored message
        failedMessages[_srcChainId][_srcAddress][_nonce] = bytes32(0);
        // execute the message. revert if it fails again
        _nonblockingLzReceive(_srcChainId, _srcAddress, _nonce, _payload);
        emit RetryMessageSuccess(_srcChainId, _srcAddress, _nonce, payloadHash);
    }
}


interface IOFTReceiverV2 {
    /**
     * @dev Called by the OFT contract when tokens are received from source chain.
     * @param _srcChainId The chain id of the source chain.
     * @param _srcAddress The address of the OFT token contract on the source chain.
     * @param _nonce The nonce of the transaction on the source chain.
     * @param _from The address of the account who calls the sendAndCall() on the source chain.
     * @param _amount The amount of tokens to transfer.
     * @param _payload Additional data with no specified format.
     */
    function onOFTReceived(uint16 _srcChainId, bytes calldata _srcAddress, uint64 _nonce, bytes32 _from, uint _amount, bytes calldata _payload) external;
}

abstract contract OFTCoreV2 is NonblockingLzApp {
    using BytesLib for bytes;
    using ExcessivelySafeCall for address;

    uint public constant NO_EXTRA_GAS = 0;

    // packet type
    uint8 public constant PT_SEND = 0;
    uint8 public constant PT_SEND_AND_CALL = 1;

    uint8 public immutable sharedDecimals;

    mapping(uint16 => mapping(bytes => mapping(uint64 => bool))) public creditedPackets;

    /**
     * @dev Emitted when `_amount` tokens are moved from the `_sender` to (`_dstChainId`, `_toAddress`)
     * `_nonce` is the outbound nonce
     */
    event SendToChain(uint16 indexed _dstChainId, address indexed _from, bytes32 indexed _toAddress, uint _amount);

    /**
     * @dev Emitted when `_amount` tokens are received from `_srcChainId` into the `_toAddress` on the local chain.
     * `_nonce` is the inbound nonce.
     */
    event ReceiveFromChain(uint16 indexed _srcChainId, address indexed _to, uint _amount);

    event CallOFTReceivedSuccess(uint16 indexed _srcChainId, bytes _srcAddress, uint64 _nonce, bytes32 _hash);

    event NonContractAddress(address _address);

    // _sharedDecimals should be the minimum decimals on all chains
    constructor(uint8 _sharedDecimals, address _lzEndpoint) NonblockingLzApp(_lzEndpoint) {
        sharedDecimals = _sharedDecimals;
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function callOnOFTReceived(
        uint16 _srcChainId,
        bytes calldata _srcAddress,
        uint64 _nonce,
        bytes32 _from,
        address _to,
        uint _amount,
        bytes calldata _payload,
        uint _gasForCall
    ) public virtual {
        require(msg.sender == address(this), "OFTCore: caller must be OFTCore");

        // send
        _amount = _transferFrom(address(this), _to, _amount);
        emit ReceiveFromChain(_srcChainId, _to, _amount);

        // call
        IOFTReceiverV2(_to).onOFTReceived{gas: _gasForCall}(_srcChainId, _srcAddress, _nonce, _from, _amount, _payload);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _estimateSendFee(
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bool _useZro,
        bytes memory _adapterParams
    ) internal view virtual returns (uint nativeFee, uint zroFee) {
        // mock the payload for sendFrom()
        bytes memory payload = _encodeSendPayload(_toAddress, _ld2sd(_amount));
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }

    function _estimateSendAndCallFee(
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bytes memory _payload,
        uint64 _dstGasForCall,
        bool _useZro,
        bytes memory _adapterParams
    ) internal view virtual returns (uint nativeFee, uint zroFee) {
        // mock the payload for sendAndCall()
        bytes memory payload = _encodeSendAndCallPayload(msg.sender, _toAddress, _ld2sd(_amount), _payload, _dstGasForCall);
        return lzEndpoint.estimateFees(_dstChainId, address(this), payload, _useZro, _adapterParams);
    }

    function _nonblockingLzReceive(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual override {
        uint8 packetType = _payload.toUint8(0);

        if (packetType == PT_SEND) {
            _sendAck(_srcChainId, _srcAddress, _nonce, _payload);
        } else if (packetType == PT_SEND_AND_CALL) {
            _sendAndCallAck(_srcChainId, _srcAddress, _nonce, _payload);
        } else {
            revert("OFTCore: unknown packet type");
        }
    }

    function _send(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal virtual returns (uint amount) {
        _checkGasLimit(_dstChainId, PT_SEND, _adapterParams, NO_EXTRA_GAS);

        (amount, ) = _removeDust(_amount);
        amount = _debitFrom(_from, _dstChainId, _toAddress, amount); // amount returned should not have dust
        require(amount > 0, "OFTCore: amount too small");

        bytes memory lzPayload = _encodeSendPayload(_toAddress, _ld2sd(amount));
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);

        emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function _sendAck(
        uint16 _srcChainId,
        bytes memory,
        uint64,
        bytes memory _payload
    ) internal virtual {
        (address to, uint64 amountSD) = _decodeSendPayload(_payload);
        if (to == address(0)) {
            to = address(0xdead);
        }

        uint amount = _sd2ld(amountSD);
        amount = _creditTo(_srcChainId, to, amount);

        emit ReceiveFromChain(_srcChainId, to, amount);
    }

    function _sendAndCall(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bytes memory _payload,
        uint64 _dstGasForCall,
        address payable _refundAddress,
        address _zroPaymentAddress,
        bytes memory _adapterParams
    ) internal virtual returns (uint amount) {
        _checkGasLimit(_dstChainId, PT_SEND_AND_CALL, _adapterParams, _dstGasForCall);

        (amount, ) = _removeDust(_amount);
        amount = _debitFrom(_from, _dstChainId, _toAddress, amount);
        require(amount > 0, "OFTCore: amount too small");

        // encode the msg.sender into the payload instead of _from
        bytes memory lzPayload = _encodeSendAndCallPayload(msg.sender, _toAddress, _ld2sd(amount), _payload, _dstGasForCall);
        _lzSend(_dstChainId, lzPayload, _refundAddress, _zroPaymentAddress, _adapterParams, msg.value);

        emit SendToChain(_dstChainId, _from, _toAddress, amount);
    }

    function _sendAndCallAck(
        uint16 _srcChainId,
        bytes memory _srcAddress,
        uint64 _nonce,
        bytes memory _payload
    ) internal virtual {
        (bytes32 from, address to, uint64 amountSD, bytes memory payloadForCall, uint64 gasForCall) = _decodeSendAndCallPayload(_payload);

        bool credited = creditedPackets[_srcChainId][_srcAddress][_nonce];
        uint amount = _sd2ld(amountSD);

        // credit to this contract first, and then transfer to receiver only if callOnOFTReceived() succeeds
        if (!credited) {
            amount = _creditTo(_srcChainId, address(this), amount);
            creditedPackets[_srcChainId][_srcAddress][_nonce] = true;
        }

        if (!_isContract(to)) {
            emit NonContractAddress(to);
            return;
        }

        // workaround for stack too deep
        uint16 srcChainId = _srcChainId;
        bytes memory srcAddress = _srcAddress;
        uint64 nonce = _nonce;
        bytes memory payload = _payload;
        bytes32 from_ = from;
        address to_ = to;
        uint amount_ = amount;
        bytes memory payloadForCall_ = payloadForCall;

        // no gas limit for the call if retry
        uint gas = credited ? gasleft() : gasForCall;
        (bool success, bytes memory reason) = address(this).excessivelySafeCall(
            gasleft(),
            150,
            abi.encodeWithSelector(this.callOnOFTReceived.selector, srcChainId, srcAddress, nonce, from_, to_, amount_, payloadForCall_, gas)
        );

        if (success) {
            bytes32 hash = keccak256(payload);
            emit CallOFTReceivedSuccess(srcChainId, srcAddress, nonce, hash);
        } else {
            // store the failed message into the nonblockingLzApp
            _storeFailedMessage(srcChainId, srcAddress, nonce, payload, reason);
        }
    }

    function _isContract(address _account) internal view returns (bool) {
        return _account.code.length > 0;
    }

    function _ld2sd(uint _amount) internal view virtual returns (uint64) {
        uint amountSD = _amount / _ld2sdRate();
        require(amountSD <= type(uint64).max, "OFTCore: amountSD overflow");
        return uint64(amountSD);
    }

    function _sd2ld(uint64 _amountSD) internal view virtual returns (uint) {
        return _amountSD * _ld2sdRate();
    }

    function _removeDust(uint _amount) internal view virtual returns (uint amountAfter, uint dust) {
        dust = _amount % _ld2sdRate();
        amountAfter = _amount - dust;
    }

    function _encodeSendPayload(bytes32 _toAddress, uint64 _amountSD) internal view virtual returns (bytes memory) {
        return abi.encodePacked(PT_SEND, _toAddress, _amountSD);
    }

    function _decodeSendPayload(bytes memory _payload) internal view virtual returns (address to, uint64 amountSD) {
        require(_payload.toUint8(0) == PT_SEND && _payload.length == 41, "OFTCore: invalid payload");

        to = _payload.toAddress(13); // drop the first 12 bytes of bytes32
        amountSD = _payload.toUint64(33);
    }

    function _encodeSendAndCallPayload(
        address _from,
        bytes32 _toAddress,
        uint64 _amountSD,
        bytes memory _payload,
        uint64 _dstGasForCall
    ) internal view virtual returns (bytes memory) {
        return abi.encodePacked(PT_SEND_AND_CALL, _toAddress, _amountSD, _addressToBytes32(_from), _dstGasForCall, _payload);
    }

    function _decodeSendAndCallPayload(bytes memory _payload)
        internal
        view
        virtual
        returns (
            bytes32 from,
            address to,
            uint64 amountSD,
            bytes memory payload,
            uint64 dstGasForCall
        )
    {
        require(_payload.toUint8(0) == PT_SEND_AND_CALL, "OFTCore: invalid payload");

        to = _payload.toAddress(13); // drop the first 12 bytes of bytes32
        amountSD = _payload.toUint64(33);
        from = _payload.toBytes32(41);
        dstGasForCall = _payload.toUint64(73);
        payload = _payload.slice(81, _payload.length - 81);
    }

    function _addressToBytes32(address _address) internal pure virtual returns (bytes32) {
        return bytes32(uint(uint160(_address)));
    }

    function _debitFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount
    ) internal virtual returns (uint);

    function _creditTo(
        uint16 _srcChainId,
        address _toAddress,
        uint _amount
    ) internal virtual returns (uint);

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal virtual returns (uint);

    function _ld2sdRate() internal view virtual returns (uint);
}

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165 {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
}

/**
 * @dev Interface of the IOFT core standard
 */
interface ICommonOFT is IERC165 {

    struct LzCallParams {
        address payable refundAddress;
        address zroPaymentAddress;
        bytes adapterParams;
    }

    /**
     * @dev estimate send token `_tokenId` to (`_dstChainId`, `_toAddress`)
     * _dstChainId - L0 defined chain id to send tokens too
     * _toAddress - dynamic bytes array which contains the address to whom you are sending tokens to on the dstChain
     * _amount - amount of the tokens to transfer
     * _useZro - indicates to use zro to pay L0 fees
     * _adapterParam - flexible bytes array to indicate messaging adapter services in L0
     */
    function estimateSendFee(uint16 _dstChainId, bytes32 _toAddress, uint _amount, bool _useZro, bytes calldata _adapterParams) external view returns (uint nativeFee, uint zroFee);

    function estimateSendAndCallFee(uint16 _dstChainId, bytes32 _toAddress, uint _amount, bytes calldata _payload, uint64 _dstGasForCall, bool _useZro, bytes calldata _adapterParams) external view returns (uint nativeFee, uint zroFee);

    /**
     * @dev returns the circulating amount of tokens on current chain
     */
    function circulatingSupply() external view returns (uint);

    /**
     * @dev returns the address of the ERC20 token
     */
    function token() external view returns (address);
}

/**
 * @dev Interface of the IOFT core standard
 */
interface IOFTV2 is ICommonOFT {

    /**
     * @dev send `_amount` amount of token to (`_dstChainId`, `_toAddress`) from `_from`
     * `_from` the owner of token
     * `_dstChainId` the destination chain identifier
     * `_toAddress` can be any size depending on the `dstChainId`.
     * `_amount` the quantity of tokens in wei
     * `_refundAddress` the address LayerZero refunds if too much message fee is sent
     * `_zroPaymentAddress` set to address(0x0) if not paying in ZRO (LayerZero Token)
     * `_adapterParams` is a flexible bytes array to indicate messaging adapter services
     */
    function sendFrom(address _from, uint16 _dstChainId, bytes32 _toAddress, uint _amount, LzCallParams calldata _callParams) external payable;

    function sendAndCall(address _from, uint16 _dstChainId, bytes32 _toAddress, uint _amount, bytes calldata _payload, uint64 _dstGasForCall, LzCallParams calldata _callParams) external payable;
}

abstract contract BaseOFTV2 is OFTCoreV2, ERC165, IOFTV2 {
    constructor(uint8 _sharedDecimals, address _lzEndpoint) OFTCoreV2(_sharedDecimals, _lzEndpoint) {}

    /************************************************************************
     * public functions
     ************************************************************************/
    function sendFrom(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        LzCallParams calldata _callParams
    ) public payable virtual override {
        _send(_from, _dstChainId, _toAddress, _amount, _callParams.refundAddress, _callParams.zroPaymentAddress, _callParams.adapterParams);
    }

    function sendAndCall(
        address _from,
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bytes calldata _payload,
        uint64 _dstGasForCall,
        LzCallParams calldata _callParams
    ) public payable virtual override {
        _sendAndCall(
            _from,
            _dstChainId,
            _toAddress,
            _amount,
            _payload,
            _dstGasForCall,
            _callParams.refundAddress,
            _callParams.zroPaymentAddress,
            _callParams.adapterParams
        );
    }

    /************************************************************************
     * public view functions
     ************************************************************************/
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IOFTV2).interfaceId || super.supportsInterface(interfaceId);
    }

    function estimateSendFee(
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bool _useZro,
        bytes calldata _adapterParams
    ) public view virtual override returns (uint nativeFee, uint zroFee) {
        return _estimateSendFee(_dstChainId, _toAddress, _amount, _useZro, _adapterParams);
    }

    function estimateSendAndCallFee(
        uint16 _dstChainId,
        bytes32 _toAddress,
        uint _amount,
        bytes calldata _payload,
        uint64 _dstGasForCall,
        bool _useZro,
        bytes calldata _adapterParams
    ) public view virtual override returns (uint nativeFee, uint zroFee) {
        return _estimateSendAndCallFee(_dstChainId, _toAddress, _amount, _payload, _dstGasForCall, _useZro, _adapterParams);
    }

    function circulatingSupply() public view virtual override returns (uint);

    function token() public view virtual override returns (address);
}

interface IERC20 {

    function totalSupply() external view returns (uint256);
    
    function symbol() external view returns(string memory);
    
    function name() external view returns(string memory);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);
    
    /**
     * @dev Returns the number of decimal places
     */
    function decimals() external view returns (uint8);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


interface IFeeReceiver {
    function trigger() external;
}

interface IDistributor {
    function setShare(address holder, uint256 balance) external;
    function process() external;
    function setRewardExempt(address wallet, bool rewardless) external;
    function pairToken(address token) external;
}

/**
    Modular Upgradeable Token
 */
contract AffinityToken is IERC20, Ownable {

    // total supply
    uint256 private _totalSupply = 860_000_000_000 * 10**18;

    // token data
    string private _name = 'Affinity';
    string private _symbol = 'AFNTY';
    uint8  private constant _decimals = 18;

    // balances
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    // Taxation on transfers
    uint256 public buyFee             = 400;
    uint256 public sellFee            = 900;
    uint256 public transferFee        = 0;
    uint256 public constant TAX_DENOM = 10000;

    // Maximum Sell Limit
    uint256 public max_sell_limit = 800_000_000_000 * 10**18;
    uint256 public max_sell_limit_duration = 12 hours;

    // Max Sell Limit Info
    struct UserInfo {
        uint256 totalSold;
        uint256 hourStarted;
        uint256 timeJoined;
    }

    // Address => Max Sell Limit Info
    mapping ( address => UserInfo ) public userInfo;

    // permissions
    struct Permissions {
        bool isFeeExempt;
        bool isLiquidityPool;
        bool isSellLimitExempt;
    }
    mapping ( address => Permissions ) public permissions;

    // Fee Recipients
    address public sellFeeRecipient;
    address public buyFeeRecipient;
    address public transferFeeRecipient;

    // Trigger Fee Recipients
    bool public triggerBuyRecipient = false;
    bool public triggerTransferRecipient = false;
    bool public triggerSellRecipient = false;

    // List of all holders
    EnumerableSet.AddressSet internal holders;

    // Whether or not the contract is paused
    bool public paused;

    // Sell Limit Enabled
    bool public sellLimitEnabled;

    // Distributor Address
    address public distributor;
    
    constructor(address distributor_) {

        // Owner
        address _owner = 0xEe3C1B43482bf018ac960EeA8B57d8e576368D57;

        // distributor
        distributor = distributor_;

        // exempt sender for tax-free initial distribution
        permissions[_owner].isFeeExempt = true;
        permissions[_owner].isSellLimitExempt = true;

        // initial supply allocation
        _balances[_owner] = _totalSupply;
        emit Transfer(address(0), _owner, _totalSupply);

        // Set Paused
        paused = true;

        // add holder
        _addHolder(_owner);

        // set share
        if (distributor != address(0)) {
            IDistributor(distributor).setShare(_owner, _balances[_owner]);
            IDistributor(distributor).pairToken(address(this));
        }
    }

    /////////////////////////////////
    /////    ERC20 FUNCTIONS    /////
    /////////////////////////////////

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    
    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public pure override returns (uint8) {
        return _decimals;
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    /** Transfer Function */
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFromInternal(msg.sender, recipient, amount);
    }

    /** Transfer Function */
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        require(
            _allowances[sender][msg.sender] >= amount,
            'Insufficient Allowance'
        );
        _allowances[sender][msg.sender] -= amount;
        return _transferFromInternal(sender, recipient, amount);
    }


    /////////////////////////////////
    /////   PUBLIC FUNCTIONS    /////
    /////////////////////////////////


    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function burnFrom(address account, uint256 amount) external {
        require(
            _allowances[account][msg.sender] >= amount,
            'Insufficient Allowance'
        );
        _allowances[account][msg.sender] -= amount;
        _burn(account, amount);
    }

    receive() external payable {
        
    }

    /////////////////////////////////
    /////    OWNER FUNCTIONS    /////
    /////////////////////////////////

    function setNameAndSymbol(string memory name_, string memory symbol_) external onlyOwner {
        _name = name_;
        _symbol = symbol_;
    }

    function setDistributor(address _distributor) external onlyOwner {
        distributor = _distributor;
    }

    function setSelllimitEnabled(bool _enabled) external onlyOwner {
        sellLimitEnabled = _enabled;
    }

    function withdraw(address token) external onlyOwner {
        require(token != address(0), 'Zero');
        bool s = IERC20(token).transfer(msg.sender, IERC20(token).balanceOf(address(this)));
        require(s);
    }

    function withdrawBNB() external onlyOwner {
        (bool s,) = payable(msg.sender).call{value: address(this).balance}("");
        require(s);
    }

    function setTransferFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero');
        transferFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        if (distributor != address(0)) {
            IDistributor(distributor).setRewardExempt(recipient, true);
        }
    }

    function setBuyFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero');
        buyFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        if (distributor != address(0)) {
            IDistributor(distributor).setRewardExempt(recipient, true);
        }
    }

    function setSellFeeRecipient(address recipient) external onlyOwner {
        require(recipient != address(0), 'Zero');
        sellFeeRecipient = recipient;
        permissions[recipient].isFeeExempt = true;
        permissions[recipient].isSellLimitExempt = true;
        if (distributor != address(0)) {
            IDistributor(distributor).setRewardExempt(recipient, true);
        }
    }

    function registerAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(!permissions[account].isLiquidityPool, 'AMM');
        permissions[account].isLiquidityPool = true;
        if (distributor != address(0)) {
            IDistributor(distributor).setRewardExempt(account, true);
        }
    }

    function unRegisterAutomatedMarketMaker(address account) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(permissions[account].isLiquidityPool, 'Not AMM');
        permissions[account].isLiquidityPool = false;
    }

    function setRewardExempt(address account, bool rewardless) external onlyOwner {
        require(account != address(0), 'Zero Address');
        require(distributor != address(0), 'No Distributor');
        IDistributor(distributor).setRewardExempt(account, rewardless);
    }

    function pause() external onlyOwner {
        paused = true;
    }

    function unPause() external onlyOwner {
        paused = false;
    }

    function setAutoTriggers(
        bool autoBuyTrigger,
        bool autoTransferTrigger,
        bool autoSellTrigger
    ) external onlyOwner {
        triggerBuyRecipient = autoBuyTrigger;
        triggerTransferRecipient = autoTransferTrigger;
        triggerSellRecipient = autoSellTrigger;
    }

    function setFees(uint _buyFee, uint _sellFee, uint _transferFee) external onlyOwner {
        require(
            _buyFee <= 2000,
            'Buy Fee Too High'
        );
        require(
            _sellFee <= 2000,
            'Sell Fee Too High'
        );
        require(
            _transferFee <= 2000,
            'Transfer Fee Too High'
        );

        buyFee = _buyFee;
        sellFee = _sellFee;
        transferFee = _transferFee;
    }

    function setFeeExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isFeeExempt = isExempt;
    }

    function setMaxSellLimitExempt(address account, bool isExempt) external onlyOwner {
        require(account != address(0), 'Zero Address');
        permissions[account].isSellLimitExempt = isExempt;
    }

    function setMaxSellLimit(uint256 newLimit) external onlyOwner {
        require(
            newLimit >= _totalSupply / 10_000,
            'Max Sell Limit Too Low'
        );
        max_sell_limit = newLimit;
    }

    function setMaxSellLimitDuration(uint256 newDuration) external onlyOwner {
        require(
            newDuration >= 10 minutes,
            'Max Sell Limit Duration Too Low'
        );
        max_sell_limit_duration = newDuration;
    }

    
    /////////////////////////////////
    /////     READ FUNCTIONS    /////
    /////////////////////////////////

    function getTax(address sender, address recipient, uint256 amount) public view returns (uint256, address, bool) {
        if ( permissions[sender].isFeeExempt || permissions[recipient].isFeeExempt ) {
            return (0, address(0), false);
        }
        return permissions[sender].isLiquidityPool ? 
               ((amount * buyFee) / TAX_DENOM, buyFeeRecipient, triggerBuyRecipient) : 
               permissions[recipient].isLiquidityPool ? 
               ((amount * sellFee) / TAX_DENOM, sellFeeRecipient, triggerSellRecipient) :
               ((amount * transferFee) / TAX_DENOM, transferFeeRecipient, triggerTransferRecipient);
    }

    function timeSinceLastSale(address user) public view returns (uint256) {
        uint256 last = userInfo[user].hourStarted;

        return last > block.timestamp ? 0 : block.timestamp - last;
    }

    function timeSinceJoined(address user) public view returns (uint256) {
        uint256 timeJoined = userInfo[user].timeJoined;
        if (timeJoined == 0) {
            return 0;
        }
        return block.timestamp > timeJoined ? block.timestamp - timeJoined : 0;
    }

    function getNumberOfHolders() external view returns (uint256) {
        return EnumerableSet.length(holders);
    }

    function getHolderAtIndex(uint256 index) external view returns (address) {
        if (EnumerableSet.length(holders) == 0) {
            return address(0);
        }
        if (index >= EnumerableSet.length(holders)) {
            index = 0;
        }
        return EnumerableSet.at(holders, index);
    }

    function viewHolderSlice(uint startIndex, uint endIndex) external view returns (address[] memory) {
        if (endIndex > EnumerableSet.length(holders)) {
            endIndex = EnumerableSet.length(holders);
        }
        if (startIndex > endIndex) {
            startIndex = endIndex;
        }
        address[] memory holderList = new address[](endIndex - startIndex);
        uint count = 0;
        for (uint i = startIndex; i < endIndex;) {
            holderList[count] = EnumerableSet.at(holders, i);
            unchecked { ++i; ++count; }
        }
        return holderList;
    }
    
    //////////////////////////////////
    /////   INTERNAL FUNCTIONS   /////
    //////////////////////////////////

    /** Internal Transfer */
    function _transferFromInternal(address sender, address recipient, uint256 amount) internal returns (bool) {
        require(
            recipient != address(0),
            'Zero Recipient'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= balanceOf(sender),
            'Insufficient Balance'
        );
        require(
            paused == false || msg.sender == this.getOwner(),
            'Paused'
        );
        
        // decrement sender balance
        _balances[sender] -= amount;

        // fee for transaction
        (uint256 fee, address feeDestination, bool trigger) = getTax(sender, recipient, amount);

        // give amount to recipient less fee
        uint256 sendAmount = amount - fee;
        require(sendAmount > 0, 'Zero Amount');

        // add / remove holders if applicable
        if (_balances[recipient] == 0) {
            _addHolder(recipient);
        }

        if (_balances[sender] == 0) {
            _removeHolder(sender);
        }

        // allocate balance
        _balances[recipient] += sendAmount;
        emit Transfer(sender, recipient, sendAmount);

        // allocate fee if any
        if (fee > 0) {

            // if recipient field is valid
            bool isValidRecipient = feeDestination != address(0) && feeDestination != address(this);

            // allocate amount to recipient
            address feeRecipient = isValidRecipient ? feeDestination : address(this);

            // add fee receiver to list if new holder
            if (_balances[feeRecipient] == 0) {
                _addHolder(feeRecipient);
            }

            // allocate fee
            _balances[feeRecipient] += fee;
            emit Transfer(sender, feeRecipient, fee);

            // if valid and trigger is enabled, trigger tokenomics mid transfer
            if (trigger && isValidRecipient) {
                IFeeReceiver(feeRecipient).trigger();
            }
        }

        // apply max sell limit if applicable
        if (permissions[recipient].isLiquidityPool && sellLimitEnabled && permissions[sender].isSellLimitExempt == false) {

            if (timeSinceLastSale(sender) >= max_sell_limit_duration) {

                // its been over the time duration, set total sold and reset timer
                userInfo[sender].totalSold = amount;
                userInfo[sender].hourStarted = block.timestamp;

            } else {
                
                // time limit has not been surpassed, increment total sold
                unchecked {
                    userInfo[sender].totalSold += amount;
                }

            }

            // ensure max limit is preserved
            require(
                userInfo[sender].totalSold <= max_sell_limit,
                'Sell Exceeds Max Sell Limit'
            );

        }

        if (distributor != address(0)) {
            IDistributor(distributor).setShare(sender, _balances[sender]);
            IDistributor(distributor).setShare(recipient, _balances[recipient]);
            IDistributor(distributor).process();
        }

        return true;
    }

    function _burn(address account, uint256 amount) internal returns (bool) {
        require(
            account != address(0),
            'Zero Address'
        );
        require(
            amount > 0,
            'Zero Amount'
        );
        require(
            amount <= _balances[account],
            'Insufficient Balance'
        );

        // delete from balance and supply
        _balances[account] -= amount;
        _totalSupply -= amount;

        // remove account
        if (_balances[account] == 0) {
            _removeHolder(account);
        }

        // emit transfer
        emit Transfer(account, address(0), amount);
        return true;
    }

    function _mint(address account, uint256 amount) internal {
        require(
            account != address(0),
            'Zero Address'
        );
        require(amount > 0, 'Zero Amount');

        if (_balances[account] == 0) {
            _addHolder(account);
        }

        _balances[account] += amount;
        _totalSupply += amount;

        emit Transfer(address(0), account, amount);
    }

    function _removeHolder(address holder) internal {
        if (EnumerableSet.contains(holders, holder)) {
            EnumerableSet.remove(holders, holder);
        }
        delete userInfo[holder].timeJoined;
    }

    function _addHolder(address holder) internal {
        if (!EnumerableSet.contains(holders, holder)) {
            EnumerableSet.add(holders, holder);
        }
        userInfo[holder].timeJoined = block.timestamp;
    }

    function _spendAllowance(address owner, address spender, uint256 value) internal {
        uint256 currentAllowance = _allowances[owner][spender];
        if (currentAllowance != type(uint256).max) {
            require(
                currentAllowance >= value,
                'Insufficient Allowance'
            );
            _allowances[owner][spender] -= value;
        }
    }

}

contract AffinityOFTV2 is BaseOFTV2, AffinityToken {
    uint internal immutable ld2sdRate;

    constructor(
        address _distributor,
        uint8 _sharedDecimals,
        address _lzEndpoint
    ) AffinityToken(_distributor) BaseOFTV2(_sharedDecimals, _lzEndpoint) {
        uint8 decimals = 9;
        require(_sharedDecimals <= decimals, "OFT: sharedDecimals");
        ld2sdRate = 10**(decimals - _sharedDecimals);
    }

    /************************************************************************
     * public functions
     ************************************************************************/
    function circulatingSupply() public view virtual override returns (uint) {
        return this.totalSupply();
    }

    function token() public view virtual override returns (address) {
        return address(this);
    }

    /************************************************************************
     * internal functions
     ************************************************************************/
    function _debitFrom(
        address _from,
        uint16,
        bytes32,
        uint _amount
    ) internal virtual override returns (uint) {
        address spender = msg.sender;
        if (_from != spender) _spendAllowance(_from, spender, _amount);
        _burn(_from, _amount);
        return _amount;
    }

    function _creditTo(
        uint16,
        address _toAddress,
        uint _amount
    ) internal virtual override returns (uint) {
        _mint(_toAddress, _amount);
        return _amount;
    }

    function _transferFrom(
        address _from,
        address _to,
        uint _amount
    ) internal override returns (uint) {
        address spender = msg.sender;
        // if transfer from this contract, no need to check allowance
        if (_from != address(this) && _from != spender) _spendAllowance(_from, spender, _amount);
        _transferFromInternal(_from, _to, _amount);
        return _amount;
    }

    function _ld2sdRate() internal view virtual override returns (uint) {
        return ld2sdRate;
    }
}