import {
  BrowserProvider,
  Contract,
  EnsPlugin,
  JsonRpcProvider,
  Network,
} from "ethers";

export const CHAIN_ID = 11155111;

export const ADDRESSES = {
  poolManager:
    process.env.NEXT_PUBLIC_POOL_MANAGER ||
    "0xE03A1074c86CFeDd5C142C4F04F1a1536e203543",
  mockUsdc:
    process.env.NEXT_PUBLIC_MOCK_USDC ||
    "0xcBFD80F74375c54E545AF34788Ff465F96F66F05",
  operatorRoleManager:
    process.env.NEXT_PUBLIC_OPERATOR_ROLE_MANAGER ||
    "0xEebAC7F3571Ac2F2192ba1C4b1A0a543cC3C3fdb",
  hook:
    process.env.NEXT_PUBLIC_HOOK ||
    "0x0e54133807433c9dFeAF31CE2Af5B5382B974A80",
  swapRouter:
    process.env.NEXT_PUBLIC_AEGIS_SWAP_ROUTER ||
    "0x682b76Fc8016BE34D5193b49c50572058d3bdE15",
  ethRegistry:
    process.env.NEXT_PUBLIC_ETH_REGISTRY ||
    "0x1D78834d97c1D7b1A38c1deDBD1a287cFEd3971e",
  universalResolver:
    process.env.NEXT_PUBLIC_UNIVERSAL_RESOLVER ||
    "0xd26f2040D083Af1cD2962ba303F4BEa0c4faf142",
} as const;

export const POOL_ID =
  process.env.NEXT_PUBLIC_POOL_ID ||
  "0xcd20bfea4db6257cf8a6be57cb89ff9985cf161ca2bb52d48835dfb89764f3d6";

export const OPERATOR_SCAN_FROM_BLOCK = Number(
  process.env.NEXT_PUBLIC_OPERATOR_SCAN_FROM_BLOCK || "0"
);

export const HOOK_ABI = [
  "error Unauthorized()",
  "error PoolNotConfigured()",
  "function poolConfigs(bytes32 poolId) view returns (uint256 ensResource,bool paused,bool configured)",
  "function isPaused(bytes32 poolId) view returns (bool)",
  "function isOperator(bytes32 poolId,address account) view returns (bool)",
  "function pausePool(bytes32 poolId)",
  "function unpausePool(bytes32 poolId)",
];

export const ROLE_MANAGER_ABI = [
  "function operatorIdentity(uint256 governanceResource,address account) view returns (address identityRegistry,uint256 identityResource,bool active)",
  "function parentOwner(uint256 governanceResource) view returns (address)",
  "function governanceConfigs(uint256 governanceResource) view returns (address operatorAdmin,address operatorAdminIdentityRegistry,uint256 operatorAdminIdentityResource,bool configured)",
  "function addOperator(uint256 governanceResource,address account,address identityRegistry,uint256 identityResource)",
  "function removeOperator(uint256 governanceResource,address account)",
  "event OperatorAdded(uint256 indexed governanceResource,address indexed operator,address indexed authorizedBy,address identityRegistry,uint256 identityResource)",
  "event OperatorRemoved(uint256 indexed governanceResource,address indexed operator,address indexed authorizedBy,address identityRegistry,uint256 identityResource)",
];

export const SWAP_ROUTER_ABI = [
  "function swapExactEthForToken((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,uint128 amountIn,uint160 sqrtPriceLimitX96) payable returns (uint256 amountOut)",
];

export const ERC20_ABI = [
  "function balanceOf(address account) view returns (uint256)",
  "function decimals() view returns (uint8)",
];

export function readProvider() {
  const network = new Network("ethonline-ensv2-sepolia", CHAIN_ID);

  // Critical ETHOnline override: do not use ethers' built-in ENS deployment.
  network.attachPlugin(
    new EnsPlugin(
      ADDRESSES.ethRegistry,
      CHAIN_ID,
      ADDRESSES.universalResolver
    )
  );

  // Browser reads go through our Next server route, keeping the upstream
  // Alchemy/Infura URL out of the client bundle.
  const rpcUrl = `${window.location.origin}/api/rpc`;
  return new JsonRpcProvider(rpcUrl, network);
}

export async function reverseResolve(
  provider: JsonRpcProvider,
  address: string
): Promise<string | null> {
  try {
    return await provider.lookupAddress(address);
  } catch {
    return null;
  }
}

export async function walletProvider() {
  const ethereum = (window as unknown as { ethereum?: any }).ethereum;
  if (!ethereum) {
    throw new Error("No injected wallet found. Install MetaMask.");
  }
  return new BrowserProvider(ethereum);
}

export const hookContract = (runner: any) =>
  new Contract(ADDRESSES.hook, HOOK_ABI, runner);

export const roleManagerContract = (runner: any) =>
  new Contract(ADDRESSES.operatorRoleManager, ROLE_MANAGER_ABI, runner);

export const swapRouterContract = (runner: any) =>
  new Contract(ADDRESSES.swapRouter, SWAP_ROUTER_ABI, runner);

export const usdcContract = (runner: any) =>
  new Contract(ADDRESSES.mockUsdc, ERC20_ABI, runner);

export function shortAddress(value?: string) {
  if (!value) return "—";
  return `${value.slice(0, 6)}…${value.slice(-4)}`;
}
