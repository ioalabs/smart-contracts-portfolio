// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface INimbusPair is IERC20 {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

interface INimbusRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

library Math {
    // babylonian method (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}

interface IPriceFeed {
    function queryRate(address sourceTokenAddress, address destTokenAddress) external view returns (uint256 rate, uint256 precision);
    function wbnbToken() external view returns(address);
}

interface ILockStakingRewards {
    function earned(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function stakeFor(uint256 amount, address user) external;
    function getReward() external;
    function getRewardForUser(address user) external;
    function withdraw(uint256 nonce) external;
    function withdrawAndGetReward(uint256 nonce) external;
}

interface IBEP20Permit {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract LockStakingLPRewardFixedAPY is ILockStakingRewards, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    struct StakeNonceInfo {
        uint256 stakeTime;
        uint256 stakingTokenAmount;
        uint256 rewardsTokenAmount;
        uint256 rewardRate;
    }

    struct APYCheckpoint {
        uint256 timestamp;
        uint256 rewardRate;
    }

    IERC20 public immutable rewardsToken;
    INimbusPair public immutable stakingLPToken;
    INimbusRouter public swapRouter;
    address public immutable lPPairTokenA;
    address public immutable lPPairTokenB;
    uint256 public rewardRate; 
    uint256 public immutable lockDuration; 
    uint256 public constant rewardDuration = 365 days;

    uint256 public rateChangesNonce;
    mapping(address => mapping(uint256 => StakeNonceInfo)) public stakeNonceInfos;
    mapping(uint256 => APYCheckpoint) APYcheckpoints;
    bool public usePriceFeeds;
    IPriceFeed public priceFeed;
    event ToggleUsePriceFeeds(bool indexed usePriceFeeds);
    event RescueToken(address indexed to, address indexed token, uint amount);
    event RewardRateUpdated(uint256 indexed rateChangesNonce, uint256 rewardRate, uint256 timestamp);
    mapping(address => uint256) public stakeNonces;

    mapping(address => uint256) public weightedStakeDate;
    mapping(address => mapping(uint256 => uint256)) public stakeLocks;
    mapping(address => mapping(uint256 => uint256)) public stakeAmounts;
    mapping(address => mapping(uint256 => uint256)) public stakeAmountsRewardEquivalent;

    uint256 private _totalSupply;
    uint256 private _totalSupplyRewardEquivalent;
    uint256 private immutable _tokenADecimalCompensate;
    uint256 private immutable _tokenBDecimalCompensate;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _balancesRewardEquivalent;

    event RewardUpdated(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Rescue(address indexed to, uint amount);
    event RescueToken(address indexed to, address indexed token, uint amount);

    constructor(
        address _rewardsToken,
        address _stakingLPToken,
        address _lPPairTokenA,
        address _lPPairTokenB,
        address _swapRouter,
        uint _rewardRate,
        uint _lockDuration
    ) {
        require(_rewardsToken != address(0) && _stakingLPToken != address(0) && _lPPairTokenA != address(0) && _lPPairTokenB != address(0) && _swapRouter != address(0), "LockStakingLPRewardFixedAPY: Zero address(es)");
        rewardsToken = IERC20(_rewardsToken);
        stakingLPToken = INimbusPair(_stakingLPToken);
        swapRouter = INimbusRouter(_swapRouter);
        rewardRate = _rewardRate;
        lockDuration = _lockDuration;
        lPPairTokenA = _lPPairTokenA;
        lPPairTokenB = _lPPairTokenB;
        uint tokenADecimals = IERC20(_lPPairTokenA).decimals();
        require(tokenADecimals >= 6, "LockStakingLPRewardFixedAPY: small amount of decimals");
        _tokenADecimalCompensate = tokenADecimals - 6;
        uint tokenBDecimals = IERC20(_lPPairTokenB).decimals();
        require(tokenBDecimals >= 6, "LockStakingLPRewardFixedAPY: small amount of decimals");
        _tokenBDecimalCompensate = tokenBDecimals - 6;

        emit RewardRateUpdated(rateChangesNonce, _rewardRate, block.timestamp);
        APYcheckpoints[rateChangesNonce++] = APYCheckpoint(block.timestamp, rewardRate);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function totalSupplyRewardEquivalent() external view returns (uint256) {
        return _totalSupplyRewardEquivalent;
    }

    function getDecimalPriceCalculationCompensate() external view returns (uint tokenADecimalCompensate, uint tokenBDecimalCompensate) { 
        tokenADecimalCompensate = _tokenADecimalCompensate;
        tokenBDecimalCompensate = _tokenBDecimalCompensate;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }
    
    function balanceOfRewardEquivalent(address account) external view returns (uint256) {
        return _balancesRewardEquivalent[account];
    }

    function earnedByNonce(address account, uint256 nonce) public view returns (uint256) {
        return stakeNonceInfos[account][nonce].rewardsTokenAmount *
        (block.timestamp - stakeNonceInfos[account][nonce].stakeTime) *
        stakeNonceInfos[account][nonce].rewardRate / (100 * rewardDuration);
    }

    function earned(address account) public view override returns (uint256) {
        uint256 totalEarned;

        for (uint256 i = 0; i < stakeNonces[account]; i++) {
            totalEarned += earnedByNonce(account, i);
        }

        return totalEarned;
    }

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        require(amount > 0, "LockStakingLPRewardFixedAPY: Cannot stake 0");
        // permit
        IBEP20Permit(address(stakingLPToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _stake(amount, msg.sender);
    }

    function stake(uint256 amount) external override whenNotPaused nonReentrant {
        require(amount > 0, "LockStakingLPRewardFixedAPY: Cannot stake 0");
        _stake(amount, msg.sender);
    }

    function stakeFor(uint256 amount, address user) external override whenNotPaused nonReentrant {
        require(amount > 0, "LockStakingLPRewardFixedAPY: Cannot stake 0");
        require(user != address(0), "LockStakingLPRewardFixedAPY: Cannot stake for zero address");
        _stake(amount, user);
    }

    function _stake(uint256 amount, address user) private {
        IERC20(stakingLPToken).safeTransferFrom(msg.sender, address(this), amount);
        uint amountRewardEquivalent = getCurrentLPPrice() * amount / 1e18;

        _totalSupply += amount;
        _totalSupplyRewardEquivalent += amountRewardEquivalent;
        uint previousAmount = _balances[user];
        uint newAmount = previousAmount + amount;
        weightedStakeDate[user] = (weightedStakeDate[user] * previousAmount / newAmount) + (block.timestamp * amount / newAmount);
        _balances[user] = newAmount;

        uint stakeNonce = stakeNonces[user]++;
        stakeLocks[user][stakeNonce] = block.timestamp + lockDuration;
        stakeNonceInfos[msg.sender][stakeNonce].stakingTokenAmount = amount;
        stakeNonceInfos[msg.sender][stakeNonce].stakeTime = block.timestamp;
        stakeNonceInfos[msg.sender][stakeNonce].rewardRate = rewardRate;
        
        stakeAmountsRewardEquivalent[user][stakeNonce] = amountRewardEquivalent;
        _balancesRewardEquivalent[user] += amountRewardEquivalent;
        emit Staked(user, amount);
    }


    //A user can withdraw its staking tokens even if there is no rewards tokens on the contract account
    function withdraw(uint256 nonce) public override nonReentrant {
        require(stakeNonceInfos[msg.sender][nonce].stakingTokenAmount > 0, "LockStakingLPRewardFixedAPY: This stake nonce was withdrawn");
        require(stakeLocks[msg.sender][nonce] < block.timestamp, "LockStakingLPRewardFixedAPY: Locked");
        uint amount = stakeNonceInfos[msg.sender][nonce].stakingTokenAmount;
        uint amountRewardEquivalent = stakeNonceInfos[msg.sender][nonce].rewardsTokenAmount;

        _totalSupply -= amount;
        _totalSupplyRewardEquivalent -= amountRewardEquivalent;
        _balances[msg.sender] -= amount;
        _balancesRewardEquivalent[msg.sender] -= amountRewardEquivalent;
        IERC20(stakingLPToken).safeTransfer(msg.sender, amount);
        stakeNonceInfos[msg.sender][nonce].stakingTokenAmount = 0;
        stakeNonceInfos[msg.sender][nonce].rewardsTokenAmount = 0;
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public override nonReentrant {
        uint256 reward = earned(msg.sender);

        if (reward > 0) {
            weightedStakeDate[msg.sender] = block.timestamp;

            for (uint256 i = 0; i < stakeNonces[msg.sender]; i++) {
                stakeNonceInfos[msg.sender][i].stakeTime = block.timestamp;
            }

            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function getRewardForUser(address user) public override nonReentrant whenNotPaused {
        require(msg.sender == owner, "StakingRewards :: isn`t allowed to call rewards");

        uint256 reward = earned(user);

        if (reward > 0) {
            for (uint256 i = 0; i < stakeNonces[user]; i++) {
                stakeNonceInfos[user][i].stakeTime = block.timestamp;
            }
            rewardsToken.safeTransfer(user, reward);
            emit RewardPaid(user, reward);
        }
    }

    function withdrawAndGetReward(uint256 nonce) external override {
        getReward();
        withdraw(nonce);
    }

    function getCurrentLPPrice() public view returns (uint) {
        // LP PRICE = 2 * SQRT(reserveA * reaserveB ) * SQRT(token1/RewardTokenPrice * token2/RewardTokenPrice) / LPTotalSupply
        uint tokenAToRewardPrice;
        uint tokenBToRewardPrice;
        address rewardToken = address(rewardsToken);    
        address[] memory path = new address[](2);
        path[1] = address(rewardToken);

        if (lPPairTokenA != rewardToken) {
            path[0] = lPPairTokenA;
            tokenAToRewardPrice = swapRouter.getAmountsOut(10 ** 6, path)[1];
            if (_tokenADecimalCompensate > 0) 
                tokenAToRewardPrice = tokenAToRewardPrice * (10 ** _tokenADecimalCompensate);
        } else {
            tokenAToRewardPrice = 1e18;
        }
        
        if (lPPairTokenB != rewardToken) {
            path[0] = lPPairTokenB;  
            tokenBToRewardPrice = swapRouter.getAmountsOut(10 ** 6, path)[1];
            if (_tokenBDecimalCompensate > 0)
                tokenBToRewardPrice = tokenBToRewardPrice * (10 ** _tokenBDecimalCompensate);
        } else {
            tokenBToRewardPrice = 1e18;
        }

        uint totalLpSupply = IERC20(stakingLPToken).totalSupply();
        require(totalLpSupply > 0, "LockStakingLPRewardFixedAPY: No liquidity for pair");
        (uint reserveA, uint reaserveB,) = stakingLPToken.getReserves();
        uint price = 
            uint(2) * Math.sqrt(reserveA * reaserveB) * Math.sqrt(tokenAToRewardPrice * tokenBToRewardPrice) / totalLpSupply;
        
        return price;
    }


    function updateRewardAmount(uint256 reward) external onlyOwner {
        rewardRate = reward;
        emit RewardUpdated(reward);
    }

    function updateSwapRouter(address newSwapRouter) external onlyOwner {
        require(newSwapRouter != address(0), "LockStakingLPRewardFixedAPY: Address is zero");
        swapRouter = INimbusRouter(newSwapRouter);
    }

    function updateRewardRate(uint256 _rewardRate) external onlyOwner {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(rateChangesNonce, _rewardRate, block.timestamp);
        APYcheckpoints[rateChangesNonce++] = APYCheckpoint(block.timestamp, _rewardRate);
    }

    function updatePriceFeed(address newPriceFeed) external onlyOwner {
        require(newPriceFeed != address(0), "StakingRewardFixedAPY: Address is zero");
        priceFeed = IPriceFeed(newPriceFeed);
    }

    function toggleUsePriceFeeds() external onlyOwner {
        usePriceFeeds = !usePriceFeeds;
        emit ToggleUsePriceFeeds(usePriceFeeds);
    }

    function rescue(address to, IERC20 token, uint256 amount) external whenPaused onlyOwner {
        require(to != address(0), "LockStakingLPRewardFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "LockStakingLPRewardFixedAPY: Cannot rescue 0");
        require(token != stakingLPToken, "LockStakingLPRewardFixedAPY: Cannot rescue staking token");
        //owner can rescue rewardsToken if there is spare unused tokens on staking contract balance

        token.safeTransfer(to, amount);
        emit RescueToken(to, address(token), amount);
    }

    function rescue(address payable to, uint256 amount) external whenPaused onlyOwner {
        require(to != address(0), "LockStakingLPRewardFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "LockStakingLPRewardFixedAPY: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }
}