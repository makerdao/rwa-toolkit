# include .env file and export its env vars
# (-include to ignore error if it does not exist)-include .env
-include .env

# install solc version
# example to install other versions: `make solc 0_8_14`
SOLC_VERSION := 0_8_14

clean:; forge clean
update:; forge update
# Build & test
build:; forge build
test:; forge test # --ffi # enable if you need the `ffi` cheat code on HEVM

flatten:; forge flatten --source-file ${file}

 # Constructor args must come last
deploy:; @scripts/forge-deploy.sh ${args}
 # Differently than deploy, this requires abi-encoded constructor arguments
verify:; @scripts/forge-verify.sh ${args}

send:; @scripts/cast-send.sh ${args}

nodejs-deps:; yarn install
lint:; yarn run lint
