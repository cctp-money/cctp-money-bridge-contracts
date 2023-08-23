// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console2} from "forge-std/Test.sol";
import {Deposit} from "../src/Deposit.sol";
import "evm-cctp-contracts/src/TokenMessenger.sol";
import "../src/interfaces/ITokenMessengerWithMetadata.sol";
import {StdUtils} from "../lib/forge-std/src/StdUtils.sol";

contract DepositTest is Test {
    Deposit public deposit;

    TokenMessenger public tokenMessenger;
    ITokenMessengerWithMetadata public tokenMessengerWithMetadata;
    address payable collector = address(0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117);
    uint32 domain = 0;

    address testnetUsdc = address(0x00000000000000000000000007865c6e87b9f70255377e024ace6630c1eaa37f);
    bytes32 mintRecipient = 0x00000000000000000000000057d4eaf1091577a6b7d121202afbd2808134f117;


    function setUp() public {
        tokenMessenger = new TokenMessenger(
            collector,
            1
        );

        tokenMessengerWithMetadata = ITokenMessengerWithMetadata(collector);

        deposit = new Deposit(
            address(tokenMessenger),
            address(tokenMessengerWithMetadata),
            collector,
            4
        );

       deal(testnetUsdc, msg.sender, 20000000);
    }

    function testCalculateFee() public {
        deposit.updateFee(4, 0, 500000); // $5 fee for Noble
        
        deposit.depositForBurn(
            12000000, // $12
            uint32(4), 
            mintRecipient,
            testnetUsdc
        );

        //vm.expectEmit()
    }
}
