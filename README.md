## Installation and Testing

### Installation

It is **strongly recommended** to use a virtual environment with this project.

The project has been tested with Ubuntu 18.04, 20.04 and with Python3.8* and Python 3.9*

```bash
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

In future sessions, activate the virtual environment with:

```bash
source venv/bin/activate
```

To learn more about `venv`, see the official [Python documentation](https://docs.python.org/3/library/venv.html).

We also use hardhat for our testing node, which requires installation

```bash
npm install
```

[Brownie installation guide](https://eth-brownie.readthedocs.io/en/stable/install.html)

#### Other dependencies

Brownie:

The following API Keys need to be added to the system environmental variables
 - Alchemy provider: $WEB3_ALCHEMY_PROJECT_ID
 - Etherscan API token: $ETHERSCAN_TOKEN

Brownie networks:

Mainnet networks
the following networks need to be added to the brownie network config file (~./brownie/network-config.yaml)

```bash
# Mainnet network
- chainid: 1
  explorer: https://api.etherscan.io/api
  host: https://eth-mainnet.alchemyapi.io/v2/$WEB3_ALCHEMY_PROJECT_ID
  id: Mainnet
  multicall2: '0x5BA1e12693Dc8F9c48aAD8770482f4739bEeD696'
  name: Mainnet
  provider: alchemy

# for tests
- cmd: npx hardhat node
  cmd_settings:
    fork: Mainnet
    port: 8545
  host: http://localhost
  id: hardhat-fork
  name: Hardhat (Mainnet Fork)
  timeout: 120
```

### Running the Tests
Unit tests can run on a regular hardhat node whereas integration tests require a mainnet fork due to the external dependencies.

To run tests:
```bash
brownie test --network hardhat-fork
```
