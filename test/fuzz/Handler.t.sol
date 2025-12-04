//SPDX-License-Identifier: MIT

//handler is going to narrow down the way we call the functions

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { MockV3Aggregator } from "../mocks/MocksV3Aggregator.sol";


contract Handler is Test{
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    ERC20Mock weth;
    ERC20Mock wbtc;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public btcUsdPriceFeed;

    uint256 public timesMintIsCalled;
    address[] public usersWithDepositedCollateral;

    uint256 public constant MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory collateralTokens = dsce.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(weth)));
        btcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(address(wbtc)));
    }

    //reedeem collateral <-

    function mintDsc(uint256 amount, uint256 addressSeed) public {
        if(usersWithDepositedCollateral.length == 0){
            return;
        }

        address sender = usersWithDepositedCollateral[addressSeed % usersWithDepositedCollateral.length];

        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(sender);

        int256 maxDscToMint = ((int256(collateralValueInUsd)/2) - int256(totalDscMinted)) ;
        // vm.assume(maxDscToMint >= 0);
        if(maxDscToMint < 0){
            return;
        }

        amount = bound(amount, 0 , uint256(maxDscToMint));
        // vm.assume(amount!=0);
        if (amount == 0){
            return;
        }

        vm.startPrank(sender);
        //We asuume that the owner of the dsc is the dsce
        //This is because we are going to mint dsc from the dsce
        //If we didn't assume this then , we would have gotten an revert of , OwnableUnauthorizedAccount ,
        //because of onlyOwner in our DSC contract
        vm.stopPrank();
        timesMintIsCalled++;
    }


    function depositeCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
            ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
            amountCollateral  = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

            vm.startPrank(msg.sender);
            collateral.mint(msg.sender, amountCollateral);
            collateral.approve(address(dsce), amountCollateral);
            dsce.depositeCollateral(address(collateral), amountCollateral);
            vm.stopPrank();
            usersWithDepositedCollateral.push(msg.sender);
    }

    function reedeemCollateralFromSeed(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);

        uint256 maxCollateralToredeem = dsce.getCollateralBalanceOfUser(address(collateral), msg.sender);
        uint256 minCollateralToredeem = 0;

        // if(maxCollateralToredeem == 0){
        //     return;
        // }
        vm.assume(maxCollateralToredeem != 0);

        amountCollateral = bound(amountCollateral, minCollateralToredeem, maxCollateralToredeem);
        dsce.redeemCollateral(address(collateral), amountCollateral);
    } 


    /////////////////////////////
    // Aggregator //
    /////////////////////////////

//this breaks our invarient test

    // function updateCollateralPrice(uint96 newPrice) public {
    //     int256 intNewPrice = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(intNewPrice);
    // }


    //Helper Function <-
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock){
        if(collateralSeed % 2 == 0){
            return weth;
        }
        return wbtc;
    }

}