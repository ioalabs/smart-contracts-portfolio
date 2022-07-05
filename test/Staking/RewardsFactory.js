const {BN, constants} = require("@openzeppelin/test-helpers");
const {expect, use} = require("chai");
const {solidity} = require("ethereum-waffle");
const StakingRewards = artifacts.require("StakingRewards");
const NBU = artifacts.require("NBU");
const GNBU = artifacts.require("GNBU");

use(solidity);

contract("StakingRewards", (accounts) => {
    const [owner] = accounts;

    before(async () => {
        let [_, rewardDistribution] = accounts;
        this.stakingToken = await NBU.deployed();
        this.rewardToken = await GNBU.deployed();
        this.contract = await StakingRewards.deployed([rewardDistribution.address, this.rewardToken.address, new BN(1000000)]);

        await this.stakingToken.approve(this.contract.address, constants.MAX_UINT256);
        await this.rewardToken.approve(this.contract.address, constants.MAX_UINT256);
        await this.rewardToken.transfer(this.contract.address, new BN(100000000), {
            from: owner,
        });
    })

    it("testPaused", async () => {
        const stakeAmount = new BN(100000);
        const withdrawAmount = new BN(50000);

        // stake
        await expect(this.contract.stake(stakeAmount)).not.to.be.reverted;
        await this.contract.setPaused(true);
        await expect(this.contract.stake(stakeAmount)).to.be.reverted;

        // withdraw
        await this.contract.setPaused(false);
        await expect(this.contract.withdraw(withdrawAmount, '0x0')).not.to.be.reverted;
        await this.contract.setPaused(true);
        await expect(this.contract.withdraw(withdrawAmount)).to.be.reverted;

        // getReward
        await this.contract.setPaused(false);
        await expect(this.contract.getReward()).not.to.be.reverted;
        await this.contract.setPaused(true);
        await expect(this.contract.getReward()).to.be.reverted;
    })
});
