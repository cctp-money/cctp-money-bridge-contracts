// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Deposit} from "../src/Deposit.sol";
import "../src/interfaces/ITokenMessenger.sol";
import "../src/interfaces/ITokenMessengerWithMetadata.sol";
import "../lib/evm-cctp-contracts/test/mocks/MockMintBurnToken.sol";


contract DepositTest is Test {
    event Burn(address sender, uint32 source, uint32 dest, address indexed token, uint256 indexed amountBurned, uint256 indexed fee);

    Deposit public deposit;

    ITokenMessenger public tokenMessenger;
    ITokenMessengerWithMetadata public tokenMessengerWithMetadata;

    address public depositorAddress = address(0x1);
    address public mockTokenMessengerAddress = address(0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117);
    address public mockTokenMessengerWithMetadataAddress = address(0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117);

    address payable collector = address(0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117);
    uint32 domain = 0;

    address testnetUsdc = address(0x00000000000000000000000007865c6e87b9f70255377e024ace6630c1eaa37f);
    bytes32 mintRecipient = 0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117;

    MockMintBurnToken public token = new MockMintBurnToken();

    function setUp() public {

        deposit = new Deposit(
            mockTokenMessengerAddress,
            mockTokenMessengerWithMetadataAddress,
            collector,
            0
        );

        
    }

    function testCalculateFee() public {
        deposit.updateFee(4, 0, 500000); // $5 fee for Noble

        // vm.expectEmit(true, true, false, true);
        // emit Burn(
        //     msg.sender, 
        //     0,
        //     4, 
        //     testnetUsdc, 
        //     7000000, 
        //     5000000);

        token.mint(depositorAddress, 20000000);

        vm.prank(depositorAddress);
        token.approve(address(depositorAddress), 20000000);

        vm.prank(depositorAddress);
        deposit.depositForBurn(
            12000000, // $12
            uint32(4), 
            mintRecipient,
            testnetUsdc
        );

    }
}
