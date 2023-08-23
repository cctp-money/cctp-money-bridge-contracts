//SPDX-License-Identifier: UNLICENSED

pragma solidity 0.7.6;

interface ITokenMessengerWithMetadata {
    function depositForBurn(
        uint64 channel,
        bytes32 destinationRecipient,
        uint256 amount,
        bytes32 mintRecipient,
        address burnToken,
        bytes calldata memo
    ) external returns (uint64 nonce);

    function rawDepositForBurn(
        uint256 amount,
        bytes32 mintRecipient,
        address burnToken,
        bytes memory metadata
    ) external returns (uint64 nonce);

    function depositForBurnWithCaller(
        uint64 channel,
        bytes32 destinationRecipient,
        uint256 amount,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        bytes calldata memo
    ) external returns (uint64 nonce);

    function rawDepositForBurnWithCaller(
        uint256 amount,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller,
        bytes memory metadata
    ) external returns (uint64 nonce);
}