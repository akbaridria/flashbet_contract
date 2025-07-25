// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/FlashBet.sol";
import "../src/BetManager.sol";
import "../src/LiquidityManager.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockUSDC is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;
    uint8 private _decimals;

    constructor() {
        _name = "Mock USDC";
        _symbol = "mUSDC";
        _decimals = 6;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) public {
        _burn(from, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(address owner, address spender, uint256 amount) internal {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}

    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

contract MockPyth {
    mapping(bytes32 => PythStructs.Price) private prices;
    uint256 public updateFee;

    constructor(uint256 _updateFee) {
        updateFee = _updateFee;
    }

    function getUpdateFee(bytes[] calldata) external view returns (uint256) {
        return updateFee;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        require(msg.value >= updateFee, "Insufficient fee");
    }

    function getPriceNoOlderThan(bytes32 priceId, uint256) external view returns (PythStructs.Price memory) {
        require(prices[priceId].publishTime > 0, "Price not available");
        return prices[priceId];
    }

    function setPrice(bytes32 priceId, int64 price, uint64 conf, int32 expo, uint256 publishTime) external {
        prices[priceId] = PythStructs.Price({price: price, conf: conf, expo: expo, publishTime: publishTime});
    }
}

contract FlashBetTest is Test {
    FlashBet flashBet;
    MockUSDC mockUSDC;
    MockPyth mockPyth;

    address owner;
    address user1;
    address user2;
    address user3;
    address resolver;

    bytes32 constant ETH_USD_PRICE_ID = 0x000000000000000000000000000000000000000000000000000000000000abcd;
    uint256 constant INITIAL_USDC_SUPPLY = 1_000_000 * 1e6;
    uint256 constant INITIAL_USER_BALANCE = 10_000 * 1e6;
    uint256 constant INITIAL_LIQUIDITY = 100_000 * 1e6;
    uint256 constant UPDATE_FEE = 0.01 ether;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        resolver = makeAddr("resolver");

        mockUSDC = new MockUSDC();
        mockPyth = new MockPyth(UPDATE_FEE);

        flashBet = new FlashBet(address(mockUSDC), address(mockPyth), ETH_USD_PRICE_ID);

        mockUSDC.mint(owner, INITIAL_USDC_SUPPLY);
        mockUSDC.mint(user1, INITIAL_USER_BALANCE);
        mockUSDC.mint(user2, INITIAL_USER_BALANCE);
        mockUSDC.mint(user3, INITIAL_USER_BALANCE);

        mockPyth.setPrice(ETH_USD_PRICE_ID, 3000 * 1e8, 10 * 1e8, -8, uint256(block.timestamp));

        mockUSDC.approve(address(flashBet), INITIAL_USDC_SUPPLY);

        vm.prank(user1);
        mockUSDC.approve(address(flashBet), INITIAL_USER_BALANCE);

        vm.prank(user2);
        mockUSDC.approve(address(flashBet), INITIAL_USER_BALANCE);

        vm.prank(user3);
        mockUSDC.approve(address(flashBet), INITIAL_USER_BALANCE);

        flashBet.addLiquidity(INITIAL_LIQUIDITY);
    }

    function test_Constructor() public view {
        assertEq(address(flashBet.usdc()), address(mockUSDC));
        assertEq(address(flashBet.pyth()), address(mockPyth));
        assertEq(flashBet.priceId(), ETH_USD_PRICE_ID);
    }

    function test_AddLiquidity() public {
        uint256 addAmount = 50_000 * 1e6;
        uint256 beforeBalance = mockUSDC.balanceOf(owner);

        flashBet.addLiquidity(addAmount);

        (uint256 totalLiquidity, uint256 availableLiquidity,) = flashBet.getMarketState();

        assertEq(mockUSDC.balanceOf(owner), beforeBalance - addAmount);
        assertEq(totalLiquidity, INITIAL_LIQUIDITY + addAmount);
        assertEq(availableLiquidity, INITIAL_LIQUIDITY + addAmount);
    }

    function test_PlaceBet_DuringTradingHours() public {
        uint256 betAmount = 100 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 tradingTime = _findTradingHourTimestamp();
        vm.warp(tradingTime);

        uint256 userBalanceBefore = mockUSDC.balanceOf(user1);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);

        assertEq(mockUSDC.balanceOf(user1), userBalanceBefore - betAmount);
    }

    function test_PlaceBet_OutsideTradingHours() public {
        uint256 betAmount = 100 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 nonTradingTime = _findNonTradingHourTimestamp();
        vm.warp(nonTradingTime);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        vm.expectRevert("Not trading hours");
        flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);
    }

    function test_ResolveBet_UserWins() public {
        uint256 betAmount = 100 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 tradingTime = _findTradingHourTimestamp();
        vm.warp(tradingTime);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        uint256 betId = flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);

        vm.warp(block.timestamp + duration);

        mockPyth.setPrice(ETH_USD_PRICE_ID, 3200 * 1e8, 10 * 1e8, -8, uint256(block.timestamp));

        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);
        uint256 resolverBalanceBefore = mockUSDC.balanceOf(resolver);

        (uint256 totalLiquidity,,) = flashBet.getMarketState();
        console.log("Total Liquidity after bet resolution:", totalLiquidity);

        vm.deal(resolver, 1 ether);
        vm.prank(resolver);
        flashBet.resolveBet{value: UPDATE_FEE}(betId, priceUpdateData);

        uint256 user1BalanceAfter = mockUSDC.balanceOf(user1);
        uint256 resolverBalanceAfter = mockUSDC.balanceOf(resolver);

        uint256 expectedPayout = (betAmount * 17500) / 10000;
        uint256 protocolFee = (betAmount * 100) / 10000;
        uint256 resolverFee = (betAmount * 100) / 10000;
        uint256 userPayout = expectedPayout - protocolFee - resolverFee;

        assertEq(user1BalanceAfter - user1BalanceBefore, userPayout);
        assertEq(resolverBalanceAfter - resolverBalanceBefore, resolverFee);
    }

    function test_ResolveBet_UserLoses() public {
        uint256 betAmount = 100 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 tradingTime = _findTradingHourTimestamp();
        vm.warp(tradingTime);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        uint256 betId = flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);

        vm.warp(block.timestamp + duration);

        mockPyth.setPrice(ETH_USD_PRICE_ID, 2800 * 1e8, 10 * 1e8, -8, uint256(block.timestamp));

        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);

        vm.deal(resolver, 1 ether);
        vm.prank(resolver);
        flashBet.resolveBet{value: UPDATE_FEE}(betId, priceUpdateData);

        uint256 user1BalanceAfter = mockUSDC.balanceOf(user1);

        assertEq(user1BalanceAfter, user1BalanceBefore);
    }

    function test_ResolveBet_Cancellation() public {
        uint256 betAmount = 100 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 tradingTime = _findTradingHourTimestamp();
        vm.warp(tradingTime);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        uint256 betId = flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);

        vm.warp(block.timestamp + duration + 61);

        uint256 user1BalanceBefore = mockUSDC.balanceOf(user1);

        vm.deal(resolver, 1 ether);
        vm.prank(resolver);
        flashBet.resolveBet{value: UPDATE_FEE}(betId, priceUpdateData);

        uint256 user1BalanceAfter = mockUSDC.balanceOf(user1);

        assertEq(user1BalanceAfter - user1BalanceBefore, betAmount);
    }

    function test_RemoveLiquidity_DuringWindow() public {
        vm.prank(user2);
        flashBet.addLiquidity(1000 * 1e6);

        uint256 withdrawalTime = _findWithdrawalWindowTimestamp();
        vm.warp(withdrawalTime);

        uint256 withdrawAmount = 500 * 1e6;
        uint256 user2BalanceBefore = mockUSDC.balanceOf(user2);

        vm.prank(user2);
        flashBet.removeLiquidity(withdrawAmount);

        uint256 user2BalanceAfter = mockUSDC.balanceOf(user2);

        assertEq(user2BalanceAfter - user2BalanceBefore, withdrawAmount);
    }

    function test_RemoveLiquidity_OutsideWindow() public {
        vm.prank(user2);
        flashBet.addLiquidity(1000 * 1e6);

        uint256 nonWithdrawalTime = _findNonWithdrawalWindowTimestamp();
        vm.warp(nonWithdrawalTime);

        uint256 withdrawAmount = 500 * 1e6;

        vm.prank(user2);
        vm.expectRevert("Not withdrawal window");
        flashBet.removeLiquidity(withdrawAmount);
    }

    function test_WithdrawProtocolFees() public {
        uint256 betAmount = 1000 * 1e6;
        uint256 duration = 5 minutes;
        bool isLong = true;
        bytes[] memory priceUpdateData = new bytes[](0);

        uint256 tradingTime = _findTradingHourTimestamp();
        vm.warp(tradingTime);

        vm.prank(user1);
        vm.deal(user1, 1 ether);
        uint256 betId = flashBet.placeBet{value: UPDATE_FEE}(betAmount, duration, isLong, priceUpdateData);

        vm.warp(block.timestamp + duration);

        mockPyth.setPrice(ETH_USD_PRICE_ID, 2800 * 1e8, 10 * 1e8, -8, uint256(block.timestamp));

        vm.deal(resolver, 1 ether);
        vm.prank(resolver);
        flashBet.resolveBet{value: UPDATE_FEE}(betId, priceUpdateData);

        uint256 protocolFees = flashBet.protocolFees();
        uint256 expectedFees = (betAmount * 100) / 10000;
        assertEq(protocolFees, expectedFees);

        uint256 ownerBalanceBefore = mockUSDC.balanceOf(owner);
        flashBet.withdrawProtocolFees();
        uint256 ownerBalanceAfter = mockUSDC.balanceOf(owner);

        assertEq(ownerBalanceAfter - ownerBalanceBefore, expectedFees);
        assertEq(flashBet.protocolFees(), 0);
    }

    function test_GetMarketState() public view {
        (uint256 totalLiquidity, uint256 availableLiquidity, uint256 nextPauseTime) = flashBet.getMarketState();

        assertEq(totalLiquidity, INITIAL_LIQUIDITY);
        assertEq(availableLiquidity, INITIAL_LIQUIDITY);
        assertEq(nextPauseTime, flashBet.lastPauseTime() + flashBet.pauseInterval());
    }

    function _findTradingHourTimestamp() internal view returns (uint256) {
        uint256 baseTime = block.timestamp;
        uint256 hour = (baseTime / 3600) % 24;

        if (hour != 21) {
            return baseTime;
        } else {
            return baseTime + 3600;
        }
    }

    function _findNonTradingHourTimestamp() internal view returns (uint256) {
        uint256 baseTime = block.timestamp;
        uint256 hour = (baseTime / 3600) % 24;

        if (hour == 21) {
            return baseTime;
        } else {
            uint256 currentDayStart = baseTime - (baseTime % 86400);
            return currentDayStart + (21 * 3600);
        }
    }

    function _findWithdrawalWindowTimestamp() internal view returns (uint256) {
        uint256 baseTime = block.timestamp;
        uint256 currentDayStart = baseTime - (baseTime % 86400);
        return currentDayStart + (1290 * 60);
    }

    function _findNonWithdrawalWindowTimestamp() internal view returns (uint256) {
        uint256 baseTime = block.timestamp;
        uint256 currentDayStart = baseTime - (baseTime % 86400);
        return currentDayStart + (12 * 3600);
    }
}
