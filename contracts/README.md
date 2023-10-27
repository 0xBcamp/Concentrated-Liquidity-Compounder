## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

-   **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
-   **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
-   **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
-   **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```

### Miguel instructions

forge compile --via-ir

forge test --via-ir -vvv

cd src

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts/src$ forge create ClExecutor --via-ir

created local weth. maybe should just be doing this on a testnet:

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ forge create --rpc-url http://localhost:8545 --private-key 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97 src/Weth9.sol:WETH9 --via-ir
[⠰] Compiling...
[⠔] Compiling 1 files with 0.4.26
[⠒] Solc 0.4.26 finished in 26.91ms
Compiler run successful!

Deployer: 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
Deployed to: 0x95bD8D42f30351685e96C62EDdc0d0613bf9a87A
Transaction hash: 0x729b153576c2fe89507b8964b185a91393542f38d51747b29290b3958ecf7d2f

changed test command

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ forge test --via-ir -vvv --fork-url http://localhost:8545 --chain-id 31337

it works but cant change active forks? so useless?

maybe we have to fork anvil with infura and mainnet?
https://mainnet.infura.io/v3/dc186b7c15b5472e9579b8c7b063eeda


scientific_peach@pop-os:~$ anvil --fork-url https://arb-mainnet.g.alchemy.com/v2/ffO12FW4K0YUmN2B55pasKLzJX3a0j-q --auto-impersonate

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast send $USDC --unlocked --from $LUCKY_USER "transfer(address,uint256)(bool)" $ALICE 15190255


scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast send 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2 --from $ALICE --value 555533333 "deposit()" --unlocked

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast send $DAI --unlocked --from $DAI_USER "transfer(address,uint256)(bool)" $ALICE 25925902525

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $IDK "swapTokens(address,address,uint256)(uint256)" $USDC $DAI 5 --trace --verbose --private-key $PRIVATE_KEY --from $ALICE

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $USDC "approve(address,uint256)(bool)" $ALICE 5555555555555 --from $ALICE

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $USDC "approve(address,uint256)(bool)" $ALICE 5555555555555 --from $ALICE
true
scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $DAI "approve(address,uint256)(bool)" $ALICE 5555555555555 --from $ALICE
true
scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $DAI "approve(address,uint256)(bool)" $IDK 5555555555555 --from $ALICE
true
scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $USDC "approve(address,uint256)(bool)" $IDK 5555555555555 --from $ALICE
true

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ cast call $DAI "approve(address,uint256)(bool)" $ZEROACC 5555555555555 --from $ZEROACC --trace
Traces:
  [24457] 0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1::approve(0x0000000000000000000000000000000000000000, 5555555555555 [5.555e12]) 
    ├─ emit Approval(param0: 0x0000000000000000000000000000000000000000, param1: 0x0000000000000000000000000000000000000000, param2: 5555555555555 [5.555e12])
    └─ ← 0x0000000000000000000000000000000000000000000000000000000000000001


Transaction successfully executed.
Gas used: 45849


forge script script/Counter.s.sol:MyScript --fork-url http://localhost:8545 --broadcast --via-ir -vvv

@_@ G_G