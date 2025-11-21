// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title DSCEngine
 * @author Subodh Negi
 * The system is designed to be minimal as possible ,and have the tokens maintain a 1 token == 1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral (ETH, BTC, etc...)
 * - Algorithmically stable
 * - Dollar Pegged
 *
 * It is similar to DAI if DAI had no governance , no fees and was only backed by WETH and WBTC.
 *
 * Our Dsc system should always be "overcollateralized" meaning that the value of the collateral should always be greater than the value of the DSC in circulation.
 *
 * @notice This contract is the core of the DSC system. It handels all the logic for minting and redeeming DSC, as well as depositing & withdrawing collteral.
 * @notice This contract is very loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    //////////////////////////
    // ERRORS               //
    //////////////////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreakHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEingine__HealthFactorIsOk();
    error DSCEngine__HealthFactorIsNotImproved();

    //////////////////////////
    // State Variables      //
    //////////////////////////
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // 10% bonus collateral for liquidators

    mapping(address => address) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount))
        private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;
    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

    ///////////////////////////
    /// EVENTS             //
    ///////////////////////////
    event CollateralDeposited(
        address indexed user,
        address indexed token,
        uint256 indexed amount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    //////////////////////////
    // MODIFIERS            //
    //////////////////////////
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    //////////////////////////
    // Constructor          //
    //////////////////////////
    constructor(
        address[] memory tokenAddresses,
        address[] memory priceFeedAddresses,
        address dscAddress
    ) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////
    // External Functions   //
    //////////////////////////

    /**
     *
     * @param tokenCollateralAddress The address of the collateral token contract.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDscToMint The amount of DSC to mint.
     * @notice this function will deposit collateral and mint Dsc in one transaction
     */
    function depositeCollateralAndmintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external {
        depositeCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @notice follows CEI
     * @param tokenCollateralAddress The address of the collateral token contract.
     * @param amountCollateral The amount of collateral to deposit.
     */
    function depositeCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    )
        public
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][
            tokenCollateralAddress
        ] += amountCollateral;

        // Transfer the collateral from the user to this contract
        bool success = IERC20(tokenCollateralAddress).transferFrom(
            msg.sender,
            address(this),
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

        emit CollateralDeposited(
            msg.sender,
            tokenCollateralAddress,
            amountCollateral
        );
    }

    /**
     *
     * @param tokenCollateralAddress The collateral address to redeem
     * @param amountCollateral The amount of Collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     * This function burns DSC and redeems underlying collateral in one transaction
     */

    function redeemCollateralForDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    //in order to reedeem collateral:
    //1. health factor must be over 1 After collateral is redeemed
    // DRY: Don't Repeat Yourself
    //CEI: Checks-Effects-Interactions
    function redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(
            tokenCollateralAddress,
            amountCollateral,
            msg.sender,
            msg.sender
        );
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows CEI
     * @notice Mints DSC to the caller's address.
     * @param amountDscToMint The amount of DSC to mint.
     * @notice they must have more collateral value than the minimum threshold.
     */
    function mintDsc(
        uint256 amountDscToMint
    ) public moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        //if they Minted too much ($150 DSC , $100 ETH)
        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    function burnDsc(
        uint256 amountDscToBurn
    ) public moreThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(msg.sender, amountDscToBurn, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidates a user's collateral if their health factor is broken.
     * @dev This function allows anyone to liquidate a user's collateral if their health factor is below 1.
     * @param collateral The address of the collateral token to liquidate.
     * @param user The address of the user whose collateral is being liquidated.
     * @param debtToCover The amount of debt to cover in DSC.
     * @notice  This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     */
    function liquidate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        //Check if health-factor is Broken
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEingine__HealthFactorIsOk();
        }

        //Get the amount of collateral to liquidate
        uint256 tokenAmountFromDebtToCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtToCovered *
            LIQUIDATION_BONUS) / 100; // 10% bonus collateral for liquidators
        uint256 totalCollateralToRedeem = tokenAmountFromDebtToCovered +
            bonusCollateral;

        _redeemCollateral(
            collateral,
            totalCollateralToRedeem,
            user,
            msg.sender
        );

        _burnDsc(user, debtToCover, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorIsNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    

    ///////////////////////////
    // Private & Internal View Functions   //
    ///////////////////////////

    /*
     *@dev Low level internal functions, do not call unless the function is calling itself for the health factor is being broken or not.
     */
    function _burnDsc(
        address dscfrom,
        uint256 amountDscToBurn,
        address onBehalfOf
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transfer(dscfrom, amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        address from,
        address to
    ) private {
        //Automatic underflow/overflow checks (runtime, not compiler)
        // Solidity 0.8+ reverts if subtraction would go below 0.
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getAccountInformation(
        address user
    )
        private
        view
        returns (uint256 totalDscMintedInUsd, uint256 totalCollateralValueInUsd)
    {
        totalDscMintedInUsd = s_DSCMinted[user];
        totalCollateralValueInUsd = getAccountcollateralValue(user);
    }

    /**
     * @notice Checks if the user's health factor is broken.
     * @dev Health factor is defined as the ratio of collateral value to DSC value.
     * If the health factor is less than 1, it means the user has more DSC minted than their collateral value.
     * @param user The address of the user to check.
     */
    function _healthFactor(address user) private view returns (uint256) {
        (
            uint256 totalDscMintedInUsd,
            uint256 totalCollateralValueInUsd
        ) = _getAccountInformation(user);
        return
            _calculateHealthFactor(
                totalDscMintedInUsd,
                totalCollateralValueInUsd
            );
    }

    function _calculateHealthFactor(uint256 totalDscMintedInUsd, uint256 totalCollateralValueInUsd)internal pure returns(uint256){
       
        if(totalDscMintedInUsd ==0){
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUsd *
            LIQUIDATION_THRESHOLD) / 100;
        // $150 ETH / 100 DSC = 1.5
        // 150ETH * 50 => 7,500 / 100 => (75/100) <1
        return (collateralAdjustedForThreshold * 1e18) / totalDscMintedInUsd; // 1e18 is to keep the precision
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            // 1e18 is the equivalent of 1 in our health factor system
            revert DSCEngine__BreakHealthFactor();
        }
    }

    ///////////////////////////
    // Public & External View Functions   //
    ///////////////////////////
    
    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        // 1e8 is the decimals of the price feed, so we need to adjust for that
        // 1e18 is the decimals of the token, so we need to adjust for that
        return (usdAmountInWei * 1e8) / uint256(price);
    }

    function getAccountcollateralValue(
        address user
    ) public view returns (uint256) {
        // loop through each collateral token, get the amount they deposited, and map it to
        // the price, to get the USD value
        uint256 CollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address collateralToken = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[user][
                collateralToken
            ];
            CollateralValueInUsd += getUsdValue(
                collateralToken,
                amountCollateral
            );
        }

        return CollateralValueInUsd;
    }

    /**
     * @notice Gets the USD value of a given amount of a token.
     * @param token The address of the token contract.
     * @param amount The amount of the token to convert to USD, which is initially in wei( 1e18).
     * @return The returned value from CL will be 1000 * 1e8
     */
    function getUsdValue(
        address token,
        uint256 amount
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return ((uint256(price) * 1e10) * amount) / 1e18;
    }

    function getAccountInformation(address user) external view returns(uint256 totalDscMinted, uint256 collateralValueInUsd){
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function claculateHealthFactor(uint256 totalDscMintedInUsd, uint256 totalCollateralValueInUsd) external pure returns(uint256){
        return _calculateHealthFactor(totalDscMintedInUsd, totalCollateralValueInUsd);
    }
    function getDsc() external view returns (address) {
        return address(i_dsc);
    }

    function getLiquidationThreshold() external pure returns (uint256) {
        return LIQUIDATION_THRESHOLD;
    }

    function getMinHealthFactor() external pure returns (uint256) {
        return MIN_HEALTH_FACTOR;
    }

    function getLiquidationBonus() external pure returns (uint256) {
        return LIQUIDATION_BONUS;
    }
    function getTotalDscMinted(address user) external view returns (uint256) {
        return s_DSCMinted[user];
    }
}
