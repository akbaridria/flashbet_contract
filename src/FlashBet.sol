// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";
import "./LiquidityManager.sol";
import "./BetManager.sol";

contract FlashBet is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    // Constants
    uint256 private constant PROTOCOL_FEE = 100; // 1%
    uint256 private constant RESOLVER_FEE = 100; // 1%
    uint256 private constant BASIS_POINTS = 10000;
    uint256 private constant LIQUIDITY_LOCK_RATIO = 7500; // 0.75x
    uint256 private constant LIQUIDITY_LOCK_THRESHOLD = 8000; // 80%

    IERC20 public immutable usdc;
    IPyth public immutable pyth;
    LiquidityManager public immutable liquidityManager;
    BetManager public immutable betManager;

    uint256 public protocolFees;
    uint256 public lastPauseTime;
    uint256 public pauseInterval = 24 hours;
    bytes32 public priceId;

    event MarketPaused(uint256 timestamp);
    event MarketUnpaused(uint256 timestamp);
    event BetPlaced(uint256 indexed betId, address indexed user);
    event BetResolved(uint256 indexed betId, bool won);
    event BetCancelled(uint256 indexed betId);

    constructor(address _usdc, address _pyth, bytes32 _priceId) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        pyth = IPyth(_pyth);
        liquidityManager = new LiquidityManager();
        betManager = new BetManager();
        lastPauseTime = block.timestamp;
        priceId = _priceId;
    }

    function _isTradingHours() internal view returns (bool) {
        uint256 hour = (block.timestamp / 60 / 60) % 24;
        return hour < 21 || hour >= 22;
    }

    function _isWithdrawalWindow() internal view returns (bool) {
        uint256 minuteOfDay = (block.timestamp / 60) % 1440;
        return minuteOfDay >= 1275 && minuteOfDay < 1320;
    }

    modifier onlyDuringTradingHours() {
        require(_isTradingHours(), "Not trading hours");
        _;
    }

    modifier onlyDuringWithdrawalWindow() {
        require(_isWithdrawalWindow(), "Not withdrawal window");
        _;
    }

    modifier validateLiquidity() {
        uint256 localLiquidity = liquidityManager.lockedLiquidity();
        uint256 totalLiquidity = liquidityManager.totalLiquidity();
        uint256 utilizationRate = localLiquidity * BASIS_POINTS / totalLiquidity;
        require(utilizationRate < LIQUIDITY_LOCK_THRESHOLD, "Liquidity utilization above threshold");
        _;
    }

    receive() external payable {}
    fallback() external payable {}

    function placeBet(uint256 amount, uint256 duration, bool isLong, bytes[] calldata priceUpdateData)
        external
        payable
        onlyDuringTradingHours
        validateLiquidity
        nonReentrant
        returns (uint256 betId)
    {
        require(amount > 0, "Invalid amount");
        require(duration >= 2 minutes && duration <= 10 minutes, "Invalid duration");

        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee");

        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        if (msg.value > fee) {
            (bool sent,) = msg.sender.call{value: msg.value - fee}("");
            require(sent, "Refund failed");
        }

        PythStructs.Price memory currentPrice = pyth.getPriceNoOlderThan(priceId, 60);
        require(block.timestamp - currentPrice.publishTime <= 60, "Price too old");

        // Transfer USDC and lock liquidity
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        uint256 lockAmount = (amount * LIQUIDITY_LOCK_RATIO) / BASIS_POINTS;
        liquidityManager.lockLiquidity(lockAmount);

        // Create bet
        betId = betManager.placeBet(msg.sender, amount, priceId, duration, isLong, currentPrice.price);

        emit BetPlaced(betId, msg.sender);
        return betId;
    }

    function resolveBet(uint256 betId, bytes[] calldata priceUpdateData) external payable nonReentrant {
        require(betManager.canResolveBet(betId), "Cannot resolve");

        Bet memory bet = betManager.getBet(betId);

        if (block.timestamp - bet.expiryTime > 60) {
            betManager.cancelBet(betId);
            if (msg.value > 0) {
                (bool sent,) = msg.sender.call{value: msg.value}("");
                require(sent, "Refund failed");
            }
            usdc.safeTransfer(bet.user, bet.amount);
            liquidityManager.unlockLiquidity(bet.amount * LIQUIDITY_LOCK_RATIO / BASIS_POINTS);
            emit BetCancelled(betId);
            return;
        }

        uint256 fee = pyth.getUpdateFee(priceUpdateData);
        require(msg.value >= fee, "Insufficient fee");

        pyth.updatePriceFeeds{value: fee}(priceUpdateData);

        if (msg.value > fee) {
            (bool sent,) = msg.sender.call{value: msg.value - fee}("");
            require(sent, "Refund failed");
        }

        PythStructs.Price memory exitPrice = pyth.getPriceNoOlderThan(priceId, 60);
        require(block.timestamp - exitPrice.publishTime <= 60, "Price too old");

        (bool won, uint256 totalPayout) = betManager.resolveBet(betId, exitPrice.price, msg.sender);

        // Release locked liquidity
        uint256 lockAmount = (bet.amount * LIQUIDITY_LOCK_RATIO) / BASIS_POINTS;
        liquidityManager.unlockLiquidity(lockAmount);

        // Handle payouts and fees
        _handleBetResolution(bet.user, bet.amount, won, totalPayout, msg.sender);

        emit BetResolved(betId, won);
    }

    function addLiquidity(uint256 amount) external nonReentrant {
        liquidityManager.addLiquidity(msg.sender, amount);
        usdc.safeTransferFrom(msg.sender, address(this), amount);
    }

    function removeLiquidity(uint256 amount) external onlyDuringWithdrawalWindow nonReentrant {
        uint256 amountToWithdraw = liquidityManager.removeLiquidity(msg.sender, amount);
        usdc.safeTransfer(msg.sender, amountToWithdraw);
    }

    function _handleBetResolution(address user, uint256 betAmount, bool won, uint256 totalPayout, address resolver)
        internal
    {
        uint256 protocolFee = (betAmount * PROTOCOL_FEE) / BASIS_POINTS;
        uint256 resolverFee = (betAmount * RESOLVER_FEE) / BASIS_POINTS;
        protocolFees += protocolFee;
        usdc.safeTransfer(resolver, resolverFee);

        if (won) {
            uint256 userPayout = totalPayout - protocolFee - resolverFee;
            usdc.safeTransfer(user, userPayout);
            liquidityManager.distributePnL(-int256(totalPayout - betAmount));
        } else {
            liquidityManager.distributePnL(int256(betAmount - protocolFee));
        }
    }

    function withdrawProtocolFees() external onlyOwner {
        require(protocolFees > 0, "No fees");
        uint256 amount = protocolFees;
        protocolFees = 0;
        usdc.safeTransfer(owner(), amount);
    }

    // View functions
    function getMarketState()
        external
        view
        returns (uint256 totalLiquidity, uint256 availableLiquidity, uint256 nextPauseTime)
    {
        return (
            liquidityManager.getTotalLiquidity(),
            liquidityManager.getAvailableLiquidity(),
            lastPauseTime + pauseInterval
        );
    }

    function getProviderBalance(address provider) external view returns (uint256 effectiveBalance) {
        effectiveBalance = liquidityManager.getProviderBalance(provider);
    }

    function getBetInfo(uint256 betId) external view returns (Bet memory bet) {
        bet = betManager.getBet(betId);
    }

    function getUserBets(address user) external view returns (uint256[] memory bets) {
        bets = betManager.getUserBets(user);
    }

    function timeUntilWithdrawalWindowOpens() external view returns (uint256 secondsUntilOpen) {
        uint256 minuteOfDay = (block.timestamp / 60) % 1440;
        if (minuteOfDay < 1275) {
            secondsUntilOpen = (1275 - minuteOfDay) * 60;
        } else if (minuteOfDay >= 1320) {
            secondsUntilOpen = ((1440 - minuteOfDay) + 1275) * 60;
        } else {
            secondsUntilOpen = 0;
        }
    }
}
