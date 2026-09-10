# Ageis! ENSv2 × Uniswap v4 Hook Governance

An ENSv2-powered governance and permission layer for Uniswap v4 pools.

## Overview

This project uses ENSv2 permissions as the authorization layer for a Uniswap v4 hook.

Each governed Uniswap v4 pool is associated with an ENSv2 resource. The hook uses that resource to determine which addresses are authorized to perform governance actions such as pausing or unpausing the pool.

The architecture separates three concerns:


ENSv2
  │
  │ identity + permissions
  ▼
HookGovernance
  │
  │ enforcement
  ▼
Uniswap v4 PoolManager
  │
  ▼
Governed Pool


## Why this matters

Uniswap v4 hooks allow developers to introduce custom behavior around swaps and liquidity operations.

This project explores how ENSv2 can provide a reusable, on-chain governance layer for those hooks rather than relying entirely on a hardcoded operator address.

An ENSv2 role can be granted or revoked independently of the pool and hook deployment, allowing operator permissions to evolve over time.

## Current Progress

### Completed

* ✅ ENSv2 name registered on Sepolia
* ✅ ENSv2 stable resource created
* ✅ `HookGovernance` contract implemented
* ✅ ENSv2 permission checks integrated into the hook
* ✅ Hook deployed
* ✅ Pool-specific governance architecture implemented
* ✅ Local governance tests implemented

### In Progress

The next integration milestone is connecting the deployed hook to a real Uniswap v4 pool:


Create PoolKey
      ↓
Initialize v4 pool
      ↓
Calculate PoolId
      ↓
configurePool(PoolId, ENS_RESOURCE)
      ↓
Grant ENS operator role
      ↓
Add liquidity
      ↓
Execute swap
      ↓
Pause pool
      ↓
Verify swap is blocked


## Core Architecture

A single `HookGovernance` contract can govern multiple Uniswap v4 pools.

Each pool is mapped to its own ENSv2 resource:


HookGovernance
       │
       ├── PoolId A → ENS Resource A
       │
       ├── PoolId B → ENS Resource B
       │
       └── PoolId C → ENS Resource C


This means different pools using the same hook can have independent operators and governance permissions.

## Governance Flow


ENSv2 Name
     ↓
ENSv2 Resource
     ↓
Operator Role
     ↓
HookGovernance
     ↓
PoolId
     ↓
Uniswap v4 Pool


## Planned Demo

The final demo will show:


Admin
  ↓
grants ENS role
  ↓
Operator
  ↓
pauses Uniswap v4 pool
  ↓
swap fails


Then:


Admin
  ↓
revokes old operator
  ↓
grants new operator
  ↓
new operator unpauses pool
  ↓
swap succeeds

The goal is to demonstrate that pool governance can change through ENSv2 permissions without redeploying the Uniswap pool or governance hook.

## Network

Current development and deployment target:

**Ethereum Sepolia**

## Tech Stack

* Solidity
* Foundry
* ENSv2
* ENSv2 Permissioned Registry
* Uniswap v4
* Uniswap v4 Hooks
* Ethereum Sepolia

Frontend development will use React/Next.js with an Ethereum wallet integration.

## Development Status

**Hackathon project currently under active development.**

The smart-contract governance layer and initial deployments are complete. Uniswap v4 pool integration and the governance frontend are currently being built.

