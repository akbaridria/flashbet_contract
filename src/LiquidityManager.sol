// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/ILiquidityManager.sol";
import "./PullBasedDistribution.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LiquidityManager is ILiquidityManager, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable usdc;
    PullBasedDistribution public immutable rewardDistributor;

    uint256 public totalLiquidity;
    uint256 public lockedLiquidity;

    constructor(address _usdc) Ownable(msg.sender) {
        usdc = IERC20(_usdc);
        rewardDistributor = new PullBasedDistribution();
    }

    function addLiquidity(address provider, uint256 amount) external override onlyOwner {
        usdc.safeTransferFrom(provider, address(this), amount);

        rewardDistributor.addStake(provider, amount);
        totalLiquidity += amount;
    }

    function removeLiquidity(address provider, uint256 amount) external override onlyOwner returns (uint256) {
        uint256 actualAmount = rewardDistributor.removeStake(provider, amount);
        usdc.safeTransfer(provider, actualAmount);
        totalLiquidity -= actualAmount;

        return actualAmount;
    }

    function lockLiquidity(uint256 amount) external override onlyOwner {
        require(lockedLiquidity + amount <= totalLiquidity, "Insufficient liquidity");
        lockedLiquidity += amount;
    }

    function unlockLiquidity(uint256 amount) external override onlyOwner {
        require(lockedLiquidity >= amount, "Invalid unlock amount");
        lockedLiquidity -= amount;
    }

    function distributePnL(int256 pnl) external override onlyOwner {
        rewardDistributor.distributePnL(pnl);
        uint256 pnlAbs = uint256(pnl);
        if (pnl > 0) {
            totalLiquidity += pnlAbs;
        } else {
            totalLiquidity -= pnlAbs;
        }
    }

    // View functions
    function getTotalLiquidity() external view override returns (uint256) {
        return totalLiquidity;
    }

    function getAvailableLiquidity() public view override returns (uint256) {
        return totalLiquidity - lockedLiquidity;
    }

    function getProviderBalance(address provider) external view override returns (uint256) {
        (,, uint256 effectiveBalance) = rewardDistributor.getProviderInfo(provider);
        return effectiveBalance;
    }
}
