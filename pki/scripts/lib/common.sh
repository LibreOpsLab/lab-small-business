#!/usr/bin/env bash
# Shared helpers for pki/scripts/*.sh — sourced, not executed directly.

set -euo pipefail

SCRIPT_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKI_ROOT="$(cd "${SCRIPT_LIB_DIR}/../.." && pwd)"

ROOT_CA_DIR="${PKI_ROOT}/root-ca"
INTERMEDIATE_CA_DIR="${PKI_ROOT}/intermediate-ca"
ISSUED_DIR="${PKI_ROOT}/issued"
OPENSSL_CFG_DIR="${PKI_ROOT}/openssl"

ROOT_CA_CNF="${OPENSSL_CFG_DIR}/root-ca.cnf"
INTERMEDIATE_CA_CNF="${OPENSSL_CFG_DIR}/intermediate-ca.cnf"

LAB_DOMAIN="lab.local"
LAB_REALM="LAB.LOCAL"

log()   { printf '\033[1;34m[pki]\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m[pki][warn]\033[0m %s\n' "$*" >&2; }
error() { printf '\033[1;31m[pki][error]\033[0m %s\n' "$*" >&2; }
die()   { error "$*"; exit 1; }

require_openssl3() {
  local ver
  ver="$(openssl version | awk '{print $2}')"
  case "${ver}" in
    3.*) ;;
    *) die "OpenSSL 3.x required, found ${ver}. Install via 'sudo apt install openssl'." ;;
  esac
}

init_ca_tree() {
  # $1 = CA directory (root-ca or intermediate-ca)
  local dir="$1"
  mkdir -p "${dir}"/{certs,crl,csr,private,db}
  chmod 700 "${dir}/private"
  [[ -f "${dir}/db/index.txt" ]] || touch "${dir}/db/index.txt"
  [[ -f "${dir}/db/index.txt.attr" ]] || echo "unique_subject = no" > "${dir}/db/index.txt.attr"
  [[ -f "${dir}/db/serial" ]] || echo 1000 > "${dir}/db/serial"
  [[ -f "${dir}/db/crlnumber" ]] || echo 1000 > "${dir}/db/crlnumber"
}

require_openssl3
