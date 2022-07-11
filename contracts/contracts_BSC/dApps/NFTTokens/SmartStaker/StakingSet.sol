// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;
import './StakingSetStorage.sol';

contract StakingSet is StakingSetStorage {
    using AddressUpgradeable for address;
    using StringsUpgradeable for uint256;
    uint256 public constant MULTIPLIER = 1 ether;
    
    function initialize(
        address _nimbusRouter, 
        address _pancakeRouter,
        address _nimbusBNB, 
        address _binanceBNB,
        address _nbuToken, 
        address _gnbuToken,
        address _lpBnbCake,
        address _NbuStaking, 
        address _GnbuStaking,
        address _CakeStaking,
        address _hub
    ) public initializer {
        __Context_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        require(AddressUpgradeable.isContract(_nimbusRouter), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_pancakeRouter), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_nimbusBNB), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_binanceBNB), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_nbuToken), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_gnbuToken), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_lpBnbCake), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_NbuStaking), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_GnbuStaking), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_CakeStaking), "NimbusStakingSet_V1: Not contract");
        require(AddressUpgradeable.isContract(_hub), "NimbusStakingSet_V1: Not contract");

        nimbusRouter = IRouter(_nimbusRouter);
        pancakeRouter = IPancakeRouter(_pancakeRouter);
        nimbusBNB = IWBNB(_nimbusBNB);
        binanceBNB = IWBNB(_binanceBNB);
        nbuToken = IERC20Upgradeable(_nbuToken);
        gnbuToken = IERC20Upgradeable(_gnbuToken);
        lpBnbCake = IlpBnbCake(_lpBnbCake);
        NbuStaking = IStaking(_NbuStaking);
        GnbuStaking = IStaking(_GnbuStaking);
        CakeStaking = IMasterChef(_CakeStaking);
        cakeToken = IERC20Upgradeable(CakeStaking.CAKE());
        purchaseToken = _nimbusBNB;
        hubRouting = _hub;
        minPurchaseAmount = 1 ether;
        lockTime = 30 days;
        POOLS_NUMBER = 3;

        rewardDuration = IStaking(_NbuStaking).rewardDuration();


        IERC20Upgradeable(_nbuToken).approve(_nimbusRouter, type(uint256).max);
        IERC20Upgradeable(_gnbuToken).approve(_nimbusRouter, type(uint256).max);
        IERC20Upgradeable(_nbuToken).approve(_NbuStaking, type(uint256).max);
        IERC20Upgradeable(_gnbuToken).approve(_GnbuStaking, type(uint256).max);

        IERC20Upgradeable(_lpBnbCake).approve(_CakeStaking, type(uint256).max);
        IERC20Upgradeable(_lpBnbCake).approve(_pancakeRouter, type(uint256).max);
        IERC20Upgradeable(CakeStaking.CAKE()).approve(_pancakeRouter, type(uint256).max);


    }

    receive() external payable {
        require(msg.sender == address(nimbusBNB) 
        || msg.sender == address(binanceBNB)
        || msg.sender == address(nimbusRouter)
        || msg.sender == address(pancakeRouter),
      "StakingSet :: receiving BNB is not allowed");
    }

    modifier onlyHub {
        require(msg.sender == hubRouting, "HubRouting::caller is not the Staking Main contract");
        _;
    }

    // ========================== StakingSet functions ==========================


    function buyStakingSet(uint256 amount, uint256 tokenId) payable external onlyHub {
      require(msg.value >= minPurchaseAmount, "StakingSet: Token price is more than sent");
      uint amountBNB = msg.value;
      providedAmount[tokenId] = msg.value;

      (uint256 nbuAmount,uint256 gnbuAmount,uint256 cakeLPamount) = makeSwaps(amountBNB); 

      uint256 nonceNbu = NbuStaking.stakeNonces(address(this));
      _balancesRewardEquivalentNbu[tokenId] += nbuAmount;

     
      uint256 nonceGnbu = GnbuStaking.stakeNonces(address(this));
      uint256 amountRewardEquivalentGnbu = GnbuStaking.getEquivalentAmount(gnbuAmount);
      _balancesRewardEquivalentGnbu[tokenId] += amountRewardEquivalentGnbu;      

      IMasterChef.UserInfo memory user = CakeStaking.userInfo(cakePID, address(this));
      uint256 oldCakeShares = user.amount;

      UserSupply storage userSupply = tikSupplies[tokenId];
      userSupply.IsActive = true;
      userSupply.NbuStakingAmount = nbuAmount;
      userSupply.GnbuStakingAmount = gnbuAmount;
      userSupply.CakeBnbAmount = cakeLPamount;
      userSupply.NbuStakeNonce = nonceNbu;
      userSupply.GnbuStakeNonce = nonceGnbu;
      userSupply.SupplyTime = block.timestamp;
      userSupply.TokenId = tokenId;

      CakeStaking.deposit(cakePID,cakeLPamount);
      user = CakeStaking.userInfo(cakePID, address(this));
      userSupply.CakeShares = user.amount - oldCakeShares;
      userSupply.CurrentCakeShares = user.amount;
      userSupply.CurrentRewardDebt = user.rewardDebt;
      
      weightedStakeDate[tokenId] = userSupply.SupplyTime;
      counter++;
      
      NbuStaking.stake(nbuAmount);
      GnbuStaking.stake(gnbuAmount);

      emit BuyStakingSet(tokenId, purchaseToken, amountBNB, userSupply.SupplyTime);
    }

    function makeSwaps(uint256 amount) private returns(uint256,uint256,uint256) {
      uint256 swapDeadline = block.timestamp + 1200; // 20 mins
      amount *= MULTIPLIER;
      uint CakeEAmount = amount * 30 / 100;

      address[] memory path = new address[](2);
      path[0] = address(binanceBNB);
      path[1] = address(cakeToken);
      (uint[] memory amountsBnbCakeSwap) = pancakeRouter.swapExactETHForTokens{value:  (CakeEAmount / 2) / MULTIPLIER }(0, path, address(this), swapDeadline);
    (, uint amountBnbCake, uint liquidityBnbCake) = pancakeRouter.addLiquidityETH{value: (amount - CakeEAmount / 2) / MULTIPLIER }(address(cakeToken), amountsBnbCakeSwap[1], 0, 0, address(this), swapDeadline);
      uint NbuAmount = ((amount - MULTIPLIER * amountBnbCake - CakeEAmount/ 2 ) / 2) / MULTIPLIER;
      
      path[0] = address(nimbusBNB);
      path[1] = address(nbuToken);
      (uint[] memory amountsBnbNbuStaking) = nimbusRouter.swapExactBNBForTokens{value: NbuAmount}(0, path, address(this), swapDeadline);

      path[1] = address(gnbuToken);      
      (uint[] memory amountsBnbGnbuStaking) = nimbusRouter.swapExactBNBForTokens{value: NbuAmount}(0, path, address(this), swapDeadline);
      
      return (amountsBnbNbuStaking[1], amountsBnbGnbuStaking[1], liquidityBnbCake);
    }

    function getNFTfields(uint tokenId, uint NFTFieldIndex) 
        external 
        view 
        returns (address pool, address rewardToken, uint256 rewardAmount, uint256 percentage, uint256 stakedAmount) {
        (uint256 nbuReward, uint256 gnbuReward, uint256 cakeReward) = getTokenRewardsAmounts(tokenId);
        if (NFTFieldIndex == 0) {
            pool = address(NbuStaking);
            rewardToken = address(nbuToken);
            rewardAmount = nbuReward;
            percentage = 35 ether;
            stakedAmount = tikSupplies[tokenId].NbuStakingAmount;
        }
        else if (NFTFieldIndex == 1) {
            pool = address(GnbuStaking);
            rewardToken = address(nbuToken);
            rewardAmount = gnbuReward;
            percentage = 35 ether;
            stakedAmount = tikSupplies[tokenId].GnbuStakingAmount;
        }
        else if (NFTFieldIndex == 2) {
            pool = address(CakeStaking);
            rewardToken = address(cakeToken);
            rewardAmount = cakeReward;
            percentage = 30 ether;
            stakedAmount = tikSupplies[tokenId].CakeBnbAmount;
        }
    }

    function getNFTtiming(uint256 tokenId) external view returns(uint256 supplyTime, uint256 burnTime) {
        supplyTime = tikSupplies[tokenId].SupplyTime;
        burnTime = tikSupplies[tokenId].BurnTime;
    }  

    function withdrawUserRewards(uint tokenId, address tokenOwner) external nonReentrant onlyHub {
        UserSupply memory userSupply = tikSupplies[tokenId];
        require(userSupply.IsActive, "StakingSet: Not active");
        (uint256 nbuReward, uint256 cakeReward) = getTotalAmountsOfRewards(tokenId);
        _withdrawUserRewards(tokenId, tokenOwner, nbuReward, cakeReward);
    }
    
    function burnStakingSet(uint tokenId, address tokenOwner) external nonReentrant onlyHub {
        UserSupply storage userSupply = tikSupplies[tokenId];
        require(block.timestamp > userSupply.SupplyTime + lockTime, "StakingSet:: NFT is locked");
        require(userSupply.IsActive, "StakingSet: Token not active");

        (uint256 nbuReward, uint256 cakeReward) = getTotalAmountsOfRewards(tokenId);
        userSupply.IsActive = false;
        userSupply.BurnTime = block.timestamp;

        if(nbuReward > 0) {
            _withdrawUserRewards(tokenId, tokenOwner, nbuReward, cakeReward);
        }

        NbuStaking.withdraw(userSupply.NbuStakeNonce);
        GnbuStaking.withdraw(userSupply.GnbuStakeNonce);
        CakeStaking.withdraw(cakePID, userSupply.CakeBnbAmount);

        TransferHelper.safeTransfer(address(nbuToken), tokenOwner, userSupply.NbuStakingAmount);
        TransferHelper.safeTransfer(address(gnbuToken), tokenOwner, userSupply.GnbuStakingAmount);
        pancakeRouter.removeLiquidityETH(address(cakeToken), userSupply.CakeBnbAmount, 0, 0, tokenOwner, block.timestamp);

     
        emit BurnStakingSet(tokenId, userSupply.NbuStakingAmount, userSupply.GnbuStakingAmount, userSupply.CakeBnbAmount);     
    }

    function getTokenRewardsAmounts(uint tokenId) public view returns (uint256 NbuUserRewards, uint256 GnbuUserRewards, uint256 CakeUserRewards) {
        UserSupply memory userSupply = tikSupplies[tokenId];
        require(userSupply.IsActive, "StakingSet: Not active");
        
        NbuUserRewards = ((_balancesRewardEquivalentNbu[tokenId] * ((block.timestamp - weightedStakeDate[tokenId]) * 60)) * MULTIPLIER / (100 * rewardDuration)) / MULTIPLIER;
        GnbuUserRewards = ((_balancesRewardEquivalentGnbu[tokenId] * ((block.timestamp - weightedStakeDate[tokenId]) * 60)) * MULTIPLIER / (100 * rewardDuration)) / MULTIPLIER;
        CakeUserRewards = getUserCakeRewards(tokenId);
    }
    
    function getTotalAmountsOfRewards(uint tokenId) public view returns (uint256, uint256) {
        (uint256 NbuUserRewards, uint256 GnbuUserRewards, uint256 CakeUserRewards) = getTokenRewardsAmounts(tokenId);
        uint256 nbuReward = NbuUserRewards + GnbuUserRewards;
        return (nbuReward, CakeUserRewards);
    }

    function getUserCakeRewards(uint256 tokenId) public view returns (uint256) {
        UserSupply memory userSupply = tikSupplies[tokenId];
        require(userSupply.IsActive, "StakingSet: Not active");
        
        uint256 ACC_CAKE_PRECISION = 1e18;
        uint256 BOOST_PRECISION = 100 * 1e10;

        IMasterChef.PoolInfo memory pool = CakeStaking.poolInfo(cakePID);
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = pool.totalBoostedShare;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number - pool.lastRewardBlock;

            uint256 cakeReward = multiplier  * CakeStaking.cakePerBlock(pool.isRegular) * pool.allocPoint /
                (pool.isRegular ? CakeStaking.totalRegularAllocPoint() : CakeStaking.totalSpecialAllocPoint());
            accCakePerShare = accCakePerShare + cakeReward * ACC_CAKE_PRECISION / lpSupply;
        }

        uint256 boostedAmount = userSupply.CakeShares * CakeStaking.getBoostMultiplier(address(this), cakePID) * MULTIPLIER / BOOST_PRECISION;
        return (boostedAmount * accCakePerShare / ACC_CAKE_PRECISION - (userSupply.CurrentRewardDebt * userSupply.CakeShares * MULTIPLIER / userSupply.CurrentCakeShares)) / MULTIPLIER;
    }
    

    function _withdrawUserRewards(uint256 tokenId, address tokenOwner, uint256 totalNbuReward, uint256 totalCakeReward) private {
        require(totalNbuReward > 0 || totalCakeReward > 0, "StakingSet: Claim not enough");

        if (nbuToken.balanceOf(address(this)) < totalNbuReward) {
            NbuStaking.getReward();
            GnbuStaking.getReward();

            emit BalanceNBURewardsNotEnough(tokenOwner, tokenId, totalNbuReward);
        }

        weightedStakeDate[tokenId] = block.timestamp;
        require(nbuToken.balanceOf(address(this)) >= totalNbuReward, "StakingSet :: Not enough funds on contract to pay off claim");
        TransferHelper.safeTransfer(address(nbuToken), tokenOwner, totalNbuReward);

        CakeStaking.deposit(cakePID, 0);
        IMasterChef.UserInfo memory user = CakeStaking.userInfo(cakePID, address(this));
        tikSupplies[tokenId].CurrentRewardDebt = user.rewardDebt;
        tikSupplies[tokenId].CurrentCakeShares = user.amount;

        TransferHelper.safeTransfer(address(cakeToken), tokenOwner, totalCakeReward);

        emit WithdrawRewards(tokenOwner, tokenId, totalNbuReward, totalCakeReward);
    }

    // ========================== Owner functions ==========================

    function setLockTime(uint256 _lockTime) external onlyOwner {
        lockTime = _lockTime;

        emit UpdateLockTime(_lockTime);
    }

    function setCakePID(uint256 _cakePID) external onlyOwner {
        cakePID = _cakePID;

        emit UpdateCakePID(_cakePID);
    }

    function rescue(address to, address tokenAddress, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingSet: Cannot rescue to the zero address");
        require(amount > 0, "StakingSet: Cannot rescue 0");

        IERC20Upgradeable(tokenAddress).transfer(to, amount);
        emit RescueToken(to, address(tokenAddress), amount);
    }

    function rescue(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingSet: Cannot rescue to the zero address");
        require(amount > 0, "StakingSet: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }

    function updateNimbusRouter(address newNimbusRouter) external onlyOwner {
        require(AddressUpgradeable.isContract(newNimbusRouter), "StakingSet: Not a contract");
        nimbusRouter = IRouter(newNimbusRouter);
        emit UpdateNimbusRouter(newNimbusRouter);
    }
    
    function updateNbuStaking(address newLpStaking) external onlyOwner {
        require(AddressUpgradeable.isContract(newLpStaking), "StakingSet: Not a contract");
        NbuStaking = IStaking(newLpStaking);
        emit UpdateNbuStaking(newLpStaking);
    }
    
    function updateGnbuStaking(address newLpStaking) external onlyOwner {
        require(AddressUpgradeable.isContract(newLpStaking), "StakingSet: Not a contract");
        GnbuStaking = IStaking(newLpStaking);
        emit UpdateGnbuStaking(newLpStaking);
    }
    
    function updateCakeStaking(address newCakeStaking) external onlyOwner {
        require(AddressUpgradeable.isContract(newCakeStaking), "StakingSet: Not a contract");
        CakeStaking = IMasterChef(newCakeStaking);
        emit UpdateCakeStaking(newCakeStaking);
    }
    
    
    function updateTokenAllowance(address token, address spender, int amount) external onlyOwner {
        require(AddressUpgradeable.isContract(token), "StakingSet: Not a contract");
        uint allowance;
        if (amount < 0) {
            allowance = type(uint256).max;
        } else {
            allowance = uint256(amount);
        }
        IERC20Upgradeable(token).approve(spender, allowance);
    }
    
    function updateMinPurchaseAmount (uint newAmount) external onlyOwner {
        require(newAmount > 0, "StakingSet: Amount must be greater than zero");
        minPurchaseAmount = newAmount;
        emit UpdateMinPurchaseAmount(newAmount);
    }
}
