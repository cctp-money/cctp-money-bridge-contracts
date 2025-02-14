pragma solidity 0.8.22;

import "evm-cctp-contracts/src/v2/TokenMessengerV2.sol";
import "evm-cctp-contracts/src/v2/TokenMinterV2.sol";
import "evm-cctp-contracts/src/messages/Message.sol";
import "evm-cctp-contracts/src/messages/BurnMessage.sol";
import "evm-cctp-contracts/src/v2/MessageTransmitterV2.sol";
import "evm-cctp-contracts/test/TestUtils.sol";
import "../src/TokenMessengerWrapperV2.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {MockERC20} from "./utils/MockERC20.sol";
import {SigUtils} from "./utils/SigUtils.sol";
import "evm-cctp-contracts/src/proxy/AdminUpgradableProxy.sol";

contract TokenMessengerWrapperV2Test is Test, TestUtils, GasSnapshot {
    // ============ Events ============
    event Collect(
        uint256 amountBurned,
        uint256 fee,
        uint32 source,
        uint32 dest
    );

    // ============ Errors ============
    error TokenMessengerNotSet();
    error FeeNotFound();
    error BurnAmountTooLow();
    error Unauthorized();
    error PercFeeTooHigh();

    // ============ State Variables ============
    uint32 public constant LOCAL_DOMAIN = 0;
    uint32 public constant MESSAGE_BODY_VERSION = 1;

    uint32 public constant REMOTE_DOMAIN = 4;
    bytes32 public constant REMOTE_TOKEN_MESSENGER =
        0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117;

    address public constant OWNER = address(0x1);
    address public constant COLLECTOR = address(0x2);
    address public constant FEE_UPDATER = address(0x3);
    address public constant TOKEN_ADDRESS = address(0x4);

    uint32 public constant ALLOWED_BURN_AMOUNT = 42000000;
    MockERC20 public token;
    SigUtils public sigUtils;

    TokenMinterV2 public tokenMinterV2 = new TokenMinterV2(tokenController);

    MessageTransmitterV2 public messageTransmitterV2;
    MessageTransmitterV2 messageTransmitterV2Impl;

    TokenMessengerV2 public tokenMessengerV2;
    TokenMessengerWrapperV2 public tokenMessengerWrapperV2;

    // Circle contacts
    address deployer = address(10);
    address pauser = address(20);
    address rescuer = address(30);
    address attesterManager = address(40);
    address proxyAdmin = address(50);


    // ============ Setup ============
    function setUp() public {
        token = new MockERC20();
        sigUtils = new SigUtils(token.DOMAIN_SEPARATOR());

        // Set up message transmitter
        vm.prank(OWNER);

        // Deploy implementation
        messageTransmitterV2 = new MessageTransmitterV2(LOCAL_DOMAIN, MESSAGE_BODY_VERSION);

        // Deploy proxy
        AdminUpgradableProxy _proxy = new AdminUpgradableProxy(
            address(messageTransmitterV2),
            proxyAdmin,
            bytes("")
        );
        messageTransmitterV2 = MessageTransmitterV2(address(_proxy));

        address[] memory _attesters = new address[](1);
        _attesters[0] = attester;
        messageTransmitterV2.initialize(
            deployer,
            pauser,
            rescuer,
            attesterManager,
            _attesters,
            1,
            maxMessageBodySize
        );

        // Set up token messenger
        vm.prank(OWNER);
        tokenMessengerV2 = new TokenMessengerV2(
            address(messageTransmitterV2),
            MESSAGE_BODY_VERSION
        );

        vm.prank(OWNER);
        tokenMessengerWrapperV2 = new TokenMessengerWrapperV2(
            address(tokenMessengerV2),
            LOCAL_DOMAIN,
            COLLECTOR,
            FEE_UPDATER,
            address(token)
        );

        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, REMOTE_DOMAIN, 0, 0);

        vm.prank(OWNER);
        tokenMessengerV2.addLocalMinter(address(tokenMinterV2));
        vm.prank(OWNER);
        tokenMessengerV2.addRemoteTokenMessenger(
            REMOTE_DOMAIN, REMOTE_TOKEN_MESSENGER
        );

        linkTokenPair(tokenMinterV2, address(token), REMOTE_DOMAIN, REMOTE_TOKEN_MESSENGER);
        tokenMinterV2.addLocalTokenMessenger(address(tokenMessengerV2));

        vm.prank(tokenController);

    tokenMinterV2.setMaxBurnAmountPerMessage(
            address(token), ALLOWED_BURN_AMOUNT
        );
    }

    // ============ Tests ============
    function testConstructor_rejectsZeroAddressTokenMessenger() public {
        vm.expectRevert(TokenMessengerNotSet.selector);

        tokenMessengerWrapperV2 = new TokenMessengerWrapperV2(
            address(0),
            LOCAL_DOMAIN,
            COLLECTOR,
            FEE_UPDATER,
            TOKEN_ADDRESS
        );
    }

    // depositForBurn - no fee set
    function testDepositForBurnFeeNotFound(
        uint256 _amount
    ) public {
        _amount = 4;

        bytes32 _mintRecipient = Message.addressToBytes32(address(0x10));
        uint32 destinationDomainWithNoFee = 55;

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, REMOTE_DOMAIN, 0, 3);

        vm.prank(OWNER);
        tokenMessengerV2.addRemoteTokenMessenger(
            destinationDomainWithNoFee, REMOTE_TOKEN_MESSENGER
        );

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWrapperV2), _amount);

        vm.expectRevert(FeeNotFound.selector);

        vm.prank(OWNER);
        tokenMessengerWrapperV2.depositForBurn(
            _amount,
            destinationDomainWithNoFee,
            _mintRecipient,
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED
        );
    }

    function testDepositForBurnWithTooSmallAmount(
        uint256 _amount,
        address _mintRecipient
    ) public {
        _amount = 2;

        vm.assume(_mintRecipient != address(0));
        bytes32 _mintRecipientRaw = Message.addressToBytes32(_mintRecipient);

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, REMOTE_DOMAIN, 0, 3);

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWrapperV2), _amount);

        vm.expectRevert(BurnAmountTooLow.selector);

        vm.prank(OWNER);
        tokenMessengerWrapperV2.depositForBurn(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipientRaw,
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED
        );
    }

    // depositForBurn
    function testDepositForBurnSuccess(
        uint256 _amount,
        uint64 _flatFee,
        uint16 _percFee
    ) public {

        snapStart("depositForBurnSuccess");

        vm.assume(_amount > 0);
        vm.assume(_amount <= ALLOWED_BURN_AMOUNT);
        vm.assume(_percFee > 0);
        vm.assume(_percFee < 100);
        vm.assume(_flatFee + _percFee * _amount / 10000 < _amount);

        bytes32 _mintRecipientRaw = Message.addressToBytes32(address(0x10));

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, REMOTE_DOMAIN, _percFee, _flatFee);

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWrapperV2), _amount);

        vm.expectEmit(true, true, true, true);
        uint256 fee = (_amount * _percFee / 10000) + _flatFee;
        emit Collect(_amount - fee, fee, LOCAL_DOMAIN, REMOTE_DOMAIN);

        vm.prank(OWNER);
        tokenMessengerWrapperV2.depositForBurn(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipientRaw,
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED
        );

        assertEq(0, token.balanceOf(OWNER));
        assertEq(fee, token.balanceOf(address(tokenMessengerWrapperV2)));

        snapEnd();
    }

    // depositForBurnPermit
    function testDepositForBurnPermitSuccess(
        uint256 _amount
    ) public {

        snapStart("depositForBurnPermitSuccess");

        vm.assume(_amount > 5);
        vm.assume(_amount <= ALLOWED_BURN_AMOUNT);

        uint16 _percFee = 1;
        uint64 _flatFee = 0;
        bytes32 _mintRecipient = Message.addressToBytes32(address(0x10));

        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, REMOTE_DOMAIN, _percFee, _flatFee);

        // max permit
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey); // 0xe05fcC23807536bEe418f142D19fa0d21BB0cfF7
        token.mint(owner, _amount);

        SigUtils.Permit memory permit = SigUtils.Permit({
            owner: owner,
            spender: address(tokenMessengerWrapperV2),
            value: _amount,
            nonce: token.nonces(owner),
            deadline: 1 days
        });

        bytes32 digest = sigUtils.getTypedDataHash(permit);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        uint256 feeCollected = (_percFee * _amount / 10000) + _flatFee;
        vm.expectEmit(true, true, true, true);
        emit Collect(_amount - feeCollected, feeCollected, LOCAL_DOMAIN, REMOTE_DOMAIN);

        vm.startPrank(owner);
        tokenMessengerWrapperV2.depositForBurnPermit(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipient,
            bytes32(0),
            FINALITY_THRESHOLD_FINALIZED,
            permit.deadline,
            v,
            r,
            s
        );
        vm.stopPrank();

        assertEq(0, token.balanceOf(owner));
        assertEq(feeCollected, token.balanceOf(address(tokenMessengerWrapperV2)));

        snapEnd();
    }

    function testNotFeeUpdater() public {
        vm.expectRevert(Unauthorized.selector);
        vm.prank(OWNER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, 3, 0, 0);
    }

    function testSetFeeTooHigh() public {
        vm.expectRevert(PercFeeTooHigh.selector);
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, 3, 10001, 15); // 100.01%
    }

    function testSetFeeSuccess(
        uint16 _percFee,
        uint64 _flatFee
    ) public {
        _percFee = uint16(bound(_percFee, 1, 100)); // 1%
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, 3, _percFee, _flatFee);
    }

    function testWithdrawFeesWhenNotCollector() public {
        vm.expectRevert(Unauthorized.selector);
        vm.prank(OWNER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, 3, 1, 15);
    }

    function testWithdrawFeesSuccess() public {
        vm.prank(FEE_UPDATER);
        tokenMessengerWrapperV2.setFee(FINALITY_THRESHOLD_FINALIZED, 3, 1, 15);
        assertEq(0, token.balanceOf(address(tokenMessengerWrapperV2)));
    }
}
