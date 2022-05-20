require('@nomiclabs/hardhat-waffle')
require('dotenv').config()
require('@nomiclabs/hardhat-etherscan')
require('solidity-coverage')

// const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const BSC_PRIVATE_KEY = process.env.BSC_PRIVATE_KEY || ''
const BSCSCANAPIKEY_API_KEY = process.env.BSCSCANAPIKEY_API_KEY || ''

task('accounts', 'Prints the list of accounts', async () => {
  const accounts = await ethers.getSigners()

  for (const account of accounts) {
    console.log(account.address)
  }
})

module.exports = {
  solidity: {
    compilers: [
      {
        version: '0.8.0',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
    ],
  },
  defaultNetwork: 'hardhat',
  networks: {
    hardhat: {},
    // testnet: {
    //   url: 'https://data-seed-prebsc-1-s1.binance.org:8545',
    //   chainId: 97,
    //   gasPrice: 10000000000,
    //   gas: 2100000,
    //   accounts: [BSC_PRIVATE_KEY],
    // },
    // mainnet: {
    //   url: 'https://bsc-dataseed.binance.org/',
    //   chainId: 56,
    //   gasPrice: 20000000000,
    //   accounts: [BSC_PRIVATE_KEY],
    // },
  },
  etherscan: {
    apiKey: {
      // binance smart chain
      bsc: BSCSCANAPIKEY_API_KEY,
      bscTestnet: BSCSCANAPIKEY_API_KEY,
    },
  },
  dependencyCompiler: {
    paths: [
      '@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol',
    ],
  },
}