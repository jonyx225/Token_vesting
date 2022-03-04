// require("@nomiclabs/hardhat-truffle5");
require("@nomiclabs/hardhat-waffle");
// require("@nomiclabs/hardhat-ganache");

const ALCHEMY_API_KEY = "REPLACE_ME";
const ROPSTEN_PRIVATE_KEY = "REPLACE_ME";

module.exports = {
  solidity: "0.6.12",
  networks: {
    ropsten: {
      url: `https://eth-ropsten.alchemyapi.io/v2/${ALCHEMY_API_KEY}`,
      accounts: [`0x${ROPSTEN_PRIVATE_KEY}`]
    }
  }
};

