# Equipment for MIP21: Off-chain Asset Backed Lending in MakerDAO

## Components

- `RwaLiquidationOracle`: acts as a liquidation beacon for an off-chain enforcer.
- `RwaUrn`: facilitates borrowing of DAI, delivering to a designated account.
- `RwaUrn2`: variation of `RwaUrn` that allows authorized parties to flush out any outstanding DAI at any moment.
- `RwaOutputConduit`: disburses DAI.
- `RwaOutputConduit2`: variation of `RwaOutputConduit` with an whitelist to control permissions to disburse DAI.
- `RwaOutputConduit3`: variation of `RwaOutputConduit` for swapping DAI to GEM through a PSM.
- `RwaInputConduit`: repays DAI.
- `RwaInputConduit2`: variation of `RwaInputConduit` with an whitelist to control permissions to repay DAI.
- `RwaInputConduit3`: variation of `RwaInputConduit` for swapping GEM to DAI through a PSM. Push is permissioned to avoid griefing by pushing to PSM when the PSM is empty or high slippage is expected. With this approach, the borrower decides when to push and at which rate according to PSM liquidity.
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
