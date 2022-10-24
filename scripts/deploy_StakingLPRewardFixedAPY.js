const hre = require('hardhat')

const REWARD_TOKEN = process.env.SLFA_REWARD_TOKEN || '';
const REWARD_PAYMENT_TOKEN = process.env.SLFA_REWARD_PAYMENT_TOKEN || '';
const STAKING_LP_TOKEN = process.env.SLFA_STAKING_LP_TOKEN || '';
const LP_PAIR_TOKEN_A = process.env.SLFA_LP_PAIR_TOKEN_A || '';
const LP_PAIR_TOKEN_B = process.env.SLFA_LP_PAIR_TOKEN_B || '';
const SWAP_ROUTER = process.env.SLFA_SWAP_ROUTER || '';
const REWARD_RATE = process.env.SLFA_REWARD_RATE || '';
const STAKING_PRICE_FEED = process.env.STAKING_PRICE_FEED || '';

const ver = async function verifyContracts(address, arguments) {
    await hre
        .run('verify:verify', {
            address: address,
            constructorArguments: arguments,
        })
        .catch((err) => console.log(err))
}

async function main() {
    const [deployer] = await hre.ethers.getSigners();
    const Contract = await hre.ethers.getContractFactory('StakingLPRewardFixedAPY');
    const arguments = [
        REWARD_TOKEN,
        REWARD_PAYMENT_TOKEN,
        STAKING_LP_TOKEN,
        LP_PAIR_TOKEN_A,
        LP_PAIR_TOKEN_B,
        SWAP_ROUTER,
        hre.ethers.BigNumber.from(REWARD_RATE),
    ]
    const contract = await Contract.deployed(arguments);

    console.log(`StakingLPRewardFixedAPY deployed: ${contract.address} by ${deployer.address}`);

    if (STAKING_PRICE_FEED.length === 0) console.log('Skipping price feed setup');
    else {
        console.log('Attaching price feeds')
        await contract.updatePriceFeed(STAKING_PRICE_FEED).then(res=>console.log('Price feed address set'));
        await contract.toggleUsePriceFeeds().then(res=>console.log('Price feed enabled'));
    }

    console.log('Verifying contracts...')
    await ver(Contract.address, arguments);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
