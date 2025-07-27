// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "../Types.sol";

interface IBetManager {
    function placeBet(address user, uint256 amount, bytes32 priceId, uint256 duration, bool isLong, int64 entryPrice)
        external
        returns (uint256 betId);

    function resolveBet(uint256 betId, int64 exitPrice, address resolver) external returns (bool won, uint256 payout);
    function cancelBet(uint256 betId) external;
    function getBet(uint256 betId) external view returns (Bet memory bet);
    function canResolveBet(uint256 betId) external view returns (bool);
}
