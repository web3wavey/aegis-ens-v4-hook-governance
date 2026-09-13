"use client";

import { useCallback, useEffect, useMemo, useState } from "react";
import {
  Contract,
  formatUnits,
  isAddress,
  parseEther,
  type JsonRpcProvider,
} from "ethers";
import {
  ADDRESSES,
  CHAIN_ID,
  POOL_ID,
  hookContract,
  readProvider,
  reverseResolve,
  roleManagerContract,
  shortAddress,
  swapRouterContract,
  usdcContract,
  walletProvider,
} from "../lib/contracts";
import {
  discoverOperators,
  type DiscoveredOperator,
} from "../lib/operators";

const SWAP_AMOUNT = parseEther("0.0001");
const MIN_SQRT_PRICE_PLUS_ONE = 4295128740n;

const GOVERNANCE_REGISTRY_ABI = [
  "function LABEL_STORE() view returns (address)",
  "function getParent() view returns (address parent, string label)",
] as const;

const LABEL_STORE_ABI = [
  "function getLabel(uint256 anyId) view returns (string)",
] as const;

async function governanceNameFromResource(
  provider: JsonRpcProvider,
  governanceResource: string
): Promise<string | null> {
  try {
    const registry = new Contract(
      ADDRESSES.ethRegistry,
      GOVERNANCE_REGISTRY_ABI,
      provider
    );

    const [labelStoreAddress, parent] = await Promise.all([
      registry.LABEL_STORE(),
      registry.getParent(),
    ]);

    const labelStore = new Contract(
      labelStoreAddress,
      LABEL_STORE_ABI,
      provider
    );

    const label = await labelStore.getLabel(governanceResource);
    const parentLabel = parent.label || parent[1];

    if (!label) return null;

    return parentLabel ? `${label}.${parentLabel}` : label;
  } catch {
    return null;
  }
}

type Activity = {
  kind: "pause" | "unpause" | "swap" | "admin" | "error";
  title: string;
  detail: string;
  tx?: string;
};

export default function Home() {
  const [account, setAccount] = useState("");
  const [connectedName, setConnectedName] = useState<string | null>(null);
  const [paused, setPaused] = useState<boolean | null>(null);
  const [configured, setConfigured] = useState<boolean | null>(null);
  const [resource, setResource] = useState("");
  const [parentOwner, setParentOwner] = useState("");
  const [parentName, setParentName] = useState<string | null>(null);
  const [operatorAdmin, setOperatorAdmin] = useState("");
  const [operatorAdminName, setOperatorAdminName] = useState<string | null>(null);
  const [operatorAdminIdentityRegistry, setOperatorAdminIdentityRegistry] = useState("");
  const [operatorAdminIdentityResource, setOperatorAdminIdentityResource] = useState("");
  const [operators, setOperators] = useState<DiscoveredOperator[]>([]);
  const [newOperatorAddress, setNewOperatorAddress] = useState("");
  const [newIdentityRegistry, setNewIdentityRegistry] = useState("");
  const [newIdentityResource, setNewIdentityResource] = useState("");
  const [balance, setBalance] = useState("—");
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [activity, setActivity] = useState<Activity[]>([]);

  const connectedOperator = useMemo(
    () =>
      account
        ? operators.find(
            (operator) =>
              operator.address.toLowerCase() === account.toLowerCase()
          )
        : undefined,
    [operators, account]
  );

  const isGovernanceOwner = Boolean(
    account &&
      parentOwner &&
      account.toLowerCase() === parentOwner.toLowerCase()
  );

  const isOperatorAdmin = Boolean(
    account &&
      operatorAdmin &&
      operatorAdmin !== "0x0000000000000000000000000000000000000000" &&
      account.toLowerCase() === operatorAdmin.toLowerCase()
  );

  const isActiveOperator = Boolean(connectedOperator?.active);
  const canManageOperators = isGovernanceOwner || isOperatorAdmin;

  const connectedRole = !account
    ? "NO WALLET CONNECTED"
    : isGovernanceOwner
    ? "GOVERNANCE OWNER"
    : isOperatorAdmin
    ? "OPERATOR ADMIN"
    : isActiveOperator
    ? "ACTIVE OPERATOR"
    : "NO POOL ROLE";

  const loadState = useCallback(async () => {
    setError("");

    try {
      const provider = readProvider();
      const hook = hookContract(provider);
      const manager = roleManagerContract(provider);

      const config = await hook.poolConfigs(POOL_ID);
      const currentResource = config.ensResource.toString();

      setResource(currentResource);
      setPaused(Boolean(config.paused));
      setConfigured(Boolean(config.configured));

      const [owner, governanceConfig] = await Promise.all([
        manager.parentOwner(currentResource),
        manager.governanceConfigs(currentResource),
      ]);

      setParentOwner(owner);
      setParentName(
        await governanceNameFromResource(provider, currentResource)
      );

      const adminAddress = String(
        governanceConfig.operatorAdmin ?? governanceConfig[0]
      );
      const adminIdentityRegistry = String(
        governanceConfig.operatorAdminIdentityRegistry ?? governanceConfig[1]
      );
      const adminIdentityResource = (
        governanceConfig.operatorAdminIdentityResource ?? governanceConfig[2]
      ).toString();

      setOperatorAdmin(adminAddress);
      setOperatorAdminIdentityRegistry(adminIdentityRegistry);
      setOperatorAdminIdentityResource(adminIdentityResource);
      setOperatorAdminName(
        adminAddress !== "0x0000000000000000000000000000000000000000"
          ? await reverseResolve(provider, adminAddress)
          : null
      );

      try {
        setOperators(await discoverOperators(provider, currentResource));
      } catch (operatorError: any) {
        setError(
          operatorError?.message || "Could not discover operator events"
        );
      }

      if (account) {
        setConnectedName(await reverseResolve(provider, account));

        const token = usdcContract(provider);
        const decimals = Number(await token.decimals());
        const rawBalance = await token.balanceOf(account);
        setBalance(formatUnits(rawBalance, decimals));
      } else {
        setConnectedName(null);
        setBalance("—");
      }
    } catch (e: any) {
      setError(
        e?.shortMessage || e?.message || "Failed to read Sepolia state"
      );
    }
  }, [account]);

  useEffect(() => {
    loadState();
  }, [loadState]);

  useEffect(() => {
    const ethereum = (window as unknown as { ethereum?: any }).ethereum;
    if (!ethereum) return;

    const onAccountsChanged = (accounts: string[]) => {
      const nextAccount = accounts?.[0] || "";

      setAccount(nextAccount);
      setConnectedName(null);
      setBalance("—");
    };

    const onChainChanged = () => {
      window.location.reload();
    };

    ethereum.on?.("accountsChanged", onAccountsChanged);
    ethereum.on?.("chainChanged", onChainChanged);

    return () => {
      ethereum.removeListener?.("accountsChanged", onAccountsChanged);
      ethereum.removeListener?.("chainChanged", onChainChanged);
    };
  }, []);

  useEffect(() => {
    if (!newIdentityRegistry && operators[0]?.identityRegistry) {
      setNewIdentityRegistry(operators[0].identityRegistry);
    }
  }, [operators, newIdentityRegistry]);

  async function connect() {
    setError("");

    try {
      const provider = await walletProvider();
      await provider.send("eth_requestAccounts", []);
      const signer = await provider.getSigner();
      setAccount(await signer.getAddress());
    } catch (e: any) {
      setError(e?.message || "Wallet connection failed");
    }
  }

  async function getSigner() {
    const provider = await walletProvider();
    const network = await provider.getNetwork();

    if (Number(network.chainId) !== CHAIN_ID) {
      await provider.send("wallet_switchEthereumChain", [
        { chainId: "0xaa36a7" },
      ]);
    }

    return provider.getSigner();
  }

  function pushActivity(item: Activity) {
    setActivity((current) => [item, ...current].slice(0, 6));
  }

  async function govern(action: "pause" | "unpause") {
    setBusy(action);
    setError("");

    let signerAddress = account;

    try {
      const signer = await getSigner();
      const hook = hookContract(signer);
      signerAddress = await signer.getAddress();

      const tx =
        action === "pause"
          ? await hook.pausePool(POOL_ID)
          : await hook.unpausePool(POOL_ID);

      await tx.wait();

      const provider = readProvider();
      const identity =
        (await reverseResolve(provider, signerAddress)) ||
        shortAddress(signerAddress);

      pushActivity({
        kind: action,
        title: action === "pause" ? "Pool paused" : "Pool unpaused",
        detail: `${identity} changed live pool state`,
        tx: tx.hash,
      });

      await loadState();
    } catch (e: any) {
      const raw = `${e?.shortMessage || ""} ${e?.reason || ""} ${
        e?.message || ""
      } ${e?.revert?.name || ""}`;
      const unauthorized =
        raw.includes("Unauthorized") || !connectedOperator?.active;
      const identity =
        connectedName || shortAddress(signerAddress || account);

      pushActivity({
        kind: "error",
        title: unauthorized
          ? "Governance action blocked"
          : "Governance transaction failed",
        detail: unauthorized
          ? `${identity} is not an active operator. HookGovernance reverted Unauthorized().`
          : e?.shortMessage || e?.reason || "Transaction reverted",
      });

      setError(
        unauthorized
          ? "Blocked on-chain: only an active Aegis operator can change pool state."
          : e?.shortMessage ||
              e?.reason ||
              e?.message ||
              "Governance transaction failed"
      );
    } finally {
      setBusy("");
    }
  }

  async function manageExistingOperator(operator: DiscoveredOperator) {
    const action = operator.active ? "remove" : "reactivate";
    setBusy(`${action}:${operator.address}`);
    setError("");

    try {
      if (!resource) throw new Error("Governance resource is not loaded");

      const signer = await getSigner();
      const manager = roleManagerContract(signer);

      const tx = operator.active
        ? await manager.removeOperator(resource, operator.address)
        : await manager.addOperator(
            resource,
            operator.address,
            operator.identityRegistry,
            BigInt(operator.identityResource)
          );

      await tx.wait();

      pushActivity({
        kind: "admin",
        title: operator.active ? "Operator removed" : "Operator reactivated",
        detail: `${operator.ensName || shortAddress(operator.address)} ${
          operator.active ? "lost" : "regained"
        } pool governance authority`,
        tx: tx.hash,
      });

      await loadState();
    } catch (e: any) {
      setError(
        e?.shortMessage ||
          e?.reason ||
          e?.message ||
          "Operator management transaction failed"
      );
    } finally {
      setBusy("");
    }
  }

  async function addNewOperator() {
    setError("");

    if (!resource) {
      setError("Governance resource is not loaded");
      return;
    }

    if (!isAddress(newOperatorAddress)) {
      setError("Enter a valid operator wallet address");
      return;
    }

    if (!isAddress(newIdentityRegistry)) {
      setError("Enter a valid ENSv2 identity registry address");
      return;
    }

    let identityResource: bigint;
    try {
      identityResource = BigInt(newIdentityResource);
      if (identityResource <= 0n) throw new Error();
    } catch {
      setError("Enter a valid non-zero ENSv2 identity resource");
      return;
    }

    setBusy("add-operator");

    try {
      const signer = await getSigner();
      const manager = roleManagerContract(signer);
      const tx = await manager.addOperator(
        resource,
        newOperatorAddress,
        newIdentityRegistry,
        identityResource
      );

      await tx.wait();

      const provider = readProvider();
      const name = await reverseResolve(provider, newOperatorAddress);

      pushActivity({
        kind: "admin",
        title: "Operator added",
        detail: `${name || shortAddress(newOperatorAddress)} received pool governance authority`,
        tx: tx.hash,
      });

      setNewOperatorAddress("");
      setNewIdentityResource("");
      await loadState();
    } catch (e: any) {
      setError(
        e?.shortMessage ||
          e?.reason ||
          e?.message ||
          "Add operator transaction failed"
      );
    } finally {
      setBusy("");
    }
  }

  async function swap() {
    setBusy("swap");
    setError("");

    try {
      const signer = await getSigner();
      const router = swapRouterContract(signer);

      const key = {
        currency0: "0x0000000000000000000000000000000000000000",
        currency1: ADDRESSES.mockUsdc,
        fee: 3000,
        tickSpacing: 60,
        hooks: ADDRESSES.hook,
      };

      const tx = await router.swapExactEthForToken(
        key,
        SWAP_AMOUNT,
        MIN_SQRT_PRICE_PLUS_ONE,
        { value: SWAP_AMOUNT }
      );

      await tx.wait();

      pushActivity({
        kind: "swap",
        title: "Swap executed",
        detail: "0.0001 ETH → MockUSDC",
        tx: tx.hash,
      });

      await loadState();
    } catch (e: any) {
      const raw = `${e?.shortMessage || ""} ${e?.reason || ""} ${
        e?.message || ""
      }`;

      const blocked = raw.includes("PoolIsPaused") || paused === true;

      pushActivity({
        kind: "error",
        title: blocked ? "Swap blocked by governance" : "Swap failed",
        detail: blocked
          ? "HookGovernance.beforeSwap rejected the live swap."
          : e?.shortMessage || "Transaction reverted",
      });

      setError(
        blocked
          ? "Swap blocked on-chain: PoolIsPaused()."
          : e?.shortMessage || e?.message || "Swap failed"
      );
    } finally {
      setBusy("");
    }
  }

  return (
    <main className="shell">
      <header className="masthead">
        <div>
          <div className="eyebrow">
            ETHONLINE 2026 // SEPOLIA // ENSV2
          </div>
          <h1>AEGIS</h1>
          <p>Live ENSv2 identity and Uniswap v4 enforcement.</p>
        </div>
        <button onClick={connect}>
          {account
            ? connectedName || shortAddress(account)
            : "CONNECT WALLET"}
        </button>
      </header>

      <section className="statusbar">
        <span className={`lamp ${paused ? "red" : "green"}`} />
        <strong>
          {paused === null
            ? "READING CHAIN…"
            : paused
            ? "POOL PAUSED"
            : "POOL ACTIVE"}
        </strong>
        <span>
          configured: {configured === null ? "…" : configured ? "yes" : "no"}
        </span>
        <button onClick={loadState}>REFRESH</button>
      </section>

      {error && <div className="errorbox">{error}</div>}

      <section className="grid heroGrid">
        <article className="panel">
          <div className="panelTitle">
            CONNECTED IDENTITY // UNIVERSAL RESOLVER
          </div>
          <div className="operatorName">
            {!account
              ? "connect a wallet"
              : connectedName || "primary ENSv2 name unresolved"}
          </div>
          <dl>
            <div>
              <dt>wallet</dt>
              <dd>{account ? shortAddress(account) : "—"}</dd>
            </div>
            <div>
              <dt>role</dt>
              <dd>{connectedRole}</dd>
            </div>
            <div>
              <dt>operator authority</dt>
              <dd>{isActiveOperator ? "YES" : "NO"}</dd>
            </div>
            <div>
              <dt>
                {isGovernanceOwner
                  ? "governance resource"
                  : "operator identity resource"}
              </dt>
              <dd>
                {isGovernanceOwner
                  ? resource || "—"
                  : connectedOperator?.identityResource || "—"}
              </dd>
            </div>
          </dl>
        </article>

        <article className="panel">
          <div className="panelTitle">
            GOVERNANCE OWNER // ENSV2 RESOURCE
          </div>
          <div className="bigName">
            {parentName || "ENSv2 resource name unavailable"}
          </div>
          <dl>
            <div>
              <dt>owner</dt>
              <dd>{parentOwner ? shortAddress(parentOwner) : "—"}</dd>
            </div>
            <div>
              <dt>resource</dt>
              <dd>{resource || "…"}</dd>
            </div>
          </dl>
        </article>
      </section>

      <section className="panel operators">
        <div className="panelTitle">
          OPERATORS // DISCOVERED FROM ON-CHAIN EVENTS
        </div>

        <div className="operatorGrid">
          {operators.length === 0 ? (
            <div className="empty">No operator events loaded yet.</div>
          ) : (
            operators.map((operator) => (
              <div
                className={`operatorCard ${
                  operator.active ? "active" : "inactive"
                }`}
                key={operator.address}
              >
                <div className="operatorTop">
                  <span>{operator.active ? "ACTIVE" : "INACTIVE"}</span>
                </div>
                <div className="operatorName">
                  {operator.ensName || "primary ENSv2 name unresolved"}
                </div>
                <div>{shortAddress(operator.address)}</div>
                <div className="identityResource">
                  <span>identity resource</span>
                  <code>{operator.identityResource}</code>
                </div>
              </div>
            ))
          )}
        </div>
      </section>

      <section className="panel adminPanel">
        <div className="panelTitle">
          GOVERNANCE ADMIN // OPERATOR ROLE MANAGER
        </div>

        <div className="adminSummary">
          <div>
            <span>connected authority</span>
            <strong>
              {!account
                ? "CONNECT WALLET"
                : isGovernanceOwner
                ? "PARENT OWNER"
                : isOperatorAdmin
                ? "OPERATOR ADMIN"
                : "READ ONLY"}
            </strong>
          </div>
          <div>
            <span>delegated operator admin</span>
            <strong>
              {operatorAdmin ===
              "0x0000000000000000000000000000000000000000"
                ? "REVOKED"
                : operatorAdminName || shortAddress(operatorAdmin)}
            </strong>
            {operatorAdmin &&
              operatorAdmin !==
                "0x0000000000000000000000000000000000000000" && (
                <small>{shortAddress(operatorAdmin)}</small>
              )}
          </div>
          <div>
            <span>admin identity resource</span>
            <strong>
              {operatorAdminIdentityResource &&
              operatorAdminIdentityResource !== "0"
                ? operatorAdminIdentityResource
                : "—"}
            </strong>
          </div>
        </div>

        {!account ? (
          <div className="adminNotice">
            Connect the governance owner or delegated operator admin to manage
            operators.
          </div>
        ) : !canManageOperators ? (
          <div className="adminNotice">
            This wallet can inspect governance but cannot add or remove
            operators.
          </div>
        ) : (
          <>
            <div className="adminOperatorList">
              {operators.map((operator) => (
                <div className="adminOperatorRow" key={operator.address}>
                  <div>
                    <strong>
                      {operator.ensName || shortAddress(operator.address)}
                    </strong>
                    <span>{shortAddress(operator.address)}</span>
                    <small>
                      {operator.active ? "ACTIVE" : "REVOKED"} · identity {
                        operator.identityResource
                      }
                    </small>
                  </div>
                  <button
                    className={operator.active ? "danger" : ""}
                    disabled={busy !== ""}
                    onClick={() => manageExistingOperator(operator)}
                  >
                    {busy === `remove:${operator.address}`
                      ? "REMOVING…"
                      : busy === `reactivate:${operator.address}`
                      ? "REACTIVATING…"
                      : operator.active
                      ? "REMOVE"
                      : "REACTIVATE"}
                  </button>
                </div>
              ))}
            </div>

            <div className="addOperatorBox">
              <div>
                <strong>ADD OPERATOR</strong>
                <p className="hint">
                  The role manager verifies that the supplied ENSv2 identity
                  resource exists before granting authority.
                </p>
              </div>
              <input
                value={newOperatorAddress}
                onChange={(event) => setNewOperatorAddress(event.target.value)}
                placeholder="operator wallet 0x…"
              />
              <input
                value={newIdentityRegistry}
                onChange={(event) => setNewIdentityRegistry(event.target.value)}
                placeholder="ENSv2 identity registry 0x…"
              />
              <input
                value={newIdentityResource}
                onChange={(event) => setNewIdentityResource(event.target.value)}
                placeholder="ENSv2 identity resource"
              />
              <button
                disabled={
                  busy !== "" ||
                  !newOperatorAddress ||
                  !newIdentityRegistry ||
                  !newIdentityResource
                }
                onClick={addNewOperator}
              >
                {busy === "add-operator" ? "ADDING…" : "ADD OPERATOR"}
              </button>
            </div>
          </>
        )}
      </section>

      <section className="grid demoGrid">
        <article className="panel">
          <div className="panelTitle">LIVE POOL CONTROL</div>
          <div className="pair">
            ETH <span>/</span> MockUSDC
          </div>
          <p className="muted">Uniswap v4 · 0.30% · tick spacing 60</p>
          <p className="hint">
            Any connected wallet can attempt these actions. HookGovernance,
            not the UI, enforces operator authorization on-chain.
          </p>
          <div className="buttonRow">
            <button
              className="danger"
              disabled={!account || busy !== "" || paused === true}
              onClick={() => govern("pause")}
            >
              {busy === "pause" ? "PAUSING…" : "PAUSE POOL"}
            </button>
            <button
              disabled={!account || busy !== "" || paused === false}
              onClick={() => govern("unpause")}
            >
              {busy === "unpause" ? "UNPAUSING…" : "UNPAUSE POOL"}
            </button>
          </div>
        </article>

        <article className="panel">
          <div className="panelTitle">LIVE ENFORCEMENT TEST</div>
          <div className="swapBox">
            <strong>0.0001 ETH</strong>
            <span>→</span>
            <strong>MockUSDC</strong>
          </div>
          <button
            className="swapButton"
            disabled={!account || busy !== ""}
            onClick={swap}
          >
            {busy === "swap"
              ? "SENDING SWAP…"
              : paused
              ? "TRY SWAP WHILE PAUSED"
              : "EXECUTE LIVE SWAP"}
          </button>
          <p className="hint">
            This remains clickable while paused so the v4 hook, not the
            frontend, proves enforcement.
          </p>
          <div className="balance">connected wallet MockUSDC: {balance}</div>
        </article>
      </section>

      <section className="panel activityPanel">
        <div className="panelTitle">DEMO ACTIVITY</div>
        {activity.length === 0 ? (
          <div className="empty">No frontend actions yet.</div>
        ) : (
          <div className="activityList">
            {activity.map((item, index) => (
              <div
                className={`activity ${item.kind}`}
                key={`${item.title}-${index}`}
              >
                <strong>{item.title}</strong>
                <span>{item.detail}</span>
                {item.tx && (
                  <a
                    href={`https://sepolia.etherscan.io/tx/${item.tx}`}
                    target="_blank"
                    rel="noreferrer"
                  >
                    view Sepolia tx ↗
                  </a>
                )}
              </div>
            ))}
          </div>
        )}
      </section>

      <section className="panel flow">
        <div className="panelTitle">LIVE DATA PATH</div>
        <div className="flowline">
          <span>MetaMask wallet</span>
          <b>→</b>
          <span>Universal Resolver</span>
          <b>→</b>
          <span>OperatorRoleManager</span>
          <b>→</b>
          <span>HookGovernance</span>
          <b>→</b>
          <span>Uniswap v4</span>
        </div>
      </section>
    </main>
  );
}
