include .env

.PHONY: format test build deploy verify 

format:
	forge fmt 

test:
	forge test

build:
	forge build

deploy-mock-usdc:
	forge script script/DeployMockERC20.s.sol \
	--rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) \
	--broadcast --verify --verifier blockscout \
	--verifier-url $(BLOCKSCOUT_VERIFIER_URL)

deploy:
	forge script script/DeployFlashbet.s.sol \
	--rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) \
	--broadcast --verify --verifier blockscout \
	--verifier-url $(BLOCKSCOUT_VERIFIER_URL)

verify:
	forge script script/DeployFlashbet.s.sol \
	--rpc-url $(RPC_URL) --private-key $(PRIVATE_KEY) \
	--resume --verify --verifier blockscout \
	--verifier-url $(BLOCKSCOUT_VERIFIER_URL)