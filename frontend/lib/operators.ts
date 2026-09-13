import { Contract, Interface, JsonRpcProvider } from "ethers";
import {
  ADDRESSES,
  ROLE_MANAGER_ABI,
  reverseResolve,
} from "./contracts";

const LOG_CHUNK_SIZE = 1000;

export type DiscoveredOperator = {
  address: string;
  active: boolean;
  ensName: string | null;
  identityRegistry: string;
  identityResource: string;
};

export async function discoverOperators(
  provider: JsonRpcProvider,
  governanceResource: string
): Promise<DiscoveredOperator[]> {
  const fromBlock = Number(
    process.env.NEXT_PUBLIC_OPERATOR_SCAN_FROM_BLOCK
  );

  if (!fromBlock) {
    throw new Error(
      "NEXT_PUBLIC_OPERATOR_SCAN_FROM_BLOCK is missing"
    );
  }

  const latestBlock = await provider.getBlockNumber();
  const iface = new Interface(ROLE_MANAGER_ABI);
  const addedTopic = iface.getEvent("OperatorAdded")!.topicHash;
  const removedTopic = iface.getEvent("OperatorRemoved")!.topicHash;
  const discovered = new Set<string>();

  for (
    let start = fromBlock;
    start <= latestBlock;
    start += LOG_CHUNK_SIZE
  ) {
    const end = Math.min(
      start + LOG_CHUNK_SIZE - 1,
      latestBlock
    );

    const logs = await provider.getLogs({
      address: ADDRESSES.operatorRoleManager,
      fromBlock: start,
      toBlock: end,
      topics: [[addedTopic, removedTopic]],
    });

    for (const log of logs) {
      const parsed = iface.parseLog(log);
      if (!parsed) continue;

      if (
        parsed.name === "OperatorAdded" ||
        parsed.name === "OperatorRemoved"
      ) {
        const eventResource = parsed.args.governanceResource.toString();
        if (eventResource !== governanceResource) continue;

        discovered.add(
          String(parsed.args.operator).toLowerCase()
        );
      }
    }
  }

  const manager = new Contract(
    ADDRESSES.operatorRoleManager,
    ROLE_MANAGER_ABI,
    provider
  );

  const operators: DiscoveredOperator[] = [];

  for (const address of discovered) {
    const identity = await manager.operatorIdentity(
      governanceResource,
      address
    );

    operators.push({
      address,
      ensName: await reverseResolve(provider, address),
      identityRegistry: String(identity.identityRegistry),
      identityResource: identity.identityResource.toString(),
      active: Boolean(identity.active),
    });
  }

  return operators.sort((a, b) => {
    if (a.active !== b.active) return a.active ? -1 : 1;
    return (a.ensName || a.address).localeCompare(
      b.ensName || b.address
    );
  });
}
