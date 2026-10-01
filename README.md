# KOANTUM Contracts

Official public smart-contract and verification repository for **KOANTUM ($KOANT)** on Base.

> **KOANTUM** is the project and community. **KOANT** is the token.

## Network

- Network: Base Mainnet
- Chain ID: `8453`
- Token standard: ERC-20
- Decimals: `18`
- Fixed supply: `404,690,000,000 KOANT`
- Solidity: `0.8.37`

## Official KOANT Contract

`0x9DC38f75a3dC03726F5b0a8C401954FCFAA7853c`

BaseScan:
https://basescan.org/token/0x9DC38f75a3dC03726F5b0a8C401954FCFAA7853c

The contract source is verified on BaseScan.

## Public Project Addresses

### KOANT Operations

`0xf1EDE320bfB26659De57Ab713Db108E4c0C69Dc4`

Operational address used for KOANT contract actions and project transaction execution.

### Treasury / TeamVault Beneficiary

`0x5002fd19637109973AaFB5E72603217319C5338c`

Official project Treasury and beneficiary of the TeamVault after unlock.

### Founder Wallet 1

`0xee8c0F95E0750846265940BE659334FBBdEaEaC5`

Initial allocation: `6,070,350,000 KOANT` — `1.5%`

### Founder Wallet 2

`0xD8e706Bcc722800895481811dBfB77397cD690ab`

Initial allocation: `6,070,350,000 KOANT` — `1.5%`

### TeamVault

`0x7Ee8A6D61affF77261b152Dd0fe4AB1eAAB8450d`

- Allocation: `15,782,910,000 KOANT` (`3.9%`)
- Unlock: `2027-11-11 00:00:00 UTC`
- Beneficiary: Treasury

### LP Locker

`0x5d9152a4F5B134cdd666253D443d259cdecA125c`

- Asset: KOANT/WETH LP tokens
- Unlock: `2069-09-06 00:00:00 UTC`


## Supply Allocation

| Allocation | Share | KOANT |
|---|---:|---:|
| Genesis Liquidity | 86.2% | 348,842,780,000 |
| Community Reserve | 6.9% | 27,923,610,000 |
| TeamVault | 3.9% | 15,782,910,000 |
| Founder Wallet 1 | 1.5% | 6,070,350,000 |
| Founder Wallet 2 | 1.5% | 6,070,350,000 |
| **Total** | **100%** | **404,690,000,000** |

## Contract Architecture

### KOANT.sol

Main ERC-20 token contract.

Public mechanics include:

- Fixed supply
- No public post-deployment mint function
- No blacklist or freeze mechanism
- No proxy or upgrade path
- One-time Pair initialization
- One-way trading enablement
- Fixed maximum buy and maximum wallet limits
- Finite launch-state tax transitions
- Permanent final state of 0% buy tax and 0% sell tax

### TeamVault.sol

Time-lock contract for the 3.9% team allocation.

The locked KOANT balance cannot be released before the configured unlock timestamp. After the unlock condition is reached, the balance is released to the configured Treasury beneficiary.

### LPLocker.sol

Long-term LP-token locking contract.

KOANT/WETH LP tokens remain locked until the configured unlock timestamp.

## Launch-State Rules

| State | Tax |
|---|---:|
| Buy #1 through #69 | 1% buy tax |
| Buy #70 onward | 0% buy tax |
| Sell while `buyCount < 404` | 50% sell tax |
| After completion of Buy #404 | 0% sell tax permanently |
| Wallet-to-wallet transfer | 0% |

Maximum buy: `6,976,855,600 KOANT`

Maximum wallet: `6,976,855,600 KOANT`

## Test Suite

The public test suite covers:

- Supply and allocation
- Pair initialization and trading state
- Launch-state tax transitions
- Maximum buy and maximum wallet limits
- SwapBack behavior
- TeamVault behavior
- LP Locker behavior
- Fuzz testing
- Adversarial cases
- Base fork integration

Current verified repository checkpoint:

**45 tests passed · 0 failed · 0 skipped**

## Build and Test

Clone with submodules:

```bash
git clone --recurse-submodules https://github.com/koantumco/KOANTUM-Contracts.git
cd KOANTUM-Contracts
```

Build:

```bash
forge build
```

Run the complete test suite:

```bash
forge test
```

Formatting check:

```bash
forge fmt --check
```

## Dependencies

Dependencies are pinned through Git submodules:

- `forge-std` — `bf647bd6046f2f7da30d0c2bf435e5c76a780c1b`
- `OpenZeppelin Contracts` — `5fd1781b1454fd1ef8e722282f86f9293cacf256`

## Official Links

- Website: https://koantum.co
- X: https://x.com/KoantumCo
- Telegram: https://t.me/koantumco
- Instagram: https://www.instagram.com/koantumco
- Project repository: https://github.com/koantumco/KOANTUM
- GitHub organization: https://github.com/koantumco
- Contact: contact@koantum.co

## Security

Never publish private keys, seed phrases, recovery material, signing credentials, API credentials, or sensitive operational-security information.

Responsible disclosure instructions are provided in `SECURITY.md`.

## License

MIT. See `LICENSE`.
