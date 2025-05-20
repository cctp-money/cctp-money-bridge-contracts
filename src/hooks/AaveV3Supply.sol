pragma solidity 0.8.22;

import "evm-cctp-contracts/src/v2/TokenMessengerV2.sol";
import "evm-cctp-contracts/src/v2/MessageTransmitterV2.sol";
import "evm-cctp-contracts/src/messages/v2/MessageV2.sol";
import "evm-cctp-contracts/src/messages/v2/BurnMessageV2.sol";
import "lib/solmate/src/auth/Owned.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {ERC20 as SolmateERC20} from "solmate/tokens/ERC20.sol";
import "aave-v3-core/contracts/protocol/pool/Pool.sol";
import "solmate/utils/ReentrancyGuard.sol";
using SafeTransferLib for SolmateERC20;
import {TypedMemView} from "evm-cctp-contracts/lib/memview-sol/contracts/TypedMemView.sol";
using TypedMemView for bytes;
using TypedMemView for bytes29;

/**
 * @title AaveV3Deposit
 * @notice An immutable contract called after a DepositForBurnWithHook on the destination chain.
 * Mints USDC to this address, calls function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
 * On failure to deposit, send to address specified in the payload.
 *
 */

// TODO should we charge a small amount for gas?

contract AaveV3Supply is Owned, ReentrancyGuard {
    // ============ Events ============
//    event Route( // TODO
//        uint256 amount,
//        uint32 sourceDomain,
//        address finalRecipient
//    );

    event DepositSuccess();
    event DepositFailure();

    // ============ Errors ============
    error CallerNotRelayer();
    error AddressNotSet();
    error MintFailure();
    error InvalidCctpVersion();
    error InvalidDomain();
    error NotUSDC();
    error InvalidHook();


    // ============ State Variables ============
    MessageTransmitterV2 public immutable messageTransmitterV2;
    Pool public immutable aavePool;
    uint32 public immutable currentDomainId;
    address public immutable usdcAddress;
    address public immutable relayer; // allowed caller

    // ============ Modifiers ==============
    modifier onlyRelayer() {
        if (msg.sender != relayer) revert CallerNotRelayer();
        _;
    }


    // ============ Constructor ============
    /**
     * @param _currentDomainId the domain id this contract is deployed on
     * @param _aavePool AaveV3 pool for USDC on this domain
     * @param _currentDomainId CCTP domain ID
     * @param _usdcAddress erc20 token address for this domain
     * @param _relayer USDC address that can call this contract
     */
    constructor(
        address _messageTransmitterV2,
        address _aavePool,
        uint32 _currentDomainId,
        address _usdcAddress,
        address _relayer
    ) Owned(msg.sender) {
        if (
            _messageTransmitterV2 == address(0) ||
            _aavePool    == address(0) ||
            _usdcAddress == address(0) ||
            _relayer     == address(0)
        ) revert AddressNotSet();

        messageTransmitterV2 = MessageTransmitterV2(_messageTransmitterV2);
        aavePool = Pool(_aavePool);
        currentDomainId = _currentDomainId;
        usdcAddress = _usdcAddress;
        relayer = _relayer;
    }

    // ============ External Functions ============
    /**
     * @notice Wrapper function for MessageTransmitter.receiveMessage()
     *
     * Note: if the hook message is invalid, we have no way of minting to the
     * recipient, so we will not proceed with the mint.
     *
     * @param message - CCTP V2 Message
     * @param attestation - attestation from Circle
     */
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external nonReentrant {

        // TODO check relayer

        // 1. Parse and validate message/burn message/hook before mint
        bytes29 view_ = message.ref(0);
        MessageV2._validateMessageFormat(view_);
        if(MessageV2._getVersion(view_) != 1) { // V1 = "0", V2 = "1"
            revert InvalidCctpVersion();
        }
        if(MessageV2._getDestinationDomain(view_) != currentDomainId) {
            revert InvalidDomain();
        }

        // validate burn message, version, burn token
        bytes29 msgBody = MessageV2._getMessageBody(view_);
        BurnMessageV2._validateBurnMessageFormat(msgBody);
        if(BurnMessageV2._getVersion(msgBody) != 1) {
            revert InvalidCctpVersion();
        }
        bytes32 burnToken = BurnMessageV2._getBurnToken(msgBody);
        if (address(uint160(uint256(burnToken))) != usdcAddress) {
            revert NotUSDC();
        }

        uint256 remainingTokens = BurnMessageV2._getAmount(msgBody) - BurnMessageV2._getFeeExecuted(msgBody);
        if(remainingTokens < 1_000_000) {
            // TODO add threshold.  think about minimum deposit size.
            // TODO should we collect a fee for gas (at 1.7 gwei, $1.40 for mainnet?
        }

        // validate hook data format
        address finalMintRecipient = _decodeHookRecipient(msgBody); // reverts on bad hook

        // 2. Mint USDC into this contract
        if(!messageTransmitterV2.receiveMessage(message, attestation)) {
            revert MintFailure();
        }

        // 3. Try to supply to Aave
        // TODO use supply with permit to avoid approve?
        // https://aave.com/docs/developers/smart-contracts/pool#write-methods-supplywithpermit

        SolmateERC20 token = SolmateERC20(usdcAddress);
        token.safeApprove(address(aavePool), remainingTokens); // TODO just set to 0

        try aavePool.supply(usdcAddress, remainingTokens, finalMintRecipient, 0) {
            token.safeApprove(address(aavePool), 0);
            emit DepositSuccess();
        } catch {
            token.safeApprove(address(aavePool), 0);
            token.safeTransfer(finalMintRecipient, remainingTokens);
            emit DepositFailure();
        }
    }

    // admin sweep in case funds are stuck
    function sweep(address token, address to) external onlyOwner {
        uint256 bal = SolmateERC20(token).balanceOf(address(this));
        if (token == usdcAddress && bal > 0) revert(); // USDC invariant
        SolmateERC20(token).safeTransfer(to, bal);
    }

    // offset | data
    // 0      | finalMintRecipient bytes32 (12 0's + 20 byte address)
    function _decodeHookRecipient(bytes29 body) internal pure returns (address rec) {
        bytes29 hook = BurnMessageV2._getHookData(body);

        if (hook.length != 32) revert InvalidHook();

        // Check top 96 bits are zero (i.e. left-padded zeros)
        uint256 rawValue = hook.indexUint(0, 32);
        if (rawValue >> 160 != 0) revert InvalidHook();

        // Decode address from the lower 20 bytes
        rec = abi.decode(hook.clone(), (address));
        if (rec == address(0)) revert InvalidHook();
    }

}
// use circle's libs for getMintRecipientAmount
// checksum guard eip 55 in client/relayer
//
