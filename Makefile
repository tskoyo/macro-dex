# Local dev commands. Run `make help` to list them.

-include .env
export

RPC_URL     ?= http://127.0.0.1:8545
UI_PORT     ?= 5173
# Default: anvil account #0 — public dev key, local use only. Override in .env.
PRIVATE_KEY ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

.DEFAULT_GOAL := help
.PHONY: help build test fmt clean anvil deploy ui dev

help: ## List available commands
	@grep -hE '^[a-z]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  make %-8s %s\n", $$1, $$2}'

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

ui: ## Serve the UI at http://localhost:UI_PORT
	@echo "UI → http://localhost:$(UI_PORT)"
	python3 -m http.server $(UI_PORT) --directory ui

dev: ## All-in-one: fresh anvil + deploy + UI (Ctrl+C stops everything)
	./ui/dev.sh
