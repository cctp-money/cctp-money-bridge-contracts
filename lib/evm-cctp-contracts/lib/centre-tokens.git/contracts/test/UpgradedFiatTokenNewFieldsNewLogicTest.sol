/**
 * SPDX-License-Identifier: MIT
 *
 * Copyright (c) 2018 zOS Global Limited.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

pragma solidity 0.8.22;

import { FiatTokenV1 } from "../v1/FiatTokenV1.sol";

/**
 * @title UpgradedFiatTokenNewFieldsNewLogicTest
 * @dev ERC20 Token backed by fiat reserves
 */
contract UpgradedFiatTokenNewFieldsNewLogicTest is FiatTokenV1 {
    bool public newBool;
    address public newAddress;
    uint256 public newUint;
    bool internal initializedV2;

    function initialize(
        string calldata tokenName,
        string calldata tokenSymbol,
        string calldata tokenCurrency,
        uint8 tokenDecimals,
        address newMasterMinter,
        address newPauser,
        address newBlacklister,
        address newOwner,
        bool _newBool,
        address _newAddress,
        uint256 _newUint
    ) external {
        super.initialize(
            tokenName,
            tokenSymbol,
            tokenCurrency,
            tokenDecimals,
            newMasterMinter,
            newPauser,
            newBlacklister,
            newOwner
        );
        initV2(_newBool, _newAddress, _newUint);
    }

    function initV2(
        bool _newBool,
        address _newAddress,
        uint256 _newUint
    ) public {
        require(!initializedV2, "contract is already initialized");
        newBool = _newBool;
        newAddress = _newAddress;
        newUint = _newUint;
        initializedV2 = true;
    }

    function setNewAddress(address _newAddress) external {
        newAddress = _newAddress;
    }
}
