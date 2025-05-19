pragma solidity 0.8.22;

import "lib/evm-cctp-contracts/src/v2/TokenMessengerV2.sol";
import "lib/evm-cctp-contracts/src/v2/MessageTransmitterV2.sol";
import "lib/solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

/**
 * @title TokenMessengerWrapperV2
 * @notice A wrapper for a CCTP TokenMessenger contract that collects fees from USDC transfers.
 *
 * depositForBurn allows users to specify any destination domain
 * depositForBurnWithHook allows arbitrary data to be posted with the instruction
 * sendMessage allows arbitrary data to be sent to another chain
 *
 */
contract TokenMessengerWrapperV2 is Owned(msg.sender) {
    // ============ Events ============
    event Collect(
        uint256 amountBurned,
        uint256 fee,
        uint32 source,
        uint32 dest
    );

    // ============ Errors ============
    error TokenMessengerNotSet();
    error MessageTransmitterNotSet();
    error FeeNotFound();
    error BurnAmountTooLow();
    error Unauthorized();
    error PercFeeTooHigh();
    
    // ============ State Variables ============
    // Circle's V2 contract for burning tokens
    TokenMessengerV2 public immutable tokenMessengerV2;
    // Circle's V2 contract for sending messages
    MessageTransmitterV2 public immutable messageTransmitterV2;
    // the domain id this contract is deployed on
    uint32 public immutable currentDomainId;
    // address that can collect fees
    address public collector;
    // address that can update fees
    address public feeUpdater;
    // USDC address for this domain
    address public immutable tokenAddress;
    // threshold values for confirmed, finalized
    uint256 public constant FINALITY_THRESHOLD_CONFIRMED = 1000;
    uint256 public constant FINALITY_THRESHOLD_FINALIZED = 2000;

    struct Fee {
        // percentage fee in bips
        uint16 percFee;
        // flat fee in uusdc (1 uusdc = 10^-6 usdc)
        uint64 flatFee;
        // needed for null check
        bool isInitialized;
    }

    // keccak(destination domain id + confirmation level) -> fee
    mapping(bytes32 => Fee) public feeMap;

    // ============ Constructor ============
    /**
     * @param _tokenMessengerV2 TokenMessengerV2 address
     * @param _currentDomainId the domain id this contract is deployed on
     * @param _collector address that can collect fees
     * @param _feeUpdater address that can update fees
     * @param _tokenAddress USDC erc20 token address for this domain
     */
    constructor(
        address _tokenMessengerV2,
        address _messageTransmitterV2,
        uint32 _currentDomainId,
        address _collector,
        address _feeUpdater,
        address _tokenAddress
    ) {
        if (_tokenMessengerV2 == address(0)) {
            revert TokenMessengerNotSet();
        }
        tokenMessengerV2 = TokenMessengerV2(_tokenMessengerV2);

        if (_messageTransmitterV2 == address(0)) {
            revert MessageTransmitterNotSet();
        }
        messageTransmitterV2 = MessageTransmitterV2(_messageTransmitterV2);

        currentDomainId = _currentDomainId;
        collector = _collector;
        feeUpdater = _feeUpdater;
        tokenAddress = _tokenAddress;

        ERC20 token = ERC20(tokenAddress);
        token.approve(_tokenMessengerV2, type(uint256).max);
    }

    // ============ External Functions ============
    /**
     * @notice Wrapper function for TokenMessengerV2.depositForBurn()
     * Can specify any destination domain, including invalid ones.
     *
     * @param amount - the burn amount
     * @param destinationDomain - domain id the funds will be minted on
     * @param mintRecipient - address receiving minted tokens on destination domain
     * @param destinationCaller - the address which can call receiveMessage on the destination domain
     * @param minFinalityThreshold - 1000 for confirmed (fast), 2000 for finalized (slow)
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold
    ) external {
        // collect fee
        uint256 remainder = calculateFee(minFinalityThreshold, amount, destinationDomain);
        ERC20 token = ERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);

        tokenMessengerV2.depositForBurn(
            remainder,
            destinationDomain,
            mintRecipient,
            tokenAddress,
            destinationCaller,
            remainder-1,
            minFinalityThreshold
        );
    }

    /**
     * @notice Wrapper function for TokenMessengerV2.depositForBurn().
     * Supports EIP-20 approvals via EIP-712 secp256k1 signatures
     * Can specify any destination domain, including invalid ones.
     *
     * @param amount - the burn amount
     * @param destinationDomain - domain id the funds will be minted on
     * @param mintRecipient - address receiving minted tokens on destination domain
     * @param deadline - a timestamp after which the signature is invalid
     * @param v, r, s - components of the EIP-712 signature that proves the owner’s consent
     */
    function depositForBurnPermit(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // collect fee
        uint256 remainder = calculateFee(minFinalityThreshold, amount, destinationDomain);
        _transferAndPermit(amount, deadline, v, r, s);

        tokenMessengerV2.depositForBurn(
            remainder,
            destinationDomain,
            mintRecipient,
            tokenAddress,
            destinationCaller,
            remainder-1,
            minFinalityThreshold
        );
    }

    /**
     * @notice Wrapper function for TokenMessengerV2.depositForBurnWithHook()
     * Can specify any destination domain, including invalid ones.
     *
     * @param amount - the burn amount
     * @param destinationDomain - domain id the funds will be minted on
     * @param mintRecipient - address receiving minted tokens on destination domain
     * @param destinationCaller - the address which can call receiveMessage on the destination domain
     * @param minFinalityThreshold - 1000 for confirmed (fast), 2000 for finalized (slow)
     * @param hookData - arbitrary calldata to be handled be receiveMessage
     */
    function depositForBurnWithHook(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) external {
        // collect fee
        uint256 remainder = calculateFee(minFinalityThreshold, amount, destinationDomain);
        ERC20 token = ERC20(tokenAddress);
        token.transferFrom(msg.sender, address(this), amount);

        _depositForBurnWithHook(
            remainder,
            destinationDomain,
            mintRecipient,
            destinationCaller,
            minFinalityThreshold,
            hookData
        );
    }

    /**
     * @notice Wrapper function for TokenMessengerV2.depositForBurn().
     * Supports EIP-20 approvals via EIP-712 secp256k1 signatures
     * Can specify any destination domain, including invalid ones.
     *
     * @param amount - the burn amount
     * @param destinationDomain - domain id the funds will be minted on
     * @param mintRecipient - address receiving minted tokens on destination domain
     * @param destinationCaller - the address which can call receiveMessage on the destination domain
     * @param minFinalityThreshold - 1000 for confirmed (fast), 2000 for finalized (slow)
     * @param hookData - arbitrary calldata to be handled be receiveMessage
     */
    function depositForBurnWithHookPermit(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata hookData,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        // collect fee
        uint256 remainder = calculateFee(minFinalityThreshold, amount, destinationDomain);
        _transferAndPermit(amount, deadline, v, r, s);

        _depositForBurnWithHook(
            remainder,
            destinationDomain,
            mintRecipient,
            destinationCaller,
            minFinalityThreshold,
            hookData
        );
    }

    /**
     * @notice Wrapper function for MessageTransmitterV2.sendMessage()
     * Can specify any destination domain, including invalid ones.
     *
     * @param destinationDomain - domain id the funds will be minted on
     * @param recipient - address receiving the message on the destination domain
     * @param destinationCaller - the address which can call receiveMessage on the destination domain
     * @param minFinalityThreshold - 1000 for confirmed (fast), 2000 for finalized (slow)
     * @param messageBody - contents of the message
     */
    function sendMessage(
        uint32 destinationDomain,
        bytes32 recipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata messageBody
    ) external {
        messageTransmitterV2.sendMessage(
            destinationDomain,
            recipient,
            destinationCaller,
            minFinalityThreshold,
            messageBody
        );
    }

    function _depositForBurnWithHook(
        uint256 remainder,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        bytes32 destinationCaller,
        uint32 minFinalityThreshold,
        bytes calldata hookData
    ) internal {
        tokenMessengerV2.depositForBurnWithHook(
            remainder,
            destinationDomain,
            mintRecipient,
            tokenAddress,
            destinationCaller,
            remainder-1,
            minFinalityThreshold,
            hookData
        );
    }

    function _transferAndPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) private {
        ERC20 token = ERC20(tokenAddress);
        token.permit(msg.sender, address(this), amount, deadline, v, r, s);
        token.transferFrom(msg.sender, address(this), amount);
    }

    function calculateFee(uint32 finalityThreshold, uint256 amount, uint32 destinationDomain) private returns (uint256) {

        Fee memory entry = feeMap[keccak256(abi.encodePacked(destinationDomain, finalityThreshold))];
        if (!entry.isInitialized) {
            revert FeeNotFound();
        }

        uint256 fee = (amount * entry.percFee) / 10000 + entry.flatFee;
        if (amount <= fee) {
            revert BurnAmountTooLow();
        }

        emit Collect(amount-fee, fee, currentDomainId, destinationDomain);

        // remainder
        return (amount-fee);
    }

    /**
     * Set fee for a given destination domain.
     */
    function setFee(uint32 finalityThreshold, uint32 destinationDomain, uint16 percFee, uint64 flatFee) external {

        if (msg.sender != feeUpdater) {
            revert Unauthorized();
        }
        if (percFee > 100) { // 1%
            revert PercFeeTooHigh();
        }

        feeMap[keccak256(abi.encodePacked(destinationDomain, finalityThreshold))] = Fee(percFee, flatFee, true);
    }

    function updateOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function updateCollector(address newCollector) external onlyOwner {
        collector = newCollector;
    }

    function updateFeeUpdater(address newFeeUpdater) external onlyOwner {
        feeUpdater = newFeeUpdater;
    }

    function withdrawFees() external {
        if (msg.sender != collector) {
            revert Unauthorized();
        }
        uint256 balance = ERC20(tokenAddress).balanceOf(address(this));
        ERC20 token = ERC20(tokenAddress);
        token.transfer(collector, balance);
    }
}
