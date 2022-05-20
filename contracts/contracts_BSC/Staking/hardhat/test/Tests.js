const { expect } = require('chai')
const { ethers } = require('hardhat')
const { both, increaseTime, mineBlock } = require('./Utils')

describe('Test Staking', function () {
  const AMOUNT_NBU = ethers.utils.parseUnits('1000000', 18)

  beforeEach(async function () {
    ;[owner, user1, user2, ...accounts] = await ethers.getSigners()

    NBU = await ethers.getContractFactory('NBU')
    GNBU = await ethers.getContractFactory('GNBU')

    StakingGNBU_WeightGNBU = await ethers.getContractFactory(
      'StakingGNBU_WeightGNBU',
    )
    StakingGNBU_WeightNBU = await ethers.getContractFactory(
      'StakingGNBU_WeightNBU',
    )

    NimbusRouter = await ethers.getContractFactory('NimbusRouter')

    nbuToken = await NBU.deploy()
    gnbuToken = await GNBU.deploy()

    NimbusRouter = await NimbusRouter.deploy()

    StakingGNBU_WeightGNBU = await StakingGNBU_WeightGNBU.deploy(
      nbuToken.address,
      gnbuToken.address,
      NimbusRouter.address,
      10,
    )
    StakingGNBU_WeightNBU = await StakingGNBU_WeightNBU.deploy(
      nbuToken.address,
      gnbuToken.address,
      NimbusRouter.address,
      10,
    )

    const ownerNBUBalance = await nbuToken.balanceOf(owner.address)
    const ownerGNBUBalance = await gnbuToken.balanceOf(owner.address)

    // console.log(ownerNBUBalance.toString(), ownerGNBUBalance.toString())

    await nbuToken.transfer(StakingGNBU_WeightGNBU.address, AMOUNT_NBU)
    await nbuToken.transfer(StakingGNBU_WeightNBU.address, AMOUNT_NBU)

    const AMOUNT_GNBU = ethers.utils.parseUnits('1000', 18)
    await gnbuToken.transfer(user1.address, AMOUNT_GNBU)
    await gnbuToken.transfer(user2.address, AMOUNT_GNBU)

    await gnbuToken
      .connect(user1)
      .approve(StakingGNBU_WeightGNBU.address, ethers.constants.MaxUint256)
    await gnbuToken
      .connect(user1)
      .approve(StakingGNBU_WeightNBU.address, ethers.constants.MaxUint256)

    await gnbuToken
      .connect(user2)
      .approve(StakingGNBU_WeightGNBU.address, ethers.constants.MaxUint256)
    await gnbuToken
      .connect(user2)
      .approve(StakingGNBU_WeightNBU.address, ethers.constants.MaxUint256)

    // tokenId = (await both(nftTokens, 'mint', MINT_PARAMS)).reply
    // await increaseTime(604800);
    // await mineBlock();
  })

  it('Balance of is correct', async function () {
    expect(await nbuToken.balanceOf(StakingGNBU_WeightGNBU.address)).to.equal(
      AMOUNT_NBU,
    )
    expect(await nbuToken.balanceOf(StakingGNBU_WeightNBU.address)).to.equal(
      AMOUNT_NBU,
    )
  })

  it('Staked to StakingGNBU_WeightNBU', async function () {
    const AMOUNT_TO_STAKE = ethers.utils.parseUnits('1', 18)
    // user1 staked into wrong staking
    await StakingGNBU_WeightNBU.connect(user1).stake(AMOUNT_TO_STAKE)
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking

    expect(await StakingGNBU_WeightNBU.balanceOf(user1.address)).to.equal(
      AMOUNT_TO_STAKE,
    )
    expect(await StakingGNBU_WeightNBU.balanceOf(user2.address)).to.equal(
      AMOUNT_TO_STAKE,
    )

    const blockTimestampBefore = (await hre.ethers.provider.getBlock('latest'))
      .timestamp
    await increaseTime(100000)
    await mineBlock(10)
    const blockTimestampAfter = (await hre.ethers.provider.getBlock('latest'))
      .timestamp

    console.log(blockTimestampBefore, blockTimestampAfter)

    const user1Amount = await StakingGNBU_WeightNBU.earned(user1.address)
    const user2Amount = await StakingGNBU_WeightNBU.earned(user2.address)
    console.log(
      `user1 ${user1Amount.toString()} user2 ${user2Amount.toString()}`,
    )
  })

  it('Staked to StakingGNBU_WeightGNBU', async function () {
    const AMOUNT_TO_STAKE = ethers.utils.parseUnits('1', 18)
    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)
    await StakingGNBU_WeightGNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking

    expect(await StakingGNBU_WeightGNBU.balanceOf(user1.address)).to.equal(
      AMOUNT_TO_STAKE,
    )
    expect(await StakingGNBU_WeightGNBU.balanceOf(user2.address)).to.equal(
      AMOUNT_TO_STAKE,
    )

    const blockTimestampBefore = (await hre.ethers.provider.getBlock('latest'))
      .timestamp
    await increaseTime(100000)
    await mineBlock(10)
    const blockTimestampAfter = (await hre.ethers.provider.getBlock('latest'))
      .timestamp

    console.log(blockTimestampBefore, blockTimestampAfter)

    const user1Amount = await StakingGNBU_WeightGNBU.earned(user1.address)
    const user2Amount = await StakingGNBU_WeightGNBU.earned(user2.address)
    console.log(
      `user1 ${user1Amount.toString()} user2 ${user2Amount.toString()}`,
    )
  })

  it('Rate not changed between 2 stakes', async function () {
    const AMOUNT_TO_STAKE = ethers.utils.parseUnits('1', 5)
    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    expect(await StakingGNBU_WeightGNBU.balanceOf(user1.address)).to.equal(
      AMOUNT_TO_STAKE,
    )
    expect(await StakingGNBU_WeightNBU.balanceOf(user2.address)).to.equal(
      AMOUNT_TO_STAKE,
    )

    const blockTimestampBefore = (await hre.ethers.provider.getBlock('latest'))
      .timestamp
    await increaseTime(10000)
    await mineBlock(1)
    const blockTimestampAfter = (await hre.ethers.provider.getBlock('latest'))
      .timestamp

    console.log('Added time', blockTimestampAfter - blockTimestampBefore)

    //change rate
    // await NimbusRouter.setMultiplier(5)

    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    const earnedAmountWrong = await StakingGNBU_WeightGNBU.earned(user1.address)
    const earnedAmountRight = await StakingGNBU_WeightNBU.earned(user2.address)
    console.log(
      `user1 earned on Wrong ${earnedAmountWrong.toString()} user2 earned on Right ${earnedAmountRight.toString()}`,
    )
  })

  it('Rate increased +50% between 2 stakes', async function () {
    const AMOUNT_TO_STAKE = ethers.utils.parseUnits('1', 5)
    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    expect(await StakingGNBU_WeightGNBU.balanceOf(user1.address)).to.equal(
      AMOUNT_TO_STAKE,
    )
    expect(await StakingGNBU_WeightNBU.balanceOf(user2.address)).to.equal(
      AMOUNT_TO_STAKE,
    )

    const blockTimestampBefore = (await hre.ethers.provider.getBlock('latest'))
      .timestamp
    await increaseTime(10000)
    await mineBlock(1)
    const blockTimestampAfter = (await hre.ethers.provider.getBlock('latest'))
      .timestamp

    console.log('Added time', blockTimestampAfter - blockTimestampBefore)

    //change rate
    await NimbusRouter.setMultiplier(15)

    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    const earnedAmountWrong = await StakingGNBU_WeightGNBU.earned(user1.address)
    const earnedAmountRight = await StakingGNBU_WeightNBU.earned(user2.address)
    console.log(
      `user1 earned on Wrong ${earnedAmountWrong.toString()} user2 earned on Right ${earnedAmountRight.toString()}`,
    )
  })

  it('Rate decreased -50% between 2 stakes', async function () {
    const AMOUNT_TO_STAKE = ethers.utils.parseUnits('1', 5)
    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    expect(await StakingGNBU_WeightGNBU.balanceOf(user1.address)).to.equal(
      AMOUNT_TO_STAKE,
    )
    expect(await StakingGNBU_WeightNBU.balanceOf(user2.address)).to.equal(
      AMOUNT_TO_STAKE,
    )

    const blockTimestampBefore = (await hre.ethers.provider.getBlock('latest'))
      .timestamp
    await increaseTime(10000)
    await mineBlock(1)
    const blockTimestampAfter = (await hre.ethers.provider.getBlock('latest'))
      .timestamp

    console.log('Added time', blockTimestampAfter - blockTimestampBefore)

    //change rate
    await NimbusRouter.setMultiplier(5)

    // user1 staked into wrong staking
    await StakingGNBU_WeightGNBU.connect(user1).stake(AMOUNT_TO_STAKE)

    // user2 staked into right staking
    await StakingGNBU_WeightNBU.connect(user2).stake(AMOUNT_TO_STAKE)

    const earnedAmountWrong = await StakingGNBU_WeightGNBU.earned(user1.address)
    const earnedAmountRight = await StakingGNBU_WeightNBU.earned(user2.address)
    console.log(
      `user1 earned on Wrong ${earnedAmountWrong.toString()} user2 earned on Right ${earnedAmountRight.toString()}`,
    )
  })
})