#!/bin/bash
kill -9 $(lsof -t -i tcp:9999)
npx hardhat node --fork https://eth-mainnet.alchemyapi.io/v2/$ETH_RPC_URL --fork-block-number $ETH_BLOCK_NUMBER --port 9999 --hostname 0.0.0.0 &
