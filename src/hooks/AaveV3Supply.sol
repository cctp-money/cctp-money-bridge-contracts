pragma solidity 0.8.22;

import "lib/evm-cctp-contracts/src/v2/TokenMessengerV2.sol";
import "lib/evm-cctp-contracts/src/v2/MessageTransmitterV2.sol";
import "lib/solmate/src/auth/Owned.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {IPool} from "lib/aave-v3-core/contracts/protocol/pool/IPool.sol";

/**
 * @title AaveV3Deposit
 * @notice A contract called after a DepositForBurnWithHook on the destination chain.
 * Mints USDC to this address, calls function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
 * On failure to deposit, send to address specified in the payload.
 *
 * This contract is immutable
 */

// TODO, should the depositForBurn wrapper specify fields? A: yes
contract AaveV3Supply is Owned(msg.sender) {
    // ============ Events ============
    event Route( // TODO
        uint256 amount,
        uint32 sourceDomain,
        address finalRecipient
    );

    event DepositFailure(uint32 test);

    // ============ Errors ============
    error AddressNotSet();
    
    // ============ State Variables ============
    // Circle's V2 contract for sending messages
    MessageTransmitterV2 public immutable messageTransmitterV2;
    // AaveV3 USDC pool address
    address public immutable aavePool;
    // the domain id this contract is deployed on
    uint32 public immutable currentDomainId;
    // address that can collect fees
    address public collector;
    // address that can update fees TODO?
    address public feeUpdater;
    // USDC address for this domain
    address public immutable usdcAddress;

    // ============ Constructor ============
    /**
     * @param _currentDomainId the domain id this contract is deployed on
     * @param _collector address that can collect fees
     * @param _feeUpdater address that can update fees
     * @param _usdcAddress USDC erc20 token address for this domain
     */
    constructor(
        address _messageTransmitterV2,
        address _aaveSupplyAddress,
        uint32 _currentDomainId,
        address _collector,
        address _feeUpdater,
        address _usdcAddress
    ) {
        if (_messageTransmitterV2 == address(0)) {
            revert AddressNotSet();
        }
        messageTransmitterV2 = MessageTransmitterV2(_messageTransmitterV2);

        if(_aaveSupplyAddress == address(0)) {
            revert AddressNotSet();
        }
        aaveSupply = P



        currentDomainId = _currentDomainId;
        collector = _collector;
        feeUpdater = _feeUpdater;
        usdcAddress = _usdcAddress;

        ERC20 token = ERC20(usdcAddress);
        token.approve(_tokenMessengerV2, type(uint256).max);
    }

    // ============ External Functions ============
    /**
     * @notice Wrapper function for MessageTransmitter.receiveMessage()
     *
     * @param amount - the burn amount
     * @param destinationDomain - domain id the funds will be minted on
     * @param mintRecipient - address receiving minted tokens on destination domain
     * @param destinationCaller - the address which can call receiveMessage on the destination domain
     * @param minFinalityThreshold - 1000 for confirmed (fast), 2000 for finalized (slow)
     */
    function receiveMessage(
        bytes calldata message,
        bytes calldata attestation
    ) external {
        bool success = messageTransmitterV2.receiveMessage(message, attestation);
        if(!success) {
            // TODO exit
        }
        // tokens are transferred to this address

        // process hook
        bytes29 memory msg = _message.ref(0);
        uint32 cctpVersion = msg.slice(0, 4, 0);
        if(cctpVersion != 1) {
            // TODO fail
        }
        bytes memory msgBody = msg.slice(
            148, // MESSAGE_BODY_INDEX for CCTP v2
            _message.len() - 148,
            0
        );
        bytes32 memory burnToken = msgBody.slice(4, 36, 0);
        if(burnToken != usdcAddress) {
            // TODO
        }
        uint256 remainingTokens = msgBody.slice(68, 100, 0) - msgBody.slice(164, 196, 0);
        if(remainingTokens < 1000000) {
            // TODO add threshold.  think about minimum deposit size
        }
        bytes memory hookData = msgBody.slice(228, msgBody.len(), 0);
        // offset | data
        // 0      | finalMintRecipient address
        // TODO validate payload

        address finalMintRecipient = hookData.slice(0, 32, 0);

        // TODO maybe use supply with permit to avoid approve?
        // https://aave.com/docs/developers/smart-contracts/pool#write-methods-supplywithpermit
        ERC20 token = ERC20(usdcAddress);
        token.approve(aaveSupplyAddress, remainingTokens);
        aaveSupplyAddress.supply(burnToken, remainingTokens, finalMintRecipient, 0);


    }


    function updateOwner(address newOwner) external onlyOwner {
        owner = newOwner;
    }

    function updateCollector(address newCollector) external onlyOwner {
        collector = newCollector;
    }


    function withdrawFees() external {
        if (msg.sender != collector) {
            revert Unauthorized();
        }
        uint256 balance = ERC20(usdcAddress).balanceOf(address(this));
        ERC20 token = ERC20(usdcAddress);
        token.transfer(collector, balance);
    }
}
