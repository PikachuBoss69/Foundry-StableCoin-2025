// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.18;

// //Have our invariants aka properties of system

// //What are Invariants?

// //1. The total supply of stablecoins should always be less than  to the total value of the collateral backing them.
// //2. Getter View functions should never revert <- evergreen invariants

// import {Test, console} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
// import {DeployDSC} from "../../script/DeployDSC.s.sol";
// import {DSCEngine} from "../../src/DSCEngine.sol";
// import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {HelperConfig} from "../../script/Helperconfig.s.sol";

// contract OpenInvariantsTest is StdInvariant{
//     DeployDSC deployer;
//     DSCEngine dsce;
//     DecentralizedStableCoin dsc;
//     HelperConfig config;
//     address weth;
//     address wbtc;

//     function setUp() public {
//         deployer = new DeployDSC();
//         (dsc, dsce, config) = deployer.run();
//         (,, weth, wbtc, ) = config.activeNetworkConfig();
//         targetContract(address(dsce));
//     }

//     function invariant_protocolMustHaveMoreValuethanTotalSupply() public view {
//         uint256 totalSupply = dsc.totalSupply();
//         uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
//         uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));

//     uint256 wethValue = dsce.getUsdValue(weth, totalWethDeposited);
//     uint256 wbtcValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

//     assert(wethValue + wbtcValue >= totalSupply);

//     }
// }