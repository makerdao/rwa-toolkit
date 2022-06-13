# Equipment for MIP21: Off-chain Asset Backed Lending in MakerDAO

## Components

- `RwaLiquidationOracle`: acts as a liquidation beacon for an off-chain enforcer.
- `RwaUrn`: facilitates borrowing of DAI, delivering to a designated account.
- `RwaUrn2`: variation of `RwaUrn` that allows authorized parties to flush out any outstanding DAI at any moment. 
- `RwaOutputConduit`: disburses DAI.
- `RwaOutputConduit2`: variation of `RwaOutputConduit` with an whitelist to control permissions to disburse DAI.
- `RwaInputConduit`: repays DAI.
- `RwaInputConduit2`: variation of `RwaInputConduit` with an whitelist to control permissions to repay DAI.
- `RwaToken`: represents the RWA collateral in the system.
- `RwaTokenFactory`: factory of `RwaToken`s.
- `RwaJar`: facilitates paying stability fess directly into the DSS surplus buffer.

## Spells

**⚠️ ATTENTION:** Spells were moved to [`ces-spells-goerli`](https://github.com/clio-finance/ces-spells-goerli/tree/master/template/rwa-onboarding).

## Deploy

### Kovan \[deprecated\]
```
make deploy-kovan
```

### Goerli
```
make deploy-goerli
```

### Mainnet
```
make deploy-mainnet
```