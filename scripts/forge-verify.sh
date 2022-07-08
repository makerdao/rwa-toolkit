#!/bin/bash
set -eo pipefail

source "${BASH_SOURCE%/*}/_common.sh"

function verify() {
  normalize-env-vars
  check-required-etherscan-api-key

  local CHAIN="$(cast chain)"
  [ CHAIN = 'ethlive' ] && CHAIN='mainnet'

  local RESPONSE=
  # Log the command being issued
  log "forge verify-contract --chain $CHAIN" $(printf ' %q' "$@")
  # Currently `forge verify-contract` sends the logs to stdout instead of stderr.
  # This makes it hard to compose its output with other commands, so here we are:
  # 1. Duplicating stdout to stderr through `tee`
  # 2. Extracting only the URL of the verified contract to stdout
  RESPONSE=$(forge verify-contract --chain "$CHAIN" --watch "$@" | tee >(cat 1>&2))

  # Display only the URL
  if grep -E -i '^\s*Response:.*OK.*$' <<<"$RESPONSE" >/dev/null; then
    grep -E -i '^\s*URL:' <<<"$RESPONSE" | head -1 | awk -F': ' '{ print $2 }' | sed -r 's/(^\s*|\s*$)//'
  fi
}

function check-required-etherscan-api-key() {
  [ -n "$FOUNDRY_ETHERSCAN_API_KEY" ] || die "$(err-msg-etherscan-api-key)"
}

function usage() {
  cat <<MSG
forge-verify.sh <address> <file>:<contract> [ --constructor-args <abi_encoded_args> ]

Examples:

    # Constructor does not take any arguments
    forge-verify.sh 0xdead...0000 src/MyContract.sol:MyContract

    # Constructor takes (uint, address) arguments. Don't forget to abi-encode them!
    forge-verify.sh 0xdead...0000 src/MyContract.sol:MyContract \\
        --constructor-args="\$(cast abi-encode 'constructor(uint, address)' 1 0x0000000000000000000000000000000000000000)"
MSG
}

# Executes the function if it's been called as a script.
# This will evaluate to false if this script is sourced by other script.
if [ "$0" = "$BASH_SOURCE" ]; then
  [ "$1" = "-h" -o "$1" = "--help" ] && {
    echo -e "\n$(usage)\n"
    exit 0
  }

  verify "$@"
fi
