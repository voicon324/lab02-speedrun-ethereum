# Lab02
## Student Information
- **Name**: Ho Khanh Duy
- **ID**: 22120076

## Challenges### Included Challenges
1.  **Challenge 1: Decentralized Staking App**
    - Directory: `challenge-decentralized-staking`
2.  **Challenge 2: Token Vendor**
    - Directory: `challenge-token-vendor`
3.  **Challenge 3: Dice Game**
    - Directory: `challenge-dice-game`
4.  **Challenge 4: Build a DEX**
    - Directory: `challenge-dex`
5.  **Challenge 5: Over-Collateralized Lending**
    - Directory: `challenge-over-collateralized-lending`
6.  **Challenge 6: Stablecoins**
    - Directory: `challenge-stablecoins` 

## How to Run

For each challenge, navigate to its directory and follow these steps:

1.  Install dependencies:
    ```bash
    yarn install
    ```

2.  Start the local chain:
    ```bash
    yarn chain
    ```

3.  Deploy contracts (in a new terminal):
    ```bash
    yarn deploy
    ```

4.  Start the frontend (in a new terminal):
    ```bash
    yarn start
    ```

5.  Open your browser at `http://localhost:3000`.

## Switching to Local Network
The challenges are currently configured for **Sepolia**. To run them locally:

1.  Open `packages/nextjs/scaffold.config.ts` in the challenge folder.
2.  Change `targetNetworks` from `[chains.sepolia]` to `[chains.foundry]` (or `[chains.hardhat]`).
    ```typescript
    // packages/nextjs/scaffold.config.ts
    // targetNetworks: [chains.sepolia], 
    targetNetworks: [chains.foundry], 
    ```
3.  Restart your frontend (`yarn start`).
