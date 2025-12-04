// SPDX-License-Identifier: MIT

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

pragma solidity ^0.8.18;

/**
 * @title OracleLib
 * @author Subodh
 * @notice This library is used to checks the chainlink Oracle for stable data.
 * If a price is satte, the function will revert, and render the DSCEngine usable - this is by design
 * We wnat the DSCEngine to freeze if prices become stable.
 *
 * so if the chainlink network explodes and you have a lot of money locked in protocol.......
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 private constant TIMEOUT = 3 hours; //3 * 60 * 60 = 10800 seconds

    function stalePriceCheckLatestRoundData(AggregatorV3Interface priceFeed)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeed.latestRoundData();

        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIMEOUT) {
            revert OracleLib__StalePrice();
        }
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
