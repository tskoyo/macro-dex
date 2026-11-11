# Local setup

Run the contracts and the demo UI on your own machine.

## Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `anvil`, `cast`)
- Python 3 (serves the demo UI)
- Node 18+ (only for these docs)

## One command

```sh
make dev
```

This starts a fresh local chain, deploys a mock wETH, a mock DAI and an ETH/DAI market (lot size 0.01 ETH), gives the first five test accounts 1,000,000 DAI each, and serves the UI at `http://localhost:5173`. Ctrl+C stops everything.

## Step by step

```sh
make anvil    # terminal 1: local chain
make deploy   # terminal 2: deploy, writes ui/deployments.json
make ui       # serve the UI
```

## Other commands

| Command | Does |
|---|---|
| `make build` | compile contracts |
| `make test` | run tests |
| `make fmt` | format Solidity |
| `make docs` | run this docs site locally |
| `make help` | list everything |

## Settings

Put overrides in `.env` (see `.env.example`). The Makefile reads `RPC_URL`, `PRIVATE_KEY` and `UI_PORT`. The default key is anvil's public test account #0. Never use it on a real network.
