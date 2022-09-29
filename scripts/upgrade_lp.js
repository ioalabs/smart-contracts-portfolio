const hre = require('hardhat')

const SMARTLP_BUSD_ADDRESS = process.env.SMARTLP_BUSD_ADDRESS || '';

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms))
}

const ver = async function verifyContracts(address, arguments) {
  await hre
    .run('verify:verify', {
      address: address,
      constructorArguments: arguments,
    })
    .catch((err) => console.log(err))
}

async function main() {
  ;[deployer] = await hre.ethers.getSigners()

  smartLP = await hre.ethers.getContractFactory('contracts/NFT/SmartLP_BUSD.sol:SmartLP')
  
  smartLPNew = await upgrades.upgradeProxy(SMARTLP_BUSD_ADDRESS, smartLP)
  smartLPNew = await smartLPNew.deployed()
  console.log('SmartLP BUSD upgraded at:', smartLPNew.address)

  console.log('Verifying contracts...')
  const smartLPNewImplAddress = await upgrades.erc1967.getImplementationAddress(smartLPNew.address);
  await ver(smartLPNewImplAddress, [])
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
