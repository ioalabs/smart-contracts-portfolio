pragma solidity ^0.8.2;
import './StakingSetStorage.sol';


contract StakingSetBusd is StakingSetStorage {
    using Address for address;
    using Strings for uint256;
    
    address public target;

    function initialize(
        address _nimbusRouter, 
        address _pancakeRouter,
        address _nimbusBNB, 
        address _binanceBNB,
        address _nbuToken, 
        address _gnbuToken,
        address _busdToken, 
        address _lpBnbCake,
        address _NbuStaking, 
        address _GnbuStaking,
        address _CakeStaking,
        address _hub
    ) external onlyOwner {
        require(Address.isContract(_nimbusRouter), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_pancakeRouter), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_nimbusBNB), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_binanceBNB), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_nbuToken), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_gnbuToken), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_busdToken), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_lpBnbCake), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_NbuStaking), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_GnbuStaking), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_CakeStaking), "NimbusStakingSet_V1: Not contract");
        require(Address.isContract(_hub), "NimbusStakingSet_V1: Not contract");

        nimbusRouter = IRouter(_nimbusRouter);
        pancakeRouter = IPancakeRouter(_pancakeRouter);
        nimbusBNB = IWBNB(_nimbusBNB);
        binanceBNB = IWBNB(_binanceBNB);
        nbuToken = IBEP20(_nbuToken);
        gnbuToken = IBEP20(_gnbuToken);
        busdToken = IBEP20(_busdToken);
        lpBnbCake = IlpBnbCake(_lpBnbCake);
        NbuStaking = INbuStaking(_NbuStaking);
        GnbuStaking = IGnbuStaking(_GnbuStaking);
        CakeStaking = IMasterChef(_CakeStaking);
        cakeToken = IBEP20(CakeStaking.CAKE());
        purchaseToken = _busdToken;
        hubRouting = _hub;

        minPurchaseAmount = 10 ether;
        rewardDuration = INbuStaking(_NbuStaking).rewardDuration();

        IBEP20(_nbuToken).approve(_nimbusRouter, type(uint256).max);
        IBEP20(_gnbuToken).approve(_nimbusRouter, type(uint256).max);
        IBEP20(_nbuToken).approve(_NbuStaking, type(uint256).max);
        IBEP20(_gnbuToken).approve(_GnbuStaking, type(uint256).max);
        IBEP20(_busdToken).approve(_nimbusRouter, type(uint256).max);

        IBEP20(_lpBnbCake).approve(_CakeStaking, type(uint256).max);
        IBEP20(_lpBnbCake).approve(_pancakeRouter, type(uint256).max);
        IBEP20(CakeStaking.CAKE()).approve(_pancakeRouter, type(uint256).max);
    }

    receive() external payable {
        assert(msg.sender == address(nimbusBNB) 
        || msg.sender == address(binanceBNB)
        || msg.sender == address(nimbusRouter)
        || msg.sender == address(pancakeRouter)
      );
    }

    modifier onlyHub {
        require(msg.sender == hubRouting, "HubRouting::caller is not the Staking Main contract");
        _;
    }

    // ========================== StakingSet functions ==========================


    function buyStakingSet(uint256 amount, uint256 tokenId) external {
      require(msg.sender == hubRouting, "StakingSet:: Caller is not the HubRouting contract");
      require(amount >= minPurchaseAmount, "StakingSet: Token price is more than sent");
      providedAmount[tokenId] = amount;

      (uint256 nbuAmount,uint256 gnbuAmount,uint256 cakeLPamount) = makeSwaps(amount); 

      NbuStaking.stake(nbuAmount);
      _balancesRewardEquivalentNbu[tokenId] += nbuAmount;

      uint256 noncesGnbu = GnbuStaking.stakeNonces(address(this));
      GnbuStaking.stake(gnbuAmount);
      uint amountRewardEquivalentGnbu = GnbuStaking.getEquivalentAmount(gnbuAmount);
      _balancesRewardEquivalentGnbu[tokenId] += amountRewardEquivalentGnbu;

      
      IMasterChef.UserInfo memory user = CakeStaking.userInfo(CAKE_PID, address(this));
      uint oldCakeShares = user.amount;

      CakeStaking.deposit(CAKE_PID,cakeLPamount);
      user = CakeStaking.userInfo(CAKE_PID, address(this));

      UserSupply storage userSupply = tikSupplies[tokenId];
      userSupply.IsActive = true;
      userSupply.NbuStakingAmount = nbuAmount;
      userSupply.GnbuStakingAmount = gnbuAmount;
      userSupply.CakeBnbAmount = cakeLPamount;
      userSupply.GnbuStakeNonce = noncesGnbu;
      userSupply.CakeShares = user.amount - oldCakeShares;
      userSupply.CurrentCakeShares = user.amount;
      userSupply.CurrentRewardDebt = user.rewardDebt;
      userSupply.SupplyTime = block.timestamp;
      userSupply.TokenId = tokenId;

      weightedStakeDate[tokenId] = userSupply.SupplyTime;
      counter++;

      emit BuyStakingSet(tokenId, purchaseToken, amount, userSupply.SupplyTime);
    }

    function makeSwaps(uint256 amount) private returns(uint256,uint256,uint256) {
      address[] memory path = new address[](2);
      path[0] = address(busdToken);
      path[1] = address(nimbusBNB);
      (uint[] memory amountsBusdBnb) = nimbusRouter.swapExactTokensForBNB(amount, 0, path, address(this), block.timestamp);
      amount = amountsBusdBnb[1];
      
      uint CakeEAmount = amount / 100 * 30;

      path[0] = address(binanceBNB);
      path[1] = address(cakeToken);
      (uint[] memory amountsBnbCakeSwap) = pancakeRouter.swapExactETHForTokens{value:  CakeEAmount/ 2}(0, path, address(this), block.timestamp);
    (, uint amountBnbCake, uint liquidityBnbCake) = pancakeRouter.addLiquidityETH{value: amount - CakeEAmount/ 2 }(address(cakeToken), amountsBnbCakeSwap[1], 0, 0, address(this), block.timestamp);
      uint NbuAmount = (amount - amountBnbCake - CakeEAmount/ 2 ) / 2;
      
      path[0] = address(nimbusBNB);
      path[1] = address(nbuToken);
      (uint[] memory amountsBnbNbuStaking) = nimbusRouter.swapExactBNBForTokens{value: NbuAmount}(0, path, address(this), block.timestamp);

      path[1] = address(gnbuToken);      
      (uint[] memory amountsBnbGnbuStaking) = nimbusRouter.swapExactBNBForTokens{value: NbuAmount}(0, path, address(this), block.timestamp);

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

    function withdrawUserRewards(uint tokenId, address tokenOwner) external nonReentrant {
        require(msg.sender == hubRouting, "StakingSet:: Caller is not the HubRouting contract");
        UserSupply memory userSupply = tikSupplies[tokenId];
        require(userSupply.IsActive, "StakingSet: Not active");
        (uint256 nbuReward, uint256 cakeReward) = getTotalAmountsOfRewards(tokenId);
        _withdrawUserRewards(tokenId, tokenOwner, nbuReward, cakeReward);
    }
    
    function burnStakingSet(uint tokenId, address tokenOwner) external nonReentrant {
        require(msg.sender == hubRouting, "StakingSet:: Caller is not the HubRouting contract");
        UserSupply storage userSupply = tikSupplies[tokenId];
        require(block.timestamp > userSupply.SupplyTime + lockTime, "StakingSet:: NFT is locked");
        require(userSupply.IsActive, "StakingSet: Token not active");
        (uint256 nbuReward, uint256 cakeReward) = getTotalAmountsOfRewards(tokenId);
        
        if(nbuReward > 0) {
            _withdrawUserRewards(tokenId, tokenOwner, nbuReward, cakeReward);
        }


        NbuStaking.withdraw(userSupply.NbuStakingAmount);
        GnbuStaking.withdraw(userSupply.GnbuStakeNonce);
        CakeStaking.withdraw(CAKE_PID, userSupply.CakeBnbAmount);

        TransferHelper.safeTransfer(address(nbuToken), tokenOwner, userSupply.NbuStakingAmount);
        TransferHelper.safeTransfer(address(gnbuToken), tokenOwner, userSupply.GnbuStakingAmount);
        pancakeRouter.removeLiquidityETH(address(cakeToken), userSupply.CakeBnbAmount, 0, 0, tokenOwner, block.timestamp);
        
        userSupply.IsActive = false;
        userSupply.BurnTime = block.timestamp;
     
        emit BurnStakingSet(tokenId, userSupply.NbuStakingAmount, userSupply.GnbuStakingAmount, userSupply.CakeBnbAmount);     
    }

   



    function getTokenRewardsAmounts(uint tokenId) public view returns (uint256 NbuUserRewards, uint256 GnbuUserRewards, uint256 CakeUserRewards) {
        UserSupply memory userSupply = tikSupplies[tokenId];
        require(userSupply.IsActive, "StakingSet: Not active");
        
        NbuUserRewards = (_balancesRewardEquivalentNbu[tokenId] * ((block.timestamp - weightedStakeDate[tokenId]) * 60)) / (100 * rewardDuration);
        GnbuUserRewards = (_balancesRewardEquivalentGnbu[tokenId] * ((block.timestamp - weightedStakeDate[tokenId]) * 60)) / (100 * rewardDuration);
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

        IMasterChef.PoolInfo memory pool = CakeStaking.poolInfo(CAKE_PID);
        uint256 accCakePerShare = pool.accCakePerShare;
        uint256 lpSupply = pool.totalBoostedShare;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number - pool.lastRewardBlock;

            uint256 cakeReward = multiplier * CakeStaking.cakePerBlock(pool.isRegular) * pool.allocPoint /
                (pool.isRegular ? CakeStaking.totalRegularAllocPoint() : CakeStaking.totalSpecialAllocPoint());
            accCakePerShare = accCakePerShare + cakeReward * ACC_CAKE_PRECISION / lpSupply;
        }

        uint256 boostedAmount = userSupply.CakeShares * CakeStaking.getBoostMultiplier(address(this), CAKE_PID) / BOOST_PRECISION;
        return boostedAmount * accCakePerShare / ACC_CAKE_PRECISION - (userSupply.CurrentRewardDebt * userSupply.CakeShares / userSupply.CurrentCakeShares);
    }
    

    function _withdrawUserRewards(uint256 tokenId, address tokenOwner, uint256 totalNbuReward, uint256 totalCakeReward) private {
        require(totalNbuReward > 0 || totalCakeReward > 0, "StakingSet: Claim not enough");

        if (nbuToken.balanceOf(address(this)) < totalNbuReward) {
            NbuStaking.getReward();
            GnbuStaking.getReward();

            emit BalanceNBURewardsNotEnough(tokenOwner, tokenId, totalNbuReward);
        }

        TransferHelper.safeTransfer(address(nbuToken), tokenOwner, totalNbuReward);
        weightedStakeDate[tokenId] = block.timestamp;

        CakeStaking.deposit(CAKE_PID, 0);
        IMasterChef.UserInfo memory user = CakeStaking.userInfo(CAKE_PID, address(this));
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

    function setCakePID(uint256 _CAKE_PID) external onlyOwner {
        CAKE_PID = _CAKE_PID;

        emit UpdateCakePID(_CAKE_PID);
    }

    function rescue(address to, address tokenAddress, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingSet: Cannot rescue to the zero address");
        require(amount > 0, "StakingSet: Cannot rescue 0");

        IBEP20(tokenAddress).transfer(to, amount);
        emit RescueToken(to, address(tokenAddress), amount);
    }

    function rescue(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "StakingSet: Cannot rescue to the zero address");
        require(amount > 0, "StakingSet: Cannot rescue 0");

        to.transfer(amount);
        emit Rescue(to, amount);
    }

    function updateNimbusRouter(address newNimbusRouter) external onlyOwner {
        require(Address.isContract(newNimbusRouter), "StakingSet: Not a contract");
        nimbusRouter = IRouter(newNimbusRouter);
        emit UpdateNimbusRouter(newNimbusRouter);
    }
    
    function updateNbuStaking(address newLpStaking) external onlyOwner {
        require(Address.isContract(newLpStaking), "StakingSet: Not a contract");
        NbuStaking = INbuStaking(newLpStaking);
        emit UpdateNbuStaking(newLpStaking);
    }
    
    function updateGnbuStaking(address newLpStaking) external onlyOwner {
        require(Address.isContract(newLpStaking), "StakingSet: Not a contract");
        GnbuStaking = IGnbuStaking(newLpStaking);
        emit UpdateGnbuStaking(newLpStaking);
    }
    
    function updateCakeStaking(address newCakeStaking) external onlyOwner {
        require(Address.isContract(newCakeStaking), "StakingSet: Not a contract");
        CakeStaking = IMasterChef(newCakeStaking);
        emit UpdateCakeStaking(newCakeStaking);
    }
    
    
    function updateTokenAllowance(address token, address spender, int amount) external onlyOwner {
        require(Address.isContract(token), "StakingSet: Not a contract");
        uint allowance;
        if (amount < 0) {
            allowance = type(uint256).max;
        } else {
            allowance = uint256(amount);
        }
        IBEP20(token).approve(spender, allowance);
    }
    
    function updateMinPurchaseAmount (uint newAmount) external onlyOwner {
        require(newAmount > 0, "StakingSet: Amount must be greater than zero");
        minPurchaseAmount = newAmount;
        emit UpdateMinPurchaseAmount(newAmount);
    }
}