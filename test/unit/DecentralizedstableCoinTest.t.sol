//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin dsc;

    address constant OWNER = address(1);

    function setUp() public {
        dsc = new DecentralizedStableCoin(OWNER);
    }

    function testMustMintMoreThanZero() public {
        vm.prank(OWNER);
        vm.expectRevert();
        dsc.mint(address(this), 0);
    }

    function testMustBurnMoreThanZero() public {
        vm.startPrank(OWNER);
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(0);
        vm.stopPrank();
    }

    function testCantBurnMoreThanYouHave() public {
        vm.startPrank(OWNER);
        dsc.mint(address(this), 100);
        vm.expectRevert();
        dsc.burn(101);
        vm.stopPrank();
    }

    function testCantMintToZeroAddress() public {
        vm.startPrank(OWNER);
        vm.expectRevert();
        dsc.mint(address(0), 100);
        vm.stopPrank();
    }
}
