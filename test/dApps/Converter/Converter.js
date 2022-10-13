
const { signDaiPermit, signERC2612Permit } = require("../../utils/eth-permit");
const { splitSignature } = require('ethers/lib/utils');
const { BigNumberish, constants, Signature, Wallet } = require('ethers');
const { expect } = require("chai");
const { ethers, upgrades, waffle } = require("hardhat");
const { both, increaseTime, mineBlock } = require("./../Utils");

describe("Converter PriceFeed test", function () {

    beforeEach(async function () {
        [owner, other, user2, ...accounts] = await ethers.getSigners();

        WBNB = await ethers.getContractFactory("NBU_WBNB")
        WbnbContract = await WBNB.deploy();
        await WbnbContract.deployed()

        BUSD = await ethers.getContractFactory("BUSDTest")
        BusdContract = await BUSD.deploy();
        await BusdContract.deployed()

        NBU = await ethers.getContractFactory("NBU")
        NBUContract = await NBU.deploy();
        await NBUContract.deployed()

        NBU2 = await ethers.getContractFactory("NBU")
        NBU2Contract = await NBU.deploy();
        await NBU2Contract.deployed()

        Converter = await ethers.getContractFactory("Converter")
        ConverterContract = await Converter.deploy(NBUContract.address, NBU2Contract.address,owner.address);
        await ConverterContract.deployed()

        PriceFeeds = await ethers.getContractFactory("PriceFeeds")
        PriceFeedscontract = await PriceFeeds.deploy();
        await PriceFeedscontract.deployed()

        NimbusPriceFeed1 = await ethers.getContractFactory("NimbusPriceFeed1")
        NimbusPriceFeed1Contract = await NimbusPriceFeed1.deploy();
        await NimbusPriceFeed1Contract.deployed()

        NimbusPriceFeed2 = await ethers.getContractFactory("NimbusPriceFeed2")
        NimbusPriceFeed2Contract = await NimbusPriceFeed2.deploy();
        await NimbusPriceFeed2Contract.deployed()
    });

    it("Test PriceFeed using + convertWithPermit ", async function () {
        const provider = waffle.provider;
        const curTimestamp = (await ethers.provider.getBlock(await ethers.provider.getBlockNumber())).timestamp;
        const result = await signERC2612Permit(provider, NBUContract.address, other.address, ConverterContract.address, "1000000000000000000000", curTimestamp + 100);
        console.log(result)
        await NimbusPriceFeed1Contract.connect(owner).setLatestAnswer("1000000000000000000")
        await NimbusPriceFeed2Contract.connect(owner).setLatestAnswer("1000000000000000000")
        await PriceFeedscontract.connect(owner).setDecimals([NBUContract.address, NBU2Contract.address])
        await PriceFeedscontract.connect(owner).setPriceFeed([NBUContract.address, NBU2Contract.address], [NimbusPriceFeed1Contract.address, NimbusPriceFeed2Contract.address])
        await ConverterContract.connect(owner).updatePriceFeed(PriceFeedscontract.address)
        await ConverterContract.connect(owner).updateUsePriceFeeds(true)
        expect(await ConverterContract.usePriceFeeds()).to.equal(true);
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000000")
        await ConverterContract.connect(other).convertWithPermit("1000000000000000000000", curTimestamp + 100, result.v, result.r, result.s)
    });
    it("Test convert ", async function () {
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000000")
        await NBUContract.connect(other).approve(ConverterContract.address, "1000000000000000000000")
        await ConverterContract.connect(other).convert("1000000000000000000000")
        expect(await ConverterContract.receiveTokenSupply()).to.equal("0");
    });
    it("Test Pause ", async function () {
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000000")
        await NBUContract.connect(other).approve(ConverterContract.address, "1000000000000000000000")
        await ConverterContract.connect(owner).setPaused(true)
        await expect(ConverterContract.connect(other).convert("1000000000000000000000")).to.be.revertedWith('Pausable: paused');
        await ConverterContract.connect(owner).setPaused(false)
        await ConverterContract.connect(other).convert("1000000000000000000000")
        expect(await ConverterContract.receiveTokenSupply()).to.equal("0");
    });

    it("Test PriceFeeds using ", async function () {

        await NimbusPriceFeed1Contract.connect(owner).setLatestAnswer("1000000000000000000")
        await NimbusPriceFeed2Contract.connect(owner).setLatestAnswer("4000000000000000000")
        await PriceFeedscontract.connect(owner).setDecimals([NBUContract.address, NBU2Contract.address])
        await PriceFeedscontract.connect(owner).setPriceFeed([NBUContract.address, NBU2Contract.address], [NimbusPriceFeed1Contract.address, NimbusPriceFeed2Contract.address])
        await ConverterContract.connect(owner).updatePriceFeed(PriceFeedscontract.address)
        await ConverterContract.connect(owner).updateUsePriceFeeds(true)
        expect(await ConverterContract.usePriceFeeds()).to.equal(true);
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000")
        await NBUContract.connect(other).approve(ConverterContract.address, "1000000000000000000")
        await ConverterContract.connect(other).convert("1000000000000000000")
        const LatestAnswer1 = await NimbusPriceFeed1Contract.latestAnswer();
        const LatestAnswer2 = await NimbusPriceFeed2Contract.latestAnswer();
        const getEquivalentAmount = await ConverterContract.getEquivalentAmount("1000000000000000000")
        const Div = LatestAnswer2.div(LatestAnswer1);
        const DIv2 = (LatestAnswer1).mul("1000000000000000000").div(LatestAnswer2)
        expect(DIv2.toString()).to.equals(getEquivalentAmount.toString());
        console.log((123), LatestAnswer2.toString(), LatestAnswer1.toString(), LatestAnswer2.div(LatestAnswer1).toString(), getEquivalentAmount.toString(), Div.toString(), DIv2.toString())
    });
    it("Test Rescue ERC20 Tokens  ", async function () {
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000000")
        await ConverterContract.rescueERC20(other.address, NBU2Contract.address, "1000000000000000000000")
        expect(await NBU2Contract.balanceOf(ConverterContract.address)).to.equal("0");
        expect(await NBU2Contract.balanceOf(other.address)).to.equal("1000000000000000000000");
    });
    it("setManualRate", async function () {
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "1000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000")
        await NBUContract.connect(other).approve(ConverterContract.address, "1000000000000000000")
        await ConverterContract.connect(other).convert("1000000000000000000")
        expect(await ConverterContract.receiveTokenSupply()).to.equal("0");

        await ConverterContract.connect(owner).setManualRate("2000000000000000000")
        
        await NBU2Contract.connect(owner).transfer(ConverterContract.address, "4000000000000000000")
        await NBUContract.connect(owner).transfer(other.address, "1000000000000000000")
        await NBUContract.connect(other).approve(ConverterContract.address, "1000000000000000000")
        await ConverterContract.connect(other).convert("1000000000000000000")
        expect(await ConverterContract.receiveTokenSupply()).to.equal("2000000000000000000");
    });

});
