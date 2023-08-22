// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {Deposit} from "../src/Deposit.sol";

contract CounterTest is Test {
    Deposit public deposit;

    function setUp() public {
        deposit = new Deposit();
    }
}
