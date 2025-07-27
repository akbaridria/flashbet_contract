// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IBetManager.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./Types.sol";

contract BetManager is IBetManager, ReentrancyGuard, Ownable {
    constructor() Ownable(msg.sender) {}

    mapping(uint256 => Bet) public bets;
    mapping(address => uint256[]) public userBets;

    uint256 public nextBetId = 1;

    uint256 private constant PAYOUT_MULTIPLIER = 17500; // 1.75x
    uint256 private constant BASIS_POINTS = 10000;

    event BetPlaced(uint256 indexed betId, address indexed user, uint256 amount, uint256 expiryTime);
    event BetResolved(uint256 indexed betId, address indexed resolver, bool won, uint256 payout);

    function placeBet(address user, uint256 amount, bytes32 priceId, uint256 duration, bool isLong, int64 entryPrice)
        external
        override
        onlyOwner
        returns (uint256 betId)
    {
        betId = nextBetId++;

        bets[betId] = Bet({
            user: user,
            amount: amount,
            priceId: priceId,
            entryPrice: entryPrice,
            entryTime: block.timestamp,
            expiryTime: block.timestamp + duration,
            isLong: isLong,
            won: false,
            resolver: address(0),
            status: Status.Pending
        });

        userBets[user].push(betId);

        emit BetPlaced(betId, user, amount, block.timestamp + duration);
        return betId;
    }

    function resolveBet(uint256 betId, int64 exitPrice, address resolver)
        external
        override
        onlyOwner
        returns (bool won, uint256 payout)
    {
        Bet storage bet = bets[betId];
        require(bet.status != Status.Resolved, "Already resolved");
        require(block.timestamp >= bet.expiryTime, "Not expired");

        won = bet.isLong ? exitPrice > bet.entryPrice : exitPrice < bet.entryPrice;

        if (won) {
            payout = (bet.amount * PAYOUT_MULTIPLIER) / BASIS_POINTS;
        }

        bet.status = Status.Resolved;
        bet.won = won;
        bet.resolver = resolver;

        emit BetResolved(betId, resolver, won, payout);
        return (won, payout);
    }

    function cancelBet(uint256 betId) external override onlyOwner {
        Bet storage bet = bets[betId];
        require(bet.status == Status.Pending, "Cannot cancel");

        bet.status = Status.Cancelled;

        emit BetResolved(betId, msg.sender, false, 0);
    }

    function getBet(uint256 betId) external view override returns (Bet memory bet) {
        bet = bets[betId];
    }

    function canResolveBet(uint256 betId) external view override returns (bool) {
        Bet memory bet = bets[betId];
        return bet.status == Status.Pending && block.timestamp >= bet.expiryTime && bet.user != address(0);
    }

    function getUserBets(address user) external view returns (uint256[] memory) {
        return userBets[user];
    }
}
