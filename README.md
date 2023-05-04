# Equipment for Off-chain Asset Backed Lending in MakerDAO

## Components

- `RwaLiquidationOracle`: acts as a liquidation beacon for an off-chain enforcer.
- `RwaUrn`: facilitates borrowing of DAI, delivering to a designated account.
- `RwaUrn2`: variation of `RwaUrn` that allows authorized parties to flush out any outstanding DAI at any moment.
- `RwaOutputConduit`: disburses DAI.
- `RwaOutputConduit2`: variation of `RwaOutputConduit` with a whitelist to control permissions to disburse DAI.
- `RwaSwapOutputConduit`: variation of `RwaOutputConduit` for swapping DAI to GEM through a PSM.
- `RwaInputConduit`: repays DAI.
- `RwaInputConduit2`: variation of `RwaInputConduit` with a whitelist to control permissions to repay DAI.
- `RwaSwapInputConduit`: variation of `RwaInputConduit` for swapping GEM to DAI through a PSM.
- `RwaSwapInputConduit2`: variation of `RwaSwapInputConduit` with a permissionless `push`.
- `RwaToken`: represents the RWA collateral in the system.
- `RwaTokenFactory`: factory of `RwaToken`s.
- `RwaJar`: facilitates paying stability fess directly into the DSS surplus buffer.
- `RwaCageSettlement`: RWA settlement facility to allow DAI holders to redeem RWA tokens if MakerDAO Governance ever issues an Emergency Shutdown.
- `RwaCageSettlementFactory`: factory of `RwaCageSettlement`.

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
