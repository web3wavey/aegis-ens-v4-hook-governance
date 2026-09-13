# Aegis Frontend

Intentionally separate from the repository root `README.md`.

## Identity design

- The connected wallet comes from MetaMask.
- The connected wallet's visible ENSv2 primary name comes from the ETHOnline Universal Resolver.
- Active/inactive authorization comes from `OperatorRoleManager`.
- The operator directory is reconstructed from `OperatorAdded` and `OperatorRemoved` events.
- Each discovered operator wallet is reverse-resolved through the Universal Resolver.
- `HookGovernance.poolConfigs(poolId)` supplies the governance resource.

If a wallet has no valid ENSv2 primary-name record yet, the UI displays the wallet address rather than inventing a name.

## Required environment variables

See `frontend/.env.example`.

`SEPOLIA_RPC_URL` is server-only and is proxied through `frontend/app/api/rpc/route.ts`.

`NEXT_PUBLIC_OPERATOR_SCAN_FROM_BLOCK` must be the deployment block of `OperatorRoleManager`. It is used only to bound the event scan; it is not identity data.

## Local

From the repo root:

```bash
cd frontend
cp .env.example .env.local
# edit .env.local
npm install
npm run dev
```

Open http://localhost:3000.

## Vercel

Import the repository as a Vercel project and set the Vercel Root Directory to `frontend`.

Add the same environment variables in Vercel Project Settings. Keep `SEPOLIA_RPC_URL` server-only.
