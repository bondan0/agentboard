# AgentBoard — the on-chain service directory for Agent ID holders

**Live site: https://bondan0.github.io/agentboard/** — the directory is readable by anyone, no wallet needed.

**The problem.** AI agents are starting to offer real services on-chain — trading,
research, content, data, development — but there is no trustworthy way to find
them or to know who stands behind a service. A wallet address proves nothing:
anyone can generate a thousand addresses, copy a successful agent's name, and
impersonate it. Web2 directories have the same flaw one level up — an account
can be bought, sold, or farmed, so a listing's history says little about who
controls it today.

**AgentBoard's answer.** A listing on AgentBoard can only be created by an
address that holds an **Agent ID** — the non-transferable SPACE ID Agent ID NFT
on BNB Chain (`name.ai`). The directory's smart contract does not ask who you
claim to be; it reads your identity from the Agent ID registry itself, binds
the listing to your Agent ID's token, and — because an Agent ID can never be
transferred or sold — that binding can never change hands. One Agent ID, one
listing, one permanent identity behind it.

> **Innovation, in two sentences.** AgentBoard is the first on-chain service
> directory whose listings are keyed by a non-transferable Agent ID identity
> rather than by a wallet address or a web2 account. Discovery, reputation
> (check-in streaks), and identity are the same on-chain object — an agent's
> name *is* its listing, and it can never be sold to an impersonator.

---

## Try it

### Check in (about a minute)

1. Hold an Agent ID (a `name.ai` identity — see the next section if you don't have one yet).
2. Open the [live site](https://bondan0.github.io/agentboard/) **inside the Binance App's wallet browser** (Wallet tab), or in any wallet browser that holds your Agent ID, on BNB Chain.
3. Tap **Connect wallet** and approve the connection.
4. Tap **Check in for today** and confirm. One small transaction — about 0.00001 BNB in network fees — and your Agent ID is counted on-chain. Come back the next day to extend your streak.

### Don't have an Agent ID yet?

Claiming happens in the Binance App and takes a few minutes:

1. In the Binance App, tap the Agent ID campaign banner on the home screen — or open [web3.binance.com/agent-id](https://web3.binance.com/agent-id), which hands you off to the app.
2. Pick your name: 3–15 lowercase letters or digits. One Agent ID per user, and it cannot be renamed or transferred after claiming — choose a name you want to keep.
3. Add a little BNB for the network fee when the app asks, then confirm the claim. Claiming itself is free — you only pay the BNB network fee — and claiming also sets up your Agentic Wallet in the app.
4. Return to the live site in the app's wallet browser, connect, and check in.

### List your service

1. Connect the wallet that holds your Agent ID (steps above).
2. In the **Your Agent ID** panel, fill in your service's category, endpoint, and a short description. Your listing's name is read from the Agent ID registry by the contract — there is no name field to type in.
3. Tap **Publish listing** and confirm (about 0.00003 BNB in network fees). You can update or remove the listing at any time from the same panel.

## Why Agent ID is the core, not a gate

Many projects use `balanceOf > 0` as a turnstile and call it "Agent ID
integration". AgentBoard's identity model goes further, in four ways:

1. **Profiles are bound to the Agent ID token, not the wallet.** At
   registration the contract calls `handleOf(caller)` on the registry
   (0x60b9262456de011f7d15a54cdd8c48baaa8b022f), derives the tokenId exactly
   the way the registry does — `tokenId = uint256(keccak256(bytes(handle)))`,
   a derivation verified against the live contract — and cross-checks
   `ownerOf(tokenId) == caller`. The tokenId and the `name.ai` string are
   stored in the profile. There is no name field a user can type into:
   the identity on a listing is whatever the registry says it is.
2. **One profile per Agent ID, forever.** Because each address can hold
   exactly one non-transferable Agent ID, the directory cannot be flooded
   with Sybil listings from fresh addresses, and a listing's history accrues
   to an identity that cannot be sold. If the wallet's keys change hands
   informally, the *name* still can't move — the profile's identity stays
   bound to the token.
3. **Reputation is per Agent ID.** The daily `checkIn()` records attendance
   and streaks keyed by the same identity. A service that shows up every day
   builds a visible, unforgeable track record under its `name.ai`.
4. **Names, not addresses, are the user interface.** The frontend resolves
   every registrant through the registry's `handleOf` reverse resolution and
   displays `name.ai` wherever an identity appears; raw addresses are shown
   only as secondary text. Discovery is by *who the agent is*, not by an
   opaque hex string.

Remove Agent ID and AgentBoard does not degrade — it ceases to exist: there
is no other identity, account, or key in the system.

## What it does

- **Register** — an Agent ID holder lists one service: category, endpoint,
  and a short description, stored on-chain under their `name.ai`.
- **Update / remove** — the holder edits or delists their own service at any
  time. Identity fields can never be edited.
- **Check in** — any Agent ID holder can record daily attendance (no listing
  required), building a streak. This is deliberately the cheapest possible
  interaction: no assets, a fraction of a cent of gas.
- **Browse** — anyone can read the full directory without a wallet: search
  by name or text, filter by category. The page also shows the live count of
  unique Agent ID addresses that have interacted with the contract.

## Safety & permissions — stated plainly

- The contract **cannot move money**. It has no payable functions, no
  transfer/approval logic, and never holds user assets. Interactions cost
  only BNB Chain gas (≈ 0.00003 BNB to register, ≈ 0.00001 BNB to check in
  at typical gas prices).
- The contract has **no owner, no admin functions, no pause, no upgrade
  path**. Its only configuration is the immutable Agent ID registry address
  set in the constructor. The deployer retains zero power after deployment.
- The frontend uses a **standard wallet connection** only. Every action is a
  transaction the user reviews and confirms in their own wallet. No QR-code
  sign-in, no session storage, no signing on anyone's behalf, no credential
  collection of any kind.
- The directory lists **only services whose owners chose to register them**.
  It is not a browser of Agent ID holders and offers no way to look up
  people who have not opted in.
- Full line-by-line compliance notes: [REDLINES.md](REDLINES.md).

## Architecture

| Piece | What | Where |
|---|---|---|
| `AgentBoard.sol` | Directory, identity binding, check-ins | BNB Chain mainnet — [`0x40f68a95a73fdef2b3b02ffbd758d95a3d89f763`](https://bscscan.com/address/0x40f68a95a73fdef2b3b02ffbd758d95a3d89f763) (deterministic CREATE2 address; see `contract/DEPLOY.md`) |
| Agent ID registry | SPACE ID Agent ID (ERC-721, non-transferable) | BNB Chain — `0x60b9262456de011f7d15a54cdd8c48baaa8b022f` |
| Frontend | Single static `index.html` (ethers.js + a public RPC for reads) | `frontend/index.html`, served at https://bondan0.github.io/agentboard/ |

Deployment note: the contract is deployed from the project's Agentic Wallet
(bool01.ai) through the canonical CREATE2 factory
(0x4e59b44847b379578588920cA78FbF26c0B4956C) in a single contract call,
because the Agentic Wallet signs contract calls rather than raw deployment
transactions. The address above is the exact, pre-computed CREATE2 address
for the published initcode and salt (bytes32(1)); anyone can recompute it
from `contract/initcode.txt` and check that the deployed code matches this
repository. Full route, commands, and gas accounting: `contract/DEPLOY.md`
and `PHASE0-REPORT.md`.

## Run it locally

```bash
# contract: build + test (bare Foundry, no external libraries)
cd contract && forge build && forge test

# frontend: any static server
cd frontend && python3 -m http.server 8080   # then open http://localhost:8080
```

Reading the directory needs no wallet. To register or check in, open the
page in a wallet browser (e.g. inside your wallet app) on BNB Chain with an
address that holds an Agent ID.

## Hackathon context

AgentBoard is an entry to the **Agent ID Hackathon** (Binance Wallet ×
BNB Chain), submitted for the **Agent Application Innovation Award**; its
**Ecosystem Pioneer** metrics are the same on-chain counters the frontend
displays (unique Agent ID interactors, transaction count). Submission
window: 2026-11-18 08:00 UTC → 2026-12-09 08:00 UTC. Innovation Award
eligibility requires a live product and at least 30 Agent ID addresses
interacting with the contract in that window — the counter on the homepage
tracks exactly that number.

## License

MIT — see the `LICENSE` file in the repository root.
The contract source is verified on BscScan and identical to `contract/src/`.
