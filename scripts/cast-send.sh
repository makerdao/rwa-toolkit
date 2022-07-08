#!/bin/bash
set -eo pipefail

source "${BASH_SOURCE%/*}/_common.sh"

send() {
  normalize-env-vars

  local PASSWORD="$(extract-password)"
  local PASSWORD_OPT=()
  if [ -n "$PASSWORD" ]; then
    PASSWORD_OPT=(--password "$PASSWORD")
  fi

  local RESPONSE
  # Log the command being issued, making sure not to expose the password
  log "cast send --json --gas $FOUNDRY_GAS_LIMIT --keystore="$FOUNDRY_ETH_KEYSTORE_FILE" $(sed 's/ .*$/ [REDACTED]/' <<<"${PASSWORD_OPT[@]}")" $(printf ' %q' "$@")
  # Currently `cast send` sends the logs to stdout instead of stderr.
  # This makes it hard to compose its output with other commands, so here we are:
  # 1. Duplicating stdout to stderr through `tee`
  # 2. Extracting only the hash of the transaction to stdout
  RESPONSE=$(cast send --json --gas $FOUNDRY_GAS_LIMIT --keystore="$FOUNDRY_ETH_KEYSTORE_FILE" "${PASSWORD_OPT[@]}" "$@" | tee >(cat 1>&2))

  jq -Rr 'fromjson? | .transactionHash' <<<"$RESPONSE"
}

usage() {
  cat <<MSG
cast-send.sh <address> <method_signature> [ ...args ]

Examples:

    # Method does not take any arguments
    cast-send.sh 0xdead...0000 "someFunc()"

    # Method takes (uint, address) arguments
    cast-send.sh 0xdead...0000 'anotherFunc(uint, address)' --args 1 0x0000000000000000000000000000000000000000
MSG
}

if [ "$0" = "$BASH_SOURCE" ]; then
  [ "$1" = "-h" -o "$1" = "--help" ] && {
    echo -e "\n$(usage)\n"
    exit 0
  }

  send "$@"
fi
