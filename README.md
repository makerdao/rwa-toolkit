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

**⚠️ ATTENTION:** Spells are being moved to the [`ces-spells-goerli` repo](https://github.com/clio-finance/ces-spells-goerli/tree/master/template/rwa-onboarding), once the migration is completed, these files are going to be removed.

The following can be found in [`src/spells/RwaSpell.sol`](./src/spells/RwaSpell.sol):
- `RwaSpell`: which deploys and configures the RWA collateral in MakerDAO in accordance with MIP21 

The following can be found in [`src/spells/RwaSpell.t.sol`](./src/spells/RwaSpell.t.sol):

- `TellSpell`: which allows MakerDAO governance to initiate liquidation proceedings.
- `CureSpell`: which allows MakerDAO governance to dismiss liquidation proceedings.
- `CullSpell`: which allows MakerDAO governance to write off a loan which was in liquidation.

## Deploy

### kovan
```
make deploy-kovan
```

### goerli
```
make deploy-goerli
```

### mainnet
```
make deploy-mainnet
```
