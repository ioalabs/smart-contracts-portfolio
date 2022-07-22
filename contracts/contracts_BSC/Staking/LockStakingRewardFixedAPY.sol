// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface INimbusRouter {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
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

contract LockStakingRewardFixedAPY is ILockStakingRewards, ReentrancyGuard, Pausable, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable rewardsToken;
    IERC20 public immutable stakingToken;
    INimbusRouter public swapRouter;
    uint256 public rewardRate; 
    uint256 public immutable lockDuration; 
    uint256 public constant rewardDuration = 365 days; 

    mapping(address => uint256) public weightedStakeDate;
    mapping(address => mapping(uint256 => uint256)) public stakeLocks;
    mapping(address => mapping(uint256 => uint256)) public stakeAmounts;
    mapping(address => mapping(uint256 => uint256)) public stakeAmountsRewardEquivalent;
    mapping(address => uint256) public stakeNonces;

    uint256 private _totalSupply;
    uint256 private _totalSupplyRewardEquivalent;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _balancesRewardEquivalent;

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

    uint256 public rateChangesNonce;
    mapping(address => mapping(uint256 => StakeNonceInfo)) public stakeNonceInfos;
    mapping(uint256 => APYCheckpoint) APYcheckpoints;
    bool public usePriceFeeds;
    IPriceFeed public priceFeed;
    event ToggleUsePriceFeeds(bool indexed usePriceFeeds);
    event RescueToken(address indexed to, address indexed token, uint amount);
    event RewardRateUpdated(uint256 indexed rateChangesNonce, uint256 rewardRate, uint256 timestamp);
    mapping(address => uint256) public stakeNonces;

    event RewardUpdated(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Rescue(address indexed to, uint amount);
    event RescueToken(address indexed to, address indexed token, uint amount);

    constructor(
        address _rewardsToken,
        address _stakingToken,
        address _swapRouter,
        uint _rewardRate,
        uint _lockDuration
    ) {
        require(_rewardsToken != address(0) && _swapRouter != address(0), "LockStakingRewardFixedAPY: Zero address(es)");
        rewardsToken = IERC20(_rewardsToken);
        stakingToken = IERC20(_stakingToken);
        swapRouter = INimbusRouter(_swapRouter);
        rewardRate = _rewardRate;
        lockDuration = _lockDuration;

        emit RewardRateUpdated(rateChangesNonce, _rewardRate, block.timestamp);
        APYcheckpoints[rateChangesNonce++] = APYCheckpoint(block.timestamp, rewardRate);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function totalSupplyRewardEquivalent() external view returns (uint256) {
        return _totalSupplyRewardEquivalent;
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
        stakeNonceInfos[account][nonce].rewardRate / (100 * rewardsDuration);
    }

    function earned(address account) public view override returns (uint256) {
        uint256 totalEarned;

        for (uint256 i = 0; i < stakeNonces[account]; i++) {
            totalEarned += earnedByNonce(account, i);
        }

        return totalEarned;
    }

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        require(amount > 0, "LockStakingRewardFixedAPY: Cannot stake 0");
        // permit
        IBEP20Permit(address(stakingToken)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        _stake(amount, msg.sender);
    }

    function stake(uint256 amount) external override whenNotPaused nonReentrant {
        require(amount > 0, "LockStakingRewardFixedAPY: Cannot stake 0");
        _stake(amount, msg.sender);
    }

    function stakeFor(uint256 amount, address user) external override whenNotPaused nonReentrant {
        require(amount > 0, "LockStakingRewardFixedAPY: Cannot stake 0");
        require(user != address(0), "LockStakingRewardFixedAPY: Cannot stake for zero address");
        _stake(amount, user);
    }

    function _stake(uint256 amount, address user) private {
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint amountRewardEquivalent = getEquivalentAmount(amount);

        _totalSupply += amount;
        _totalSupplyRewardEquivalent += amountRewardEquivalent;
        uint previousAmount = _balances[user];
        uint newAmount = previousAmount + amount;
        weightedStakeDate[user] = (weightedStakeDate[user] * (previousAmount) / newAmount) + (block.timestamp * amount / newAmount);
        _balances[user] = newAmount;
        uint stakeNonce = stakeNonces[msg.sender]++;

        uint stakeNonce = stakeNonces[user]++;

        stakeNonceInfos[msg.sender][stakeNonce].stakingTokenAmount = amount;
        stakeNonceInfos[msg.sender][stakeNonce].stakeTime = block.timestamp;
        stakeNonceInfos[msg.sender][stakeNonce].rewardRate = rewardRate;
        stakeLocks[user][stakeNonce] = block.timestamp + lockDuration;
        
        stakeAmountsRewardEquivalent[user][stakeNonce] = amountRewardEquivalent;
        _balancesRewardEquivalent[user] += amountRewardEquivalent;
        emit Staked(user, amount);
    }

    //A user can withdraw its staking tokens even if there is no rewards tokens on the contract account
    function withdraw(uint256 nonce) public override whenNotPaused nonReentrant {
        require(stakeNonceInfos[msg.sender][nonce].stakingTokenAmount > 0, "LockStakingRewardFixedAPY: This stake nonce was withdrawn");
        require(stakeLocks[msg.sender][nonce] < block.timestamp, "LockStakingRewardFixedAPY: Locked");
        uint amount = stakeNonceInfos[msg.sender][nonce].stakingTokenAmount;
        uint amountRewardEquivalent = stakeNonceInfos[msg.sender][nonce].rewardsTokenAmount;

        _totalSupply -= amount;
        _totalSupplyRewardEquivalent -= amountRewardEquivalent;
        _balances[msg.sender] -= amount;
        _balancesRewardEquivalent[msg.sender] -= amountRewardEquivalent;
        stakingToken.safeTransfer(msg.sender, amount);
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

    function withdrawAndGetReward(uint256 nonce) external override {
        getReward();
        withdraw(nonce);
    }

    function getEquivalentAmount(uint amount) public view returns (uint) {
        address[] memory path = new address[](2);

        uint equivalent;
        if (stakingToken != rewardsToken) {
            path[0] = address(stakingToken);            
            path[1] = address(rewardsToken);
            equivalent = swapRouter.getAmountsOut(amount, path)[1];
        } else {
            equivalent = amount;   
        }
        
        return equivalent;
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

    function updateRewardAmount(uint256 reward) external onlyOwner {
        rewardRate = reward;
        emit RewardUpdated(reward);
    }

    function updateSwapRouter(address newSwapRouter) external onlyOwner {
        require(newSwapRouter != address(0), "LockStakingRewardFixedAPY: Address is zero");
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

    function rescue(address to, address token, uint256 amount) external whenPaused onlyOwner {
        require(to != address(0), "LockStakingRewardFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "LockStakingRewardFixedAPY: Cannot rescue 0");
        require(token != address(stakingToken), "LockStakingRewardFixedAPY: Cannot rescue staking token");
        //owner can rescue rewardsToken if there is spare unused tokens on staking contract balance

        IERC20(token).safeTransfer(to, amount);
        emit RescueToken(to, address(token), amount);
    }

    function rescue(address payable to, uint256 amount) external whenPaused onlyOwner {
        require(to != address(0), "LockStakingRewardFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "LockStakingRewardFixedAPY: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }
}