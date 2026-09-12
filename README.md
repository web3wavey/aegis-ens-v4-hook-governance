# Aegis — ENSv2 × Uniswap v4 Pool Governance

**ENS-powered multi-operator access control and governance for Uniswap v4 pools.**

Aegis separates **identity, authorization, and pool enforcement** so protocols can delegate Uniswap v4 operations without handing over ultimate governance control.

> **Identity is not authority.**

An address can have a valid ENS operator identity while still having zero permission to operate a pool.

---

## The Problem

Uniswap v4 hooks enable powerful custom pool behaviour, but protocols still need to answer:

**Who is allowed to control the hook?**

Hardcoding one owner or operator creates several problems:

* operational authority becomes tied to individual wallets;
* changing operators can require additional contract-specific administration;
* multiple operators are harder to represent clearly;
* identity and permissions become tightly coupled;
* day-to-day operators may receive more authority than they need.

Aegis introduces a hierarchical governance model built around ENSv2 identities.

---

## How Aegis Works

Aegis separates the system into three layers:

```text
ENSv2
  │
  │ identity + governance hierarchy
  ▼
OperatorRoleManager
  │
  │ application authorization
  ▼
HookGovernance
  │
  │ on-chain pool enforcement
  ▼
Uniswap v4 PoolManager
  │
  ▼
Governed Pool
```

### Example hierarchy

```text
project.eth
│
│  ULTIMATE GOVERNANCE
│
└── operator.project.eth
      │
      │  OPERATOR ADMIN
      │
      ├── alice.operator.project.eth  → ACTIVE
      ├── bob.operator.project.eth    → ACTIVE
      └── charlie.operator.project.eth → INACTIVE
```

Alice and Bob may operate the same pool simultaneously.

Charlie can have a valid ENS identity while having **no pool authority**.

---

## Governance Model

Aegis separates project governance from operational access.

| Identity                       | Operate Pool | Add / Remove Operators | Ultimate Control |
| ------------------------------ | -----------: | ---------------------: | ---------------: |
| `project.eth`                  |     Optional |                      ✅ |                ✅ |
| `operator.project.eth`         |     Optional |                      ✅ |                ❌ |
| `alice.operator.project.eth`   |            ✅ |                      ❌ |                ❌ |
| `bob.operator.project.eth`     |            ✅ |                      ❌ |                ❌ |
| `charlie.operator.project.eth` |            ❌ |                      ❌ |                ❌ |

Individual pool operators cannot:

* grant another wallet access;
* revoke another operator;
* replace the operator administrator;
* change the governance resource;
* change the pool binding;
* take ownership of parent governance.

The parent ENS owner remains the ultimate authority.

---

## Core Contracts

### `OperatorRoleManager.sol`

Manages application-level pool authorization while retaining ENSv2 identities.

Each operator assignment records:

```solidity
struct OperatorAssignment {
    address identityRegistry;
    uint256 identityResource;
    bool active;
}
```

Operators are scoped to an ENS governance resource:

```text
ENS governance resource
        │
        ├── Alice → active
        ├── Bob → active
        └── Charlie → inactive
```

Only the parent ENS owner or delegated operator administrator can add or remove operators.

This deliberately separates:

```text
ENS identity ≠ pool permission
```

---

### `HookGovernance.sol`

A Uniswap v4 hook that enforces operator permissions for governed pools.

Each Uniswap v4 `PoolId` is associated with its ENS governance resource:

```text
PoolId
  │
  └── ENS Resource
```

Before allowing protected governance actions, `HookGovernance` asks the role manager whether the caller is an active operator.

Conceptually:

```solidity
operatorRoleManager.isOperator(
    governanceResource,
    account
);
```

Authorized operators can currently:

```text
pausePool()
unpausePool()
```

Unauthorized wallets revert.

---

## Uniswap v4 Integration

Aegis integrates directly with the Uniswap v4 hook architecture.

The project uses Uniswap v4 components including:

```text
IPoolManager
IHooks
Hooks
PoolKey
PoolId
PoolIdLibrary
BalanceDelta
BeforeSwapDelta
```

`HookGovernance` implements the `IHooks` interface and declares its hook permissions using Uniswap's hook permission flags.

The current hook supports callbacks around:

```text
beforeSwap
beforeAddLiquidity
beforeRemoveLiquidity
```

Pool-specific governance state is stored against each `PoolId`, allowing one `HookGovernance` deployment to support multiple independently governed pools.

```text
HookGovernance
      │
      ├── PoolId A → ENS Resource A
      ├── PoolId B → ENS Resource B
      └── PoolId C → ENS Resource C
```

---

## ENSv2 Integration

ENSv2 provides the identity and governance hierarchy.

Aegis uses ENS resources to represent:

```text
project governance
operator administration
individual operator identities
```

The `OperatorRoleManager` integrates with the ENSv2 `IPermissionedRegistry`.

The current owner of the parent ENS governance resource acts as the root authority for that project's operator configuration.

This means operational authority can change without changing the identity of the governed Uniswap pool.

---

## Operator Audit Trail

Governance actions preserve both the operator wallet and ENS identity resource.

For example, when Alice pauses a pool:

```text
PoolPaused

Pool:
0xabcd...

Operator wallet:
0xA11CE...

ENS identity:
alice.operator.project.eth
```

The emitted event records:

```text
PoolId
operator wallet
identity registry
identity resource
```

This allows the frontend to show **who performed an action and under which ENS identity**.

---

# Current Hackathon Status

## Completed

```text
ENSv2 integration
├── ENSv2 governance name                  ✅
├── Stable ENS resource                    ✅
├── Parent governance authority            ✅
└── ENS identity validation                ✅

Operator governance
├── OperatorRoleManager                    ✅
├── Parent owner override                  ✅
├── Delegated operator admin               ✅
├── Add operator                           ✅
├── Remove operator                        ✅
└── ENS identity / permission separation   ✅

Uniswap v4 hook
├── HookGovernance                         ✅
├── Pool-specific configuration            ✅
├── Operator authorization                 ✅
├── Pause / unpause                        ✅
├── Operator identity events               ✅
└── Hook deployed                          ✅
```

---

# Current Development Checkpoint

The project is now at the **Uniswap v4 pool stage**.

The next checkpoint is connecting a real test pool to the deployed governance system:

```text
Native ETH / Hackathon MockUSDC
              │
              ▼
      Uniswap v4 PoolManager
              │
              ▼
        HookGovernance
              │
              ▼
            PoolId
              │
              ▼
         ENS_RESOURCE
```

### Current task

```text
Create PoolKey
      ↓
Initialize Native ETH / MockUSDC pool
      ↓
Calculate PoolId
      ↓
configurePool(PoolId, ENS_RESOURCE)
      ↓
Connect active ENS operators
      ↓
Add liquidity
      ↓
Execute swap
      ↓
Pause pool
      ↓
Attempt swap
      ↓
Hook blocks swap
      ↓
Unpause pool
      ↓
Swap succeeds
```

This will complete the first full end-to-end flow from:

```text
ENS identity
      ↓
operator authorization
      ↓
Uniswap v4 hook
      ↓
real pool behavior
```

---

# Demo Pool

The first demonstration pool uses:

```text
Native ETH
   +
Hackathon MockUSDC
```

with the deployed `HookGovernance` attached through its `PoolKey`.

The expected relationship is:

```text
PoolKey
  │
  ├── currency0 / currency1
  ├── fee
  ├── tickSpacing
  └── HookGovernance
          │
          ▼
        PoolId
          │
          ▼
     ENS_RESOURCE
          │
          ▼
  OperatorRoleManager
          │
     ┌────┴────┐
     │         │
   Alice      Bob
   ACTIVE     ACTIVE
```

---

# Example Use Cases

### DAO Treasury Operations

A DAO can allow several treasury contributors to operate liquidity pools without giving each contributor control of the DAO's root governance identity.

### DeFi Protocol Operations

A protocol can delegate day-to-day pool operations to an operations team while retaining emergency control at the parent ENS level.

### Security Teams

Authorised security operators can pause affected pools during an incident without receiving permission to modify the protocol's governance hierarchy.

### Liquidity Management Teams

Multiple liquidity managers can operate the same pool simultaneously using individually identifiable ENS identities.

### Contributor Identity

Projects can issue ENS subnames to contributors without automatically granting protocol permissions.

```text
alice.operator.project.eth     ACTIVE
bob.operator.project.eth       ACTIVE
charlie.operator.project.eth   INACTIVE
```

---

# Planned Demo

The final demo will show three different roles:

```text
Project Admin
     │
     └── ultimate ENS governance

Operator Admin
     │
     └── adds / removes operators

Pool Operator
     │
     └── operates governed pools
```

Example flow:

```text
Project Admin
      ↓
designates Operator Admin
      ↓
Operator Admin adds Alice
      ↓
alice.operator.project.eth
      ↓
Alice pauses ETH / MockUSDC
      ↓
swap attempt
      ↓
HookGovernance reverts
```

Then:

```text
Operator Admin removes Alice
      ↓
adds Bob
      ↓
bob.operator.project.eth
      ↓
Bob unpauses pool
      ↓
swap succeeds
```

The demo proves that operational authority can change without redeploying the Uniswap pool or governance hook.

---

## Project Structure

```text
src/
├── HookGovernance.sol
├── OperatorRoleManager.sol
└── interfaces/
    └── IOperatorRoleManager.sol

script/
├── deployment and ENS setup scripts
└── Uniswap pool setup scripts

test/
└── Foundry unit and integration tests
```

---

## Tech Stack

* Solidity `0.8.24`
* Foundry
* ENSv2
* ENSv2 `IPermissionedRegistry`
* Uniswap v4
* Uniswap v4 `PoolManager`
* Uniswap v4 Hooks
* Ethereum Sepolia
* React / Next.js frontend planned

---

## Design Principle

Aegis is built around one key principle:

> **Identity is not authority.**

ENS tells the system **who an operator is**.

`OperatorRoleManager` determines **what that operator is allowed to do**.

`HookGovernance` enforces those permissions against **real Uniswap v4 pool behavior**.

---

## Status

**ETHOnline 2026 hackathon project — active development**

Current milestone:

**Native ETH / Hackathon MockUSDC → Uniswap v4 PoolManager → HookGovernance → PoolId → ENS resource**

