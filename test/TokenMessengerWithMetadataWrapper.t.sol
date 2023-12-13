pragma solidity 0.8.22;

import "evm-cctp-contracts/src/TokenMessenger.sol";
import "evm-cctp-contracts/src/messages/Message.sol";
import "evm-cctp-contracts/src/messages/BurnMessage.sol";
import "evm-cctp-contracts/src/MessageTransmitter.sol";
import "evm-cctp-contracts/test/TestUtils.sol";
import "../src/TokenMessengerWithMetadataWrapper.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";

contract TokenMessengerWithMetadataWrapperTest is Test, TestUtils, GasSnapshot {
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)")
    bytes32 constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;

    // ============ Events ============
    event Collect(
        bytes32 mintRecipient, 
        uint256 amountBurned, 
        uint256 fee,
        uint32 source, 
        uint32 dest
    );

    // ============ Errors ============
    error TokenMessengerNotSet();
    error TokenNotSupported();
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
    MockMintBurnToken public token = new MockMintBurnToken();
    TokenMinter public tokenMinter = new TokenMinter(tokenController);

    MessageTransmitter public messageTransmitter = new MessageTransmitter(
            LOCAL_DOMAIN,
            attester,
            maxMessageBodySize,
            version
        );

    TokenMessenger public tokenMessenger;
    TokenMessengerWithMetadata public tokenMessengerWithMetadata;
    TokenMessengerWithMetadataWrapper public tokenMessengerWithMetadataWrapper;

    // ============ Setup ============
    function setUp() public {
        tokenMessenger = new TokenMessenger(
            address(messageTransmitter),
            MESSAGE_BODY_VERSION
        );
        tokenMessengerWithMetadata = new TokenMessengerWithMetadata(
            address(tokenMessenger),
            4,
            bytes32(0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117)
        );

        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper = new TokenMessengerWithMetadataWrapper(
            address(tokenMessenger),
            address(tokenMessengerWithMetadata),
            LOCAL_DOMAIN,
            COLLECTOR,
            FEE_UPDATER,
            address(token)
        );

        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, 0, 0);

        tokenMessenger.addLocalMinter(address(tokenMinter));
        tokenMessenger.addRemoteTokenMessenger(
            REMOTE_DOMAIN, REMOTE_TOKEN_MESSENGER
        );

        linkTokenPair(tokenMinter, address(token), REMOTE_DOMAIN, REMOTE_TOKEN_MESSENGER);
        tokenMinter.addLocalTokenMessenger(address(tokenMessenger));

        vm.prank(tokenController);
        tokenMinter.setMaxBurnAmountPerMessage(
            address(token), ALLOWED_BURN_AMOUNT
        );
    }

    // ============ Tests ============
    function testConstructor_rejectsZeroAddressTokenMessenger() public {
        vm.expectRevert(TokenMessengerNotSet.selector);

        tokenMessengerWithMetadataWrapper = new TokenMessengerWithMetadataWrapper(
            address(0),
            address(address(tokenMessengerWithMetadata)),
            LOCAL_DOMAIN,
            COLLECTOR,
            FEE_UPDATER,
            TOKEN_ADDRESS
        );
    }

    // depositForBurn - no fee set
    function testDepositForBurnFeeNotFound(
        uint256 _amount,
        address _mintRecipient
    ) public {
        _amount = 4;

        vm.assume(_mintRecipient != address(0));
        bytes32 _mintRecipientRaw = Message.addressToBytes32(_mintRecipient);

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, 0, 3);

        tokenMessenger.addRemoteTokenMessenger(
            55, REMOTE_TOKEN_MESSENGER
        );

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWithMetadataWrapper), _amount);

        vm.expectRevert(FeeNotFound.selector);

        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.depositForBurn(
            _amount,
            55,
            _mintRecipientRaw,
            bytes32(0)
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
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, 0, 3);

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWithMetadataWrapper), _amount);

        vm.expectRevert(BurnAmountTooLow.selector);

        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.depositForBurn(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipientRaw,
            bytes32(0)
        );
    }

    // depositForBurn
    function testDepositForBurnSuccess(
        uint256 _amount,
        uint16 _percFee,
        uint64 _flatFee
    ) public {

        snapStart("depositForBurnSuccess");

        vm.assume(_amount > 0);
        vm.assume(_amount <= ALLOWED_BURN_AMOUNT);
        vm.assume(_percFee > 0);
        vm.assume(_percFee <= 100);
        vm.assume(_flatFee + _percFee * _amount / 10000 < _amount);

        bytes32 _mintRecipientRaw = Message.addressToBytes32(address(0x10));

        uint256 privateKey = 0xACAB;
        address burner = vm.addr(privateKey);
        uint256 deadline = block.timestamp + 1312;
        uint256 cost = 10 ether;

        bytes32 typedData = keccak256(abi.encode(PERMIT_TYPEHASH, burner, address(tokenMessengerWithMetadataWrapper)), cost, token.getNonce(burner), deadline);
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.getDomainSeparator(), typedData()));
        vm.prank(burner);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);

        token.mint(burner, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, _percFee, _flatFee);

        vm.expectEmit(true, true, true, true);
        uint256 fee = (_amount * _percFee / 10000) + _flatFee;
        emit Collect(_mintRecipientRaw, _amount - fee, fee, LOCAL_DOMAIN, REMOTE_DOMAIN);

        vm.prank(burner);
        tokenMessengerWithMetadataWrapper.depositForBurn(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipientRaw,
            bytes32(0),
            deadline,
            v,
            r,
            s
        );

        assertEq(0, token.balanceOf(OWNER));
        assertEq(fee, token.balanceOf(address(tokenMessengerWithMetadataWrapper)));

        snapEnd();
    }

    // depositForBurn with caller
    function testDepositForBurnWithCallerSuccess(
        uint256 _amount,
        uint16 _percFee,
        uint64 _flatFee
    ) public {

        vm.assume(_amount > 0);
        vm.assume(_amount <= ALLOWED_BURN_AMOUNT);
        vm.assume(_percFee > 0);
        vm.assume(_percFee <= 100);
        vm.assume(_flatFee + _percFee * _amount / 10000 < _amount);

        bytes32 _mintRecipientRaw = Message.addressToBytes32(address(0x10));

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, _percFee, _flatFee);

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWithMetadataWrapper), _amount);

        vm.expectEmit(true, true, true, true);
        uint256 fee = (_amount * _percFee / 10000) + _flatFee;
        emit Collect(_mintRecipientRaw, _amount - fee, fee, LOCAL_DOMAIN, REMOTE_DOMAIN);

        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.depositForBurn(
            _amount,
            REMOTE_DOMAIN,
            _mintRecipientRaw,
            0x0000000000000000000000000000000000000000000000000000000000000001
        );

        assertEq(0, token.balanceOf(OWNER));
        assertEq(fee, token.balanceOf(address(tokenMessengerWithMetadataWrapper)));
    }

    // depositForBurnIBC
    function testDepositForBurnIBCSuccess(
        uint256 _amount,
        uint16 _percFee,
        uint64 _flatFee
    ) public {
        vm.assume(_amount > 0);
        vm.assume(_amount <= ALLOWED_BURN_AMOUNT);
        vm.assume(_percFee > 0);
        vm.assume(_percFee <= 100);
        vm.assume(_flatFee + _percFee * _amount / 10000 < _amount);

        bytes32 _mintRecipientRaw = Message.addressToBytes32(address(0x10));

        token.mint(OWNER, _amount);
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(REMOTE_DOMAIN, _percFee, _flatFee);

        vm.prank(OWNER);
        token.approve(address(tokenMessengerWithMetadataWrapper), _amount);

        vm.expectEmit(true, true, true, true);
        uint256 fee = (_amount * _percFee / 10000) + _flatFee;
        emit Collect(_mintRecipientRaw, _amount - fee, fee, LOCAL_DOMAIN, REMOTE_DOMAIN);

        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.depositForBurnIBC(
            uint64(0),
            bytes32(0),
            bytes32(0),
            _amount,
            _mintRecipientRaw,
            bytes32(0),
            ""
        );

        assertEq(0, token.balanceOf(OWNER));
        assertEq(fee, token.balanceOf(address(tokenMessengerWithMetadataWrapper)));
    }

    function testNotFeeUpdater() public {
        vm.expectRevert(Unauthorized.selector);
        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.setFee(3, 0, 0);
    }

    function testSetFeeTooHigh() public {
        vm.expectRevert(PercFeeTooHigh.selector);
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(3, 10001, 15); // 100.01%
    }

    function testSetFeeSuccess(
        uint16 _percFee,
        uint64 _flatFee
    ) public {
        _percFee = uint16(bound(_percFee, 1, 100)); // 1%
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(3, _percFee, _flatFee);
    }

    function testWithdrawFeesWhenNotCollector() public {
        vm.expectRevert(Unauthorized.selector);
        vm.prank(OWNER);
        tokenMessengerWithMetadataWrapper.setFee(3, 1, 15);
    }

    function testWithdrawFeesSuccess() public {
        vm.prank(FEE_UPDATER);
        tokenMessengerWithMetadataWrapper.setFee(3, 1, 15);
        assertEq(0, token.balanceOf(address(tokenMessengerWithMetadataWrapper)));
    }
}
