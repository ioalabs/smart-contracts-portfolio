require('@nomiclabs/hardhat-waffle')
require('@openzeppelin/hardhat-upgrades');
require('dotenv').config()
require('@nomiclabs/hardhat-etherscan')
require('hardhat-coverage')
require('solidity-docgen')

// const INFURA_API_KEY = process.env.INFURA_API_KEY || "";
const BSC_PRIVATE_KEY = process.env.BSC_PRIVATE_KEY || ''
const BSCSCANAPIKEY_API_KEY = process.env.BSCSCANAPIKEY_API_KEY || ''
const BSC_TESTNET = process.env.BSC_TESTNET || ''
const BSC_MAINNET = process.env.BSC_MAINNET || ''

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
      {
        version: '0.8.7',
        settings: {
          optimizer: {
            enabled: true,
            runs: 200,
          },
        },
      },
      {
        version: '0.8.15',
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
    testnet: {
      url: BSC_TESTNET,
      chainId: 97,
      gasPrice: 16000000000,
      gas: 2100000,
      accounts: [BSC_PRIVATE_KEY],
    },
    mainnet: {
      url: BSC_MAINNET,
      chainId: 56,
      gasPrice: 10000000000,
      accounts: [BSC_PRIVATE_KEY],
    },
  },
  etherscan: {
    apiKey: {
      // binance smart chain
      bsc: BSCSCANAPIKEY_API_KEY,
      bscTestnet: BSCSCANAPIKEY_API_KEY,
    },
  },
  docgen: {
    pages: 'files',
    exclude: ['Stakings', 'Test']
  }
}
