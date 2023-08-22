//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.19;

import "./interfaces/ITokenMessenger.sol";
import "./interfaces/ITokenMessengerWithMetadata.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * This contract collects fees and wraps 6 external contract functions.
 * 
 * depositForBurn - a normal burn
 * depositForBurnWithCaller - only the destination caller address can mint
 * 
 * We can also specify IBC forwarding metadata for minting on Noble chain or IBC connected chains:
 * 
 * depositForBurnWithMetadata - explicit parameters
 * rawDepositForBurnWithMetadata - paramaters are packed into a byte array
 * depositForBurnWithCallerWithMetadata - explicit parameters with destination caller
 * rawDepositForBurnWithCallerWithMetadata - byte array parameters with destination caller
 */
contract Deposit {

    // an address that is used to update parameters
    address public owner;

    // the address where fees are sent
    address payable public collector;

    // the domain id this contract is deployed on
    bytes32 public immutable domain;

    // Noble domain id
    bytes32 public immutable nobleDomainId;

    struct Fee {
        // percentage fee in bips
        uint256 percFee;
        // flat fee in uusdc (1 usdc = 10^6 uusdc)
        uint256 flatFee;
    }

    // mapping of destination domain -> fee
    mapping(uint32 => Fee) public feeMap;

    // cctp token messenger contract
    ITokenMessenger public tokenMessenger;

    // ibc forwarding wrapper contract
    ITokenMessengerWithMetadata public tokenMessengerWithMetadata;

    // TODO the event should have everything we need to mint on destination chain
    event Burn(address sender, uint32 source, uint32 dest, address indexed token, uint256 amountBurned, uint256 fee);

    constructor(
        address _tokenMessenger, 
        address _tokenMessengerWithMetadata, 
        address _collector,
        bytes32 _domain) {

        require(_tokenMessenger != address(0), "TokenMessenger not set");
        tokenMessenger = ITokenMessenger(_tokenMessenger);

        require(_tokenMessengerWithMetadata != address(0), "TokenMessengerWithMetadata not set");
        tokenMessengerWithMetadata = ITokenMessengerWithMetadata(_tokenMessengerWithMetadata);

        collector = _collector;
        domain = _domain;

        owner = msg.sender;
    }

    /**
     * Burns the token on the source chain.
     * 
     * Wraps TokenMessenger.depositForBurn
     * 
     * @param amount asdf
     * @param destinationDomain  asdf
     * @param mintRecipient  asdf
     * @param burnToken asdf
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) external {
        Fee fee = calculateFee(amount, destinationDomain);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);

        ITokenMessenger.depositForBurn(amount - fee, destinationDomain, mintRecipient, burnToken);
        emit Burn(msg.sender, domain, destinationDomain, burnToken, amount - fee, fee);
    }

    /**
     * Burns the token on the source chain
     * Specifies an address which can mint
     * 
     * Wraps TokenMessenger.depositForBurnWithCaller
     * 
     * @param amount asdf
     * @param destinationDomain  asdf
     * @param mintRecipient  asdf
     * @param burnToken asdf
     * @param destinationCaller asdf
     */
    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external {
        Fee fee = calculateFee(amount, destinationDomain);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);

        ITokenMessenger.depositForBurnWithCaller(
            amount - fee, 
            destinationDomain, 
            mintRecipient, 
            burnToken, 
            destinationCaller
        );

        emit Burn(msg.sender, domain, destinationDomain, burnToken, amount - fee, fee);
    }

    /**
     * Only for depositing to an IBC connected chain via Noble
     * 
     * Burns tokens on the source chain
     * Includes IBC forwarding instructions
     * @param channel  asdf
     * @param destinationRecipient adsf
     * @param amount asdf
     * @param mintRecipient asdf
     * @param burnToken asdf
     * @param memo sdf
     */
    function depositForBurnWithMetadata(
        uint64 channel,
        bytes32 destinationRecipient,
        uint256 amount, 
        bytes32 mintRecipient, 
        address burnToken,
        bytes calldata memo
    ) external {
        Fee fee = calculateFee(amount, nobleDomainId);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);
        
        ITokenMessengerWithMetadata.depositForBurn(
            channel,
            destinationRecipient,
            amount - fee,
            mintRecipient,
            burnToken,
            memo
        );

        emit Burn(msg.sender, domain, nobleDomainId, burnToken, amount - fee, fee);
    }

    /**
     * Only for depositing to an IBC connected chain via Noble
     * 
     * Burns tokens on the source chain
     * Includes IBC forwarding instructions
     */
    function rawDepositForBurnWithMetadata(
        uint256 amount, 
        bytes32 mintRecipient, 
        address burnToken,
        bytes memory metadata
    ) external {
        Fee fee = calculateFee(amount, nobleDomainId);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);
        
        ITokenMessengerWithMetadata.rawDepositForBurn(
            amount - fee,
            mintRecipient,
            burnToken,
            metadata
        );

        emit Burn(msg.sender, domain, nobleDomainId, burnToken, amount - fee, fee);
    }

    /**
     * Only for depositing to an IBC connected chain via Noble
     * 
     * Burns tokens on the source chain
     * Specifies an address which can mint
     * Includes IBC forwarding instructions
     * 
     * @param channel  asdf
     * @param destinationRecipient adsf
     * @param amount asdf
     * @param mintRecipient asdf
     * @param burnToken asdf
     * @param destinationCaller asdf
     * @param memo sdf
     */
    function depositForBurnWithCallerWithMetadata(
        uint64 channel,
        bytes32 destinationRecipient,
        uint256 amount, 
        bytes32 mintRecipient, 
        address burnToken,
        bytes32 destinationCaller,
        bytes calldata memo
    ) external {
        Fee fee = calculateFee(amount, nobleDomainId);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);
        
        ITokenMessengerWithMetadata.depositForBurnWithCaller(
            channel,
            destinationRecipient,
            amount - fee,
            mintRecipient,
            burnToken,
            destinationCaller,
            memo
        );

        emit Burn(msg.sender, domain, nobleDomainId, burnToken, amount - fee, fee);
    }

   /**
    * Only for depositing to an IBC connected chain via Noble
    * 
    * Burns tokens on the source chain
    * Specifies an address which can mint
    * Includes IBC forwarding instructions
    * 
    * @param amount asdf
    * @param mintRecipient asdf
    * @param burnToken asdf
    * @param destinationCaller asdf
    * @param metadata asdf
    */
    function rawDepositForBurnWithCallerWithMetadata(
        uint256 amount, 
        bytes32 mintRecipient, 
        address burnToken,
        bytes32 destinationCaller,
        bytes memory metadata
    ) external {
        Fee fee = calculateFee(amount, nobleDomainId);
        IERC20(burnToken).transferFrom(msg.sender, collector, fee);
        
        ITokenMessengerWithMetadata.rawDepositForBurnWithCaller(
            amount - fee,
            mintRecipient,
            burnToken,
            destinationCaller,
            metadata
        );

        emit Burn(msg.sender, domain, nobleDomainId, burnToken, amount - fee, fee);
    }

    function calculateFee(uint256 amount, bytes32 destinationDomain) private returns (uint256) {
        Fee fee = feeMap[destinationDomain];
        return (amount * fee.percFee) + fee.flatFee;
    }

    function updateOwner(address newOwner) external {
        require(msg.sender == owner, "Only the owner can update the owner");
        owner = newOwner;
    }

    function updateCollector(address newCollector) external {
        require(msg.sender == owner, "Only the owner can update the collector");
        collector = newCollector;
    }

    function updateFee(bytes32 destinationDomain, uint256 percFee, uint256 flatFee) external {
        require(msg.sender == owner, "Only the owner can update fees");
        feeMap[destinationDomain] = Fee(percFee, flatFee);
    }
}