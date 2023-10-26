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
Warning: Invoking events without "emit" prefix is deprecated.
        Deposit(msg.sender, msg.value);
        ^----------------------------^
Warning: Invoking events without "emit" prefix is deprecated.
        Withdrawal(msg.sender, wad);
        ^-------------------------^
Warning: Using contract member "balance" inherited from the address type is deprecated. Convert the contract to "address" type to access the member, for example use "address(contract).balance" instead.
        return this.balance;
               ^----------^
Warning: Invoking events without "emit" prefix is deprecated.
        Approval(msg.sender, guy, wad);
        ^----------------------------^
Warning: Invoking events without "emit" prefix is deprecated.
        Transfer(src, dst, wad);
        ^---------------------^
Deployer: 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f
Deployed to: 0x95bD8D42f30351685e96C62EDdc0d0613bf9a87A
Transaction hash: 0x729b153576c2fe89507b8964b185a91393542f38d51747b29290b3958ecf7d2f

changed test command

scientific_peach@pop-os:~/fake/work/Concentrated-Liquidity-Compounder/contracts$ forge test --via-ir -vvv --fork-url http://localhost:8545 --chain-id 31337

it works but cant change active forks? so useless?
