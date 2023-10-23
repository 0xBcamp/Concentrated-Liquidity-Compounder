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
[⠰] Compiling...
No files changed, compilation skipped
Error: 
error sending request for url (http://localhost:8545/): error trying to connect: tcp connect error: Connection refused (os error 111)

Context:
- Error #0: error trying to connect: tcp connect error: Connection refused (os error 111)
- Error #1: tcp connect error: Connection refused (os error 111)
- Error #2: Connection refused (os error 111)

    address ROUTER_V2 = 0xAA23611badAFB62D37E7295A682D21960ac85A90;

    these are all the contracts you need to compile :        narrow = new Narrow();

        mid = new Mid();
        wide = new Wide();
        ramsesV2Pool = new RamsesV2Pool();
        gaugeV2 = new GaugeV2();
        votingEscrow = new VotingEscrow();
        clExecutor = new ClExecutor(

private key:
        
0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80