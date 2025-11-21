//SPDX-Licence-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/Helperconfig.s.sol";
import {ERC20Mock} from "../mocks/Erc20Mock.sol";



contract DSCTest is Test {
    DeployDSC  public deployer;
    DecentralizedStableCoin public dsc;
    DSCEngine public dsce;
    HelperConfig public config;

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

    address public USER = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed,btcUsdPriceFeed, weth, wbtc, ) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }
        //Transfer ownership of the DecentralizedStableCoin to the DSCEngine
        dsc.transferOwnership(address(dsce));
        assertEq(dsc.owner(), address(dsce));

        ERC20Mock(weth).mint(USER, AMOUNT_COLLATERAL);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
    }

    ///////////////////////
    //Constructor Tests ///
    ///////////////////////
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokneLengthDoensntMatchPriceFeedLength() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        // Adding an extra address to priceFeedAddresses to cause a mismatch
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength.selector
            )
        );
        new DSCEngine(
            tokenAddresses,
            priceFeedAddresses,
            address(dsc)
        );
    }

    ///////////////////////
    //Price Tests        //
    ///////////////////////

    function testGetUsdValue() public view{
        uint256 ethAmount = 15e18;
        // Assuming ETH price is 2000 USD
        uint256 expectedUsdValue = 15e18 * 2000; 
        uint256 actualUsdValue = dsce.getUsdValue(weth, ethAmount);
        console.log("Expected USD Value: %s", expectedUsdValue);
        console.log("Actual USD Value: %s", actualUsdValue);
        assertEq(actualUsdValue, expectedUsdValue);

    }

    function testGEtToeknAmountFromUsd() public view{
        uint256 usdAmount = 100 ether;

        uint256 expectedUsdAmount = (usdAmount)/2000; // Assuming ETH price is 2000 USD
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

        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NeedsMoreThanZero.selector)
        );

        dsce.depositeCollateral(weth, 0); 
        vm.stopPrank();
    }

    function testRevertWithUnapprovedCollateral() public {
        //ranToken is not allowed in the DSCEngine
        //ranToken is a mock ERC20 token
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, 100 ether);
        vm.startPrank(USER);
        vm.expectRevert(
            abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedToken.selector)
        );
        dsce.depositeCollateral(address(ranToken), AMOUNT_COLLATERAL);
        vm.stopPrank();
    }

    modifier depositedCollateral(){
        vm.startPrank(USER);
        //USER approves the DSC Engine to spend up to 10 ETH worth of WETH on their behalf.
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
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

    modifier deopositedCollateralAndMintDsc(){
        vm.startPrank(USER);

        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateralAndmintDsc(weth, AMOUNT_COLLATERAL, AMOUNT_MINT );
        vm.stopPrank();
        _;
    }

    function testCanMintWithDepositedCollateral() public deopositedCollateralAndMintDsc {
        uint256 userBalance = dsc.balanceOf(USER);
        assertEq(userBalance, AMOUNT_MINT);
    }

    function testRevertIfMintedDscBreaksHealthFactor() public {}

    
}