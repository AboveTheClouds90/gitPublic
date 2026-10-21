#!/usr/bin/env bash
# Run on the Proxmox host (not in the VM), as root: ./check-ram.sh
# Shows which DIMM slots are filled and how fast they run.
#
# The EPYC 9654 has 12 memory channels. Full bandwidth (460.8 GB/s) needs
# 12 DIMMs, one per channel, at 4800 MT/s. With 8 DIMMs you get ~307 GB/s.
# Two DIMMs per channel usually drops the speed below 4800.

# 1. Every slot: where it is, its size, and its rated and actual speed
dmidecode -t memory | grep -E '^\s+(Locator|Size|Speed|Configured Memory Speed):'
echo

# 2. How many slots are filled? Expect 12
echo "Filled slots: $(dmidecode -t memory | grep -cE '^\s+Size: [0-9]+')"
