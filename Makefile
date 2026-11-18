# Local dev commands. Run `make help` to list them.

-include .env
export

RPC_URL     ?= http://127.0.0.1:8545
UI_PORT     ?= 5173
# Default: anvil account #0 — public dev key, local use only. Override in .env.
# PRIVATE_KEY ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.DEFAULT_GOAL := help
.PHONY: help build test fmt clean anvil deploy deploy-sepolia ui dev docs

help: ## List available commands
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-15s %s\n", $$1, $$2}'

build: ## Compile contracts
	forge build

test: ## Run tests
	forge test -vvv

fmt: ## Format Solidity files
	forge fmt

clean: ## Remove build artifacts
	forge clean

anvil: ## Run a local chain in the foreground (keep it in its own terminal)
	anvil

deploy: ## Deploy mocks + FarmersMarket to RPC_URL and write ui/deployments.json
	@forge script script/DeployLocal.s.sol --rpc-url $(RPC_URL) --broadcast --private-key $(PRIVATE_KEY)

deploy-sepolia: ## Deploy WethMarket (WETH/PYUSD) to Sepolia, verify, write ui/deployments.sepolia.json
	@[ -n "$(ETHEREUM_SEPOLIA_RPC_URL)" ] || { echo "Set ETHEREUM_SEPOLIA_RPC_URL in .env"; exit 1; }
	@[ -n "$(ETHERSCAN_API_KEY)" ] || { echo "Set ETHERSCAN_API_KEY in .env"; exit 1; }
	forge script script/DeploySepolia.s.sol --rpc-url $(ETHEREUM_SEPOLIA_RPC_URL) --broadcast --private-key $(PRIVATE_KEY) --start-fresh

ui: ## Serve the UI at http://localhost:UI_PORT
	@echo "UI → http://localhost:$(UI_PORT)"
	python3 -m http.server $(UI_PORT) --directory ui

dev: ## All-in-one: fresh anvil + deploy + UI (Ctrl+C stops everything)
	./ui/dev.sh

docs: ## Run the docs site locally (installs deps on first run)
	@[ -d docs/node_modules ] || npm --prefix docs install
	npm --prefix docs run dev
