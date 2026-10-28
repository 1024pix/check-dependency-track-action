#!/bin/bash
set -euo pipefail

CDX_CLI_VERSION=0.33.1
CDX_CLI_SHA256=bfc8b2538da86fe239bc53658bbb63c1c8c510a293c1e6891aa5bea5d3c58746

[ "$RUNNER_OS" = "Linux" ] && [ "$RUNNER_ARCH" = "X64" ] || { echo "[-] cyclonedx-cli: only linux-x64 supported"; exit 1; }

# install cycloneDX-CLI
bin="$RUNNER_TEMP/cyclonedx-cli"
curl -fsSL -o "$bin" \
    "https://github.com/CycloneDX/cyclonedx-cli/releases/download/v${CDX_CLI_VERSION}/cyclonedx-linux-x64"

echo "${CDX_CLI_SHA256}  $bin" | sha256sum -c - 
chmod +x "$bin"

# Cyclonedx CLI validation
echo "[*] Cyclonedx CLI validation"

# Validates SBOM format
"$bin" validate --input-file "$SBOM_FILENAME" --input-format json --input-version v1_5 --fail-on-errors || { echo "[-] CycloneDX CLI validation failed. Stopping the action!"; exit 1; }