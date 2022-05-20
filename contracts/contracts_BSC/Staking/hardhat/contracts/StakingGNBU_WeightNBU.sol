// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

interface IBEP20 {
    function totalSupply() external view returns (uint256);

    function decimals() external view returns (uint8);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function getOwner() external view returns (address);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

interface INimbusRouter {
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

contract Ownable {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed from, address indexed to);

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ownable: Caller is not the owner");
        _;
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    function transferOwnership(address transferOwner) external onlyOwner {
        require(transferOwner != newOwner);
        newOwner = transferOwner;
    }

    function acceptOwnership() external virtual {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

library Address {
    function isContract(address account) internal view returns (bool) {
        // This method relies in extcodesize, which returns 0 for contracts in construction,
        // since the code is only stored at the end of the constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }
}

library SafeBEP20 {
    using Address for address;

    function safeTransfer(
        IBEP20 token,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transfer.selector, to, value)
        );
    }

    function safeTransferFrom(
        IBEP20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.transferFrom.selector, from, to, value)
        );
    }

    function safeApprove(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeBEP20: approve from non-zero to non-zero allowance"
        );
        callOptionalReturn(
            token,
            abi.encodeWithSelector(token.approve.selector, spender, value)
        );
    }

    function safeIncreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function safeDecreaseAllowance(
        IBEP20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) - value;
        callOptionalReturn(
            token,
            abi.encodeWithSelector(
                token.approve.selector,
                spender,
                newAllowance
            )
        );
    }

    function callOptionalReturn(IBEP20 token, bytes memory data) private {
        require(address(token).isContract(), "SafeBEP20: call to non-contract");

        (bool success, bytes memory returndata) = address(token).call(data);
        require(success, "SafeBEP20: low-level call failed");

        if (returndata.length > 0) {
            require(
                abi.decode(returndata, (bool)),
                "SafeBEP20: BEP20 operation did not succeed"
            );
        }
    }
}

contract ReentrancyGuard {
    /// @dev counter to allow mutex lock with only one SSTORE operation
    uint256 private _guardCounter;

    constructor() {
        // The counter starts at one to prevent changing it from zero to a non-zero
        // value, which is a more expensive operation.
        _guardCounter = 1;
    }

    modifier nonReentrant() {
        _guardCounter += 1;
        uint256 localCounter = _guardCounter;
        _;
        require(
            localCounter == _guardCounter,
            "ReentrancyGuard: reentrant call"
        );
    }
}

interface IStakingRewards {
    function earned(address account) external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function stake(uint256 amount) external;

    function stakeFor(uint256 amount, address user) external;

    function getReward() external;

    function withdraw(uint256 nonce) external;

    function withdrawAndGetReward(uint256 nonce) external;
}

interface IBEP20Permit {
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

contract StakingGNBU_WeightNBU is IStakingRewards, ReentrancyGuard, Ownable {
    using SafeBEP20 for IBEP20;

    IBEP20 public immutable rewardsToken;
    IBEP20 public immutable stakingToken;
    INimbusRouter public swapRouter;
    uint256 public rewardRate;
    uint256 public constant rewardDuration = 365 days;

    mapping(address => uint256) public weightedStakeDate;
    mapping(address => mapping(uint256 => uint256)) public stakeAmounts;
    mapping(address => mapping(uint256 => uint256))
        public stakeAmountsRewardEquivalent;
    mapping(address => uint256) public stakeNonces;

    uint256 private _totalSupply;
    uint256 private _totalSupplyRewardEquivalent;
    mapping(address => uint256) private _balances;
    mapping(address => uint256) private _balancesRewardEquivalent;

    event RewardUpdated(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event Rescue(address indexed to, uint256 amount);
    event RescueToken(
        address indexed to,
        address indexed token,
        uint256 amount
    );

    constructor(
        address _rewardsToken,
        address _stakingToken,
        address _swapRouter,
        uint256 _rewardRate
    ) {
        require(
            _rewardsToken != address(0) &&
                _stakingToken != address(0) &&
                _swapRouter != address(0),
            "StakingRewardFixedAPY: Zero address(es)"
        );
        rewardsToken = IBEP20(_rewardsToken);
        stakingToken = IBEP20(_stakingToken);
        swapRouter = INimbusRouter(_swapRouter);
        rewardRate = _rewardRate;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function totalSupplyRewardEquivalent() external view returns (uint256) {
        return _totalSupplyRewardEquivalent;
    }

    function balanceOf(address account)
        external
        view
        override
        returns (uint256)
    {
        return _balances[account];
    }

    function balanceOfRewardEquivalent(address account)
        external
        view
        returns (uint256)
    {
        return _balancesRewardEquivalent[account];
    }

    function earned(address account) public view override returns (uint256) {
        return
            (_balancesRewardEquivalent[account] *
                (block.timestamp - weightedStakeDate[account]) *
                rewardRate) / (100 * rewardDuration);
    }

    function stakeWithPermit(
        uint256 amount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant {
        require(amount > 0, "Cannot stake 0");
        // permit
        IBEP20Permit(address(stakingToken)).permit(
            msg.sender,
            address(this),
            amount,
            deadline,
            v,
            r,
            s
        );
        _stake(amount, msg.sender);
    }

    function stake(uint256 amount) external override nonReentrant {
        require(amount > 0, "StakingRewardFixedAPY: Cannot stake 0");
        _stake(amount, msg.sender);
    }

    function stakeFor(uint256 amount, address user)
        external
        override
        nonReentrant
    {
        require(amount > 0, "StakingRewardFixedAPY: Cannot stake 0");
        require(
            user != address(0),
            "StakingRewardFixedAPY: Cannot stake for zero address"
        );
        _stake(amount, user);
    }

    function _stake(uint256 amount, address user) private {
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 amountRewardEquivalent = getEquivalentAmount(amount);
        uint256 newAmountRewardEquivalent = _balancesRewardEquivalent[user] +
            amountRewardEquivalent;

        _totalSupply += amount;
        _totalSupplyRewardEquivalent += amountRewardEquivalent;
        uint256 previousAmount = _balances[user];
        uint256 newAmount = previousAmount + amount;
        weightedStakeDate[user] =
            ((weightedStakeDate[user] * _balancesRewardEquivalent[user]) /
                newAmountRewardEquivalent) +
            ((block.timestamp * amountRewardEquivalent) /
                newAmountRewardEquivalent);
        _balances[user] = newAmount;

        uint256 stakeNonce = stakeNonces[user]++;
        stakeAmounts[user][stakeNonce] = amount;

        stakeAmountsRewardEquivalent[user][stakeNonce] = amountRewardEquivalent;
        _balancesRewardEquivalent[user] = newAmountRewardEquivalent;
        emit Staked(user, amount);
    }

    //A user can withdraw its staking tokens even if there is no rewards tokens on the contract account
    function withdraw(uint256 nonce) public override nonReentrant {
        require(
            stakeAmounts[msg.sender][nonce] > 0,
            "StakingRewardFixedAPY: This stake nonce was withdrawn"
        );
        uint256 amount = stakeAmounts[msg.sender][nonce];
        uint256 amountRewardEquivalent = stakeAmountsRewardEquivalent[
            msg.sender
        ][nonce];
        _totalSupply -= amount;
        _totalSupplyRewardEquivalent -= amountRewardEquivalent;
        _balances[msg.sender] -= amount;
        _balancesRewardEquivalent[msg.sender] -= amountRewardEquivalent;
        stakingToken.safeTransfer(msg.sender, amount);
        stakeAmounts[msg.sender][nonce] = 0;
        stakeAmountsRewardEquivalent[msg.sender][nonce] = 0;
        emit Withdrawn(msg.sender, amount);
    }

    function getReward() public override nonReentrant {
        uint256 reward = earned(msg.sender);
        if (reward > 0) {
            weightedStakeDate[msg.sender] = block.timestamp;
            rewardsToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function withdrawAndGetReward(uint256 nonce) external override {
        getReward();
        withdraw(nonce);
    }

    function getEquivalentAmount(uint256 amount) public view returns (uint256) {
        address[] memory path = new address[](2);

        uint256 equivalent;
        if (stakingToken != rewardsToken) {
            path[0] = address(stakingToken);
            path[1] = address(rewardsToken);
            equivalent = swapRouter.getAmountsOut(amount, path)[1];
        } else {
            equivalent = amount;
        }

        return equivalent;
    }

    function updateRewardAmount(uint256 reward) external onlyOwner {
        rewardRate = reward;
        emit RewardUpdated(reward);
    }

    function updateSwapRouter(address newSwapRouter) external onlyOwner {
        require(
            newSwapRouter != address(0),
            "StakingRewardFixedAPY: Address is zero"
        );
        swapRouter = INimbusRouter(newSwapRouter);
    }

    function rescue(
        address to,
        address token,
        uint256 amount
    ) external onlyOwner {
        require(
            to != address(0),
            "StakingRewardFixedAPY: Cannot rescue to the zero address"
        );
        require(amount > 0, "StakingRewardFixedAPY: Cannot rescue 0");
        require(
            token != address(stakingToken),
            "StakingRewardFixedAPY: Cannot rescue staking token"
        );
        //owner can rescue rewardsToken if there is spare unused tokens on staking contract balance

        IBEP20(token).safeTransfer(to, amount);
        emit RescueToken(to, address(token), amount);
    }

    function rescue(address payable to, uint256 amount) external onlyOwner {
        require(
            to != address(0),
            "StakingRewardFixedAPY: Cannot rescue to the zero address"
        );
        require(amount > 0, "StakingRewardFixedAPY: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }
}