const hre = require('hardhat')

const REWARD_TOKEN = process.env.REWARD_TOKEN || '';
const STAKING_TOKEN = process.env.STAKING_TOKEN || '';
const REWARD_RATE = process.env.REWARD_RATE || '';
const LOCK_DURATION = process.env.LOCK_DURATION || '';
const SWAP_ROUTER = process.env.SWAP_ROUTER || '';
const SWAP_TOKEN = process.env.SWAP_ROUTER || '';
const SWAP_TOKEN_AMOUNT = process.env.SWAP_TOKEN_AMOUNT || '';

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
    const Contract = await hre.ethers.getContractFactory('LockStakingRewardMinAmountFixedAPY');
    const contract = await Contract.deployed([
        REWARD_TOKEN,
        STAKING_TOKEN,
        hre.ethers.BigNumber.from(REWARD_RATE),
        hre.ethers.BigNumber.from(LOCK_DURATION),
        SWAP_ROUTER,
        SWAP_TOKEN,
        hre.ethers.BigNumber.from(SWAP_TOKEN_AMOUNT),
    ]);

    console.log(`LockStakingRewardMinAmountFixedAPY deployed: ${contract.address} by ${deployer.address}`);

    console.log('Verifying contracts...')
    await ver(Contract.address, [
        REWARD_TOKEN,
        STAKING_TOKEN,
        hre.ethers.BigNumber.from(REWARD_RATE),
        hre.ethers.BigNumber.from(LOCK_DURATION),
        SWAP_ROUTER,
        SWAP_TOKEN,
        hre.ethers.BigNumber.from(SWAP_TOKEN_AMOUNT),
    ]);
}

main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error)
        process.exit(1)
    })
