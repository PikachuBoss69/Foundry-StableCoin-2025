//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

//Have our invariants aka properties of system

//What are Invariants?

//1. The total supply of stablecoins should always be less than  to the total value of the collateral backing them.
//2. Getter View functions should never revert <- evergreen invariants

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {HelperConfig} from "../../script/Helperconfig.s.sol";
import {Handler} from "./Handler.t.sol";
// import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract InvariantsTest is StdInvariant {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    Handler handler;
    address weth;
    address wbtc;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        // transfer token ownership to DSCEngine so DSCEngine can mint/burn

        dsc.transferOwnership(address(dsce));

        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValuethanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

        uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("Total Supply:", totalSupply);

        console.log("WETH Value:", wethValue);
        console.log("WBTC Value:", wbtcValue);
        console.log("Times mint is called:", handler.timesMintIsCalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    // function invariant_getterFunctionsShouldNotRevert(address token, uint256 usdAmountInwei, uint256 amount, uint256 totalDscMintedInUsd, uint256 totalCollateralValueInUsd) public view {
    //     dsce.getTokenAmountFromUsd(token, usdAmountInwei);
    //     dsce.getAccountInformation(msg.sender);
    //     dsce.getAccountcollateralValue(msg.sender);
    //     dsce.getUsdValue(token, amount);
    //     dsce.getHealthFactor(msg.sender);
    //     dsce.claculateHealthFactor(totalDscMintedInUsd, totalCollateralValueInUsd);
    //     dsce.getDsc();
    //     dsce.getLiquidationThreshold();
    //     dsce.getLiquidationBonus();
    //     dsce.getMinHealthFactor();
    //     dsce.getTotalDscMinted(msg.sender);
    //     dsce.getCollateralBalanceOfUser(msg.sender, token);
    //     dsce.getCollateralTokens();
    //     dsce.getCollateralTokenPriceFeed(token);
    // }
}
