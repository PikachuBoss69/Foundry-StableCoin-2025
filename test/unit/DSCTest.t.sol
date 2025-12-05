//SPDX-Licence-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/Helperconfig.s.sol";
import {ERC20Mock} from "../mocks/Erc20Mock.sol";
import {MockV3Aggregator} from "../mocks/MocksV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import "forge-std/Vm.sol";

contract DSCTest is Test {
    event CollateralRedeemed(address indexed redeemFrom, address indexed redeemTo, address token, uint256 amount);

    DeployDSC public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public config;

    uint256 public beforeLiquidatorBalance;
    uint256 public afterLiquidatorBalance;

    address public ethUsdPriceFeed;
    address public btcUsdPriceFeed;
    address public weth;
    address public wbtc;
    uint256 public deployerKey;

    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant AMOUNT_MINT = 100 ether; // 1000 DSC
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;
    uint256 public constant LIQUIDATION_BONUS = 10;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc,) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }
        //Transfer ownership of the DecentralizedStableCoin to the DSCEngine
        dsc.transferOwnership(address(dsce));
        assertEq(dsc.owner(), address(dsce));

        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        //USER approves the DSC Engine to spend up to 10 ETH worth of WETH on their behalf.
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositedCollateralAndMintDsc() {
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndmintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        _;
    }

    ///////////////////////
    //Constructor Tests ///
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoensntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        // Adding an extra address to priceFeedAddresses to cause a mismatch
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength.selector)
        );
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    ///////////////////////
    //Price Tests        //
    ///////////////////////

    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        // Assuming ETH price is 2000 USD
        uint256 expectedUsdValue = 15e18 * 2000;
        uint256 actualUsdValue = dsce.getUsdValue(weth, ethAmount);
        console.log("Expected USD Value: %s", expectedUsdValue);
        console.log("Actual USD Value: %s", actualUsdValue);
        assertEq(actualUsdValue, expectedUsdValue);
    }

    function testGEtToeknAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;

        uint256 expectedUsdAmount = (usdAmount) / 2000; // Assuming ETH price is 2000 USD
        uint256 actualTokenAmount = dsce.getTokenAmountFromUsd(weth, usdAmount);
        console.log("Expected Token Amount: %s", expectedUsdAmount);
        console.log("Actual Token Amount: %s", actualTokenAmount);
        assertEq(actualTokenAmount, expectedUsdAmount);
    }

    ///////////////////////////////////
    //DepositCollateral Tests        //
    ///////////////////////////////////
    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        //USER approves the DSC Engine to spend up to 10 ETH worth of WETH on their behalf.
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));

        dsce.depositeCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        //ranToken is not allowed in the DSCEngine
        //ranToken is a mock ERC20 token
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, 100 ether);
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector));
        dsce.depositeCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    function testCanDepositeCollateralAndAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dsce.getAccountInformation(USER);
        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmoount = dsce.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(expectedDepositAmoount, AMOUNT_COLLATERAL);
    }

    function testDepositeCollateralWithoutMinting() public depositedCollateral {
        uint256 totalDscMinted = dsce.getTotalDscMinted(USER);
        uint256 expectedTotalDscMinted = 0;
        assertEq(totalDscMinted, expectedTotalDscMinted);
    }

    //////////////////////////////////////////////////
    //DepositeCollateralANdMintDsc Tests            //
    //////////////////////////////////////////////////

    function testCanMintWithDepositedCollateral() public depositedCollateralAndMintDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_MINT);
    }

    function testRevertIfMintedDscBreaksHealthFactor() public {
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 amountToMint = (AMOUNT_COLLATERAL * uint256(price) * 1e10) / 1e18;
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector));
        dsce.depositeCollateralAndmintDsc(weth, AMOUNT_COLLATERAL, amountToMint);
        vm.stopPrank();
    }

    ///////////////////
    //Mint Dsc Tests //
    ///////////////////

    function testRevertsIfMintAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.mintDsc(0);
        vm.stopPrank();
    }

    function testCanMintDsc() public depositedCollateral {
        vm.prank(USER);
        dsce.mintDsc(AMOUNT_MINT);
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_MINT);
    }

    function testCannotMintWithoutDepositingCollateral() public {
        vm.startPrank(USER);

        // Do NOT deposit collateral; do NOT approve anything.
        // Try to mint — should revert because health factor will be broken.
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreakHealthFactor.selector));
        dsce.mintDsc(AMOUNT_MINT);

        vm.stopPrank();
    }

    ///////////////////
    //Burn Dsc Tests //
    ///////////////////

    function testRevertIfBurnAmountIsZero() public {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dsce.burnDsc(0);
        vm.stopPrank();
    }

    function testRevertIfNotEnoughMintedBeforeBurning() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndmintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotEnoughMinted.selector));
        dsce.burnDsc(AMOUNT_MINT + 1);
        vm.stopPrank();
    }

    function testCanBurnDsc() public depositedCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_MINT);
        dsce.burnDsc(AMOUNT_MINT);
        vm.stopPrank();

        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, 0);
    }

    ////////////////////////
    //Health Factor Tests //
    ////////////////////////

    function testProperlyReportsHealthFactor() public depositedCollateralAndMintDsc {
        // Assuming the price of WETH is 2000 USD
        (, int256 price,,,) = MockV3Aggregator(ethUsdPriceFeed).latestRoundData();
        uint256 collateralValueInUsd = (AMOUNT_COLLATERAL * uint256(price) * 1e10) / 1e18;
        uint256 effectiveCollateral = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        uint256 debt = AMOUNT_MINT;
        uint256 expectedHealthFactor = (effectiveCollateral * 1e18) / debt;
        uint256 healthFactor = dsce.getHealthFactor(USER);
        assertEq(healthFactor, expectedHealthFactor);
    }

    ////////////////////////////
    //Redeem Collateral Tests //
    ////////////////////////////

    function testRevertsIfRedeemAmountIsZero() public depositedCollateral {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector));
        dsce.redeemCollateral(weth, 0);
    }

    function testCanRedeemCollateral() public depositedCollateral {
        vm.startPrank(USER);
        uint256 userBalanceBeforeRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceBeforeRedeem, AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalanceAfterRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    //     function testEmitCollateralRedeemedWithCorrectArgs() public depositedCollateralAndMintDsc {
    //     vm.startPrank(USER);

    //     vm.expectEmit(true, true, true, false, address(dsce));
    //     emit CollateralRedeemed(USER,USER, address(weth), AMOUNT_COLLATERAL);

    //     dsce.redeemCollateral(address(weth), AMOUNT_COLLATERAL);

    //     vm.stopPrank();
    // }

    ///////////////////////////////////
    // redeemCollateralForDsc Tests //
    //////////////////////////////////
    function testMustRedeemMoreThanZero() public depositedCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dsce), AMOUNT_MINT);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.redeemCollateralForDsc(address(weth), 0, AMOUNT_MINT);
        vm.stopPrank();
    }

    function testCanRedeemDepositedCollateral() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalanceBeforeRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceBeforeRedeem, AMOUNT_COLLATERAL);
        dsce.redeemCollateral(weth, AMOUNT_COLLATERAL);
        uint256 userBalanceAfterRedeem = dsce.getCollateralBalanceOfUser(USER, weth);
        assertEq(userBalanceAfterRedeem, 0);
        vm.stopPrank();
    }

    ///////////////////////
    // Liquidation Tests //
    ///////////////////////

    function testCantLiquidateIfHealthFActorIsOk() public depositedCollateralAndMintDsc{
        // You give the liquidator some WETH tokens so they have enough collateral to attempt a liquidation.
        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);

        // ✔ A — Takes the liquidator's WETH
        // ✔ B — Locks the WETH as collateral inside the protocol
        // ✔ C — Mints DSC stablecoins, NOT WETH
        dsce.depositeCollateralAndmintDsc(weth, collateralToCover, AMOUNT_MINT);
        dsc.approve(address(dsce), AMOUNT_MINT);
        vm.expectRevert(
            DSCEngine.DSCEingine__HealthFactorIsOk.selector
        );
        dsce.liquidate(weth, USER, AMOUNT_MINT);
        vm.stopPrank();

    }

    modifier liquidated() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndmintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT);
        vm.stopPrank();
        int256 ethUsdUpdatedPrice = 18e8; // 1 ETH = $18

        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(ethUsdUpdatedPrice);
        uint256 userHealthFactor = dsce.getHealthFactor(USER);

        ERC20Mock(weth).mint(liquidator, collateralToCover);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dsce), collateralToCover);
        dsce.depositeCollateralAndmintDsc(weth, collateralToCover, AMOUNT_MINT);
        dsc.approve(address(dsce), AMOUNT_MINT);
        beforeLiquidatorBalance = dsc.balanceOf(liquidator);
        dsce.liquidate(weth, USER, AMOUNT_MINT); // We are covering their whole debt
        vm.stopPrank();
        afterLiquidatorBalance = dsc.balanceOf(liquidator);
        _;
    }
    function testLiquidatorTakesOnUserdebt() public liquidated{
        uint256 expectedLiquidatorDscBalance = AMOUNT_MINT;
        assertEq(beforeLiquidatorBalance-afterLiquidatorBalance, expectedLiquidatorDscBalance);
}
    function testUserHasNoMoreDebt() public liquidated {
        (uint256 userDscMinted,) = dsce.getAccountInformation(USER);
        assertEq(userDscMinted, 0);
    }

    /////////////////////////////////
    //View and Pure function Tests //
    /////////////////////////////////

    function testGetCollateralTokens() public view{
        address[] memory collateralTokens = dsce.getCollateralTokens();
        assertEq(collateralTokens[0], weth);
    }

    function testGetMinimumHealthFactor() public view{
        uint256 healthfactor = dsce.getMinHealthFactor();
        assertEq(healthfactor, MIN_HEALTH_FACTOR);
    }

    function testGetLiquidationThreshold() public view{
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();
        assertEq(liquidationThreshold, LIQUIDATION_THRESHOLD);
    }

    function testGetAccountCollateralValueFromInformation() public depositedCollateral {
        (, uint256 collateralValue) = dsce.getAccountInformation(USER);
        uint256 expectedCollateralValue = dsce.getUsdValue(weth, AMOUNT_COLLATERAL);
        assertEq(collateralValue, expectedCollateralValue);
    }

    function testLiquidationBonus() public view{
        uint256 liquidationBonus = dsce.getLiquidationBonus();
        assertEq(liquidationBonus, LIQUIDATION_BONUS);
    }

    function testGetDsc() public view{
        address dscAddress = dsce.getDsc();
        assertEq(dscAddress, address(dsc));
    }
}
