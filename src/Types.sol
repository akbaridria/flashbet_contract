// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

enum Status {
    Pending,
    Resolved,
    Cancelled
}

struct Bet {
    address user;
    uint256 amount;
    bytes32 priceId;
    int64 entryPrice;
    uint256 entryTime;
    uint256 expiryTime;
    bool isLong;
    bool won;
    address resolver;
    Status status;
}
