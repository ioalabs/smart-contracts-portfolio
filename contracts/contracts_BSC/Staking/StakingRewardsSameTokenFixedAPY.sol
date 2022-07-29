// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

interface IStakingRewards {
    function earned(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function stake(uint256 amount) external;
    function stakeFor(uint256 amount, address user) external;
    function getReward() external;
    function withdraw(uint256 amount) external;
    function withdrawAndGetReward(uint256 amount) external;
    function exit() external;
}

interface IBEP20Permit {
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract StakingRewardsSameTokenFixedAPY is IStakingRewards, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    IERC20 public immutable stakingToken; //read only variable for compatibility with other contracts
    uint256 public rewardRate; 
    uint256 public constant rewardDuration = 365 days; 


    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    uint256 public rateChangesNonce;
    mapping(address => uint256) public weightedStakeDate;
    mapping(address => mapping(uint256 => StakeNonceInfo)) public stakeNonceInfos;
    mapping(address => uint256) public stakeNonces;
    mapping(uint256 => APYCheckpoint) APYcheckpoints;

    struct StakeNonceInfo {
        uint256 stakeTime;
        uint256 tokenAmount;
        uint256 rewardRate;
    }

    struct APYCheckpoint {
        uint256 timestamp;
        uint256 rewardRate;
    }


    event RewardUpdated(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Rescue(address indexed to, uint amount);
    event RescueToken(address indexed to, address indexed token, uint amount);
    event RewardRateUpdated(uint256 indexed rateChangesNonce, uint256 rewardRate, uint256 timestamp);


    constructor(
        address _token,
        uint _rewardRate
    ) {
        require(_token != address(0), "LockStakingRewardSameTokenFixedAPY: Zero address");
        token = IERC20(_token);
        stakingToken = IERC20(_token);
        rewardRate = _rewardRate;
        emit RewardRateUpdated(rateChangesNonce, _rewardRate, block.timestamp);
        APYcheckpoints[rateChangesNonce++] = APYCheckpoint(block.timestamp, rewardRate);
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }


    function earnedByNonce(address account, uint256 nonce) public view returns (uint256) {
        return stakeNonceInfos[account][nonce].tokenAmount * 
            (block.timestamp - stakeNonceInfos[account][nonce].stakeTime) *
             stakeNonceInfos[account][nonce].rewardRate / (100 * rewardDuration);
    }

    function earned(address account) public view override returns (uint256 totalEarned) {
        for (uint256 i = 0; i < stakeNonces[account]; i++) {
            totalEarned += earnedByNonce(account, i);
        }
    }

    function stakeWithPermit(uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        require(amount > 0, "StakingRewardsSameTokenFixedAPY: Cannot stake 0");
        _totalSupply += amount;
        uint previousAmount = _balances[msg.sender];
        uint newAmount = previousAmount + amount;
        weightedStakeDate[msg.sender] = (weightedStakeDate[msg.sender] * previousAmount / newAmount) + (block.timestamp * amount / newAmount);
        _balances[msg.sender] = newAmount;

        // permit
        IERC20Permit(address(token)).permit(msg.sender, address(this), amount, deadline, v, r, s);
        
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function stake(uint256 amount) external override nonReentrant {
        require(amount > 0, "StakingRewardsSameTokenFixedAPY: Cannot stake 0");
        token.safeTransferFrom(msg.sender, address(this), amount);
    
        _totalSupply += amount;
        _balances[msg.sender] += amount;

        uint stakeNonce = stakeNonces[msg.sender]++;
        stakeNonceInfos[msg.sender][stakeNonce].tokenAmount = amount;
        stakeNonceInfos[msg.sender][stakeNonce].stakeTime = block.timestamp;
        stakeNonceInfos[msg.sender][stakeNonce].rewardRate = rewardRate;
        emit Staked(msg.sender, amount);
    }

    function stakeFor(uint256 amount, address user) external override nonReentrant {
        require(amount > 0, "StakingRewardsSameTokenFixedAPY: Cannot stake 0");
        require(user != address(0), "StakingRewardsSameTokenFixedAPY: Cannot stake for zero address");
        _totalSupply += amount;
        uint previousAmount = _balances[user];
        uint newAmount = previousAmount + amount;
        weightedStakeDate[user] = (weightedStakeDate[user] * previousAmount / newAmount) + (block.timestamp * amount / newAmount);
        _balances[user] = newAmount;
        token.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(user, amount);
    }

    //A user can withdraw its staking tokens even if there is no rewards tokens on the contract account

    function withdraw(uint256 nonce) public override nonReentrant whenNotPaused {
        require(stakeNonceInfos[msg.sender][nonce].tokenAmount > 0, "StakingRewardsSameTokenFixedAPY: This stake nonce was withdrawn");
        uint amount = stakeNonceInfos[msg.sender][nonce].tokenAmount;
        _totalSupply -= amount;
        _balances[msg.sender] -= amount;
        stakeNonceInfos[msg.sender][nonce].tokenAmount = 0;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public override nonReentrant whenNotPaused {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            for (uint256 i = 0; i < stakeNonces[msg.sender]; i++) {
                stakeNonceInfos[msg.sender][i].stakeTime = block.timestamp;
            }
            token.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function withdrawAndGetReward(uint256 nonce) external override {
        getReward();
        withdraw(nonce);
    }

    function exit() external override {
        getReward();
        for (uint256 i = 0; i < stakeNonces[msg.sender]; i++) {
            if (stakeNonceInfos[msg.sender][i].tokenAmount > 0) {
                withdraw(i);
            }
        }
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) _pause();
        else _unpause();
    }

    function updateRewardRate(uint256 reward) external onlyOwner {
        rewardRate = reward;
        emit RewardUpdated(reward);
    }

    function rescue(address to, IERC20 tokenAddress, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingRewardsSameTokenFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "StakingRewardsSameTokenFixedAPY: Cannot rescue 0");
        require(tokenAddress != token, "StakingRewardsSameTokenFixedAPY: Cannot rescue staking/reward token");

        tokenAddress.safeTransfer(to, amount);
        emit RescueToken(to, address(tokenAddress), amount);
    }

    function rescue(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingRewardsSameTokenFixedAPY: Cannot rescue to the zero address");
        require(amount > 0, "StakingRewardsSameTokenFixedAPY: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }
}