const networkConfig: any = {
    default: {
        name: "arbitrum",
    },
    42161: {
        name: "arbitrum",
        usdc: "0xaf88d065e77c8cC2239327C5EDb3A432268e5831",
        weth: "0x82aF49447D8a07e3bd95BD0d56f35241523fBab1",
        link: "0xf97f4df75117a78c1A5a0DBb814Af92458539FB4",
        dai: "0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1",
        RouterV2: "0xAA23611badAFB62D37E7295A682D21960ac85A90",
        NonFungiblePositionManager: "0xAA277CB7914b7e5514946Da92cb9De332Ce610EF",
        RamsesV2Factory: "0xAA2cd7477c451E703f3B9Ba5663334914763edF8",
        RAMToken: "0xAAA6C1E32C55A7Bfa8066A6FAE9b42650F262418",
        xRAMToken: "0xAAA1eE8DC1864AE49185C368e8c64Dd780a50Fb7",
        ethUsdPriceFeed: "??",
        maticUsdPriceFeed: "??",
        automationUpdateInterval: "30",
        fee: "100000000000000",
        fundAmount: "100000000000000",
        oracle: "??",
        jobId: "??",
        subscriptionId: "??",
        vrfCoordinator: "??",
        keyHash: "??"
    },
    1: {
        name: "mainnet",
        fee: "100000000000000000",
        keyHash: "0xd89b2bf150e3b9e13446986e571fb9cab24b13cea0a43ea20a6049a85cc807cc",
        jobId: "29fa9aa13bf1468788b7cc4a500a45b8",
        fundAmount: "1000000000000000000",
        automationUpdateInterval: "30",
        ethUsdPriceFeed: "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
        weth: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
        usdc: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48",
        dai: "0x6B175474E89094C44Da98b954EedeAC495271d0F",
        link: "0x514910771AF9Ca656af840dff83E8264EcF986CA",
        sushi: "0x6B3595068778DD592e39A122f4f5a5cF09C90fE2",
        uniswap_router_v2: "0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D",
        sushiswap_router_v2: "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F",
        sushiswap_factory_v2: "0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac",
        master_chef_v2: "0xef0881ec094552b2e128cf945ef17a6752b4ec5d"
    },
}

module.exports = { networkConfig };