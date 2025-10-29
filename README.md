
# 🎯 DrawChain

- **Automated, Provably Fair On-Chain Draw System**  
- Built on Solidity — deployed on the **Celo Sepolia Testnet**  
- ✨ Transparent • Trustless • Verifiable ✨

---

## 📖 Project Description

**DrawChain** is a decentralized smart contract designed to host **provably fair draws** entirely on-chain.  
It uses the **commit-reveal** pattern to ensure that every participant has an equal and verifiable chance to win — without relying on any centralized authority or off-chain randomness.

This project demonstrates the principles of fairness, transparency, and automation in blockchain-based draw systems.


<img width="1920" height="1080" alt="Screenshot (1)" src="https://github.com/user-attachments/assets/8c9f2808-6e8d-4c6e-8d53-173edf05614d" />

<img width="1908" height="899" alt="Screenshot 2025-10-29 135437" src="https://github.com/user-attachments/assets/9192e48e-0846-40ac-a1f7-eefa13fe78eb" />


---

## ⚙️ What It Does

1. **Create a Draw** — Anyone can create a new draw with a custom commit and reveal phase duration.  
2. **Commit Phase** — Participants submit a hashed version of their secret (commitment).  
3. **Reveal Phase** — Participants reveal their secrets to verify fairness.  
4. **Finalization** — After the reveal phase ends, the contract automatically and deterministically selects a winner using all revealed secrets + a block hash for unpredictability.  
5. **Transparency** — Every step, from commitments to winner selection, is public and verifiable on-chain.

---

## 🌟 Features

✅ **Fully On-Chain & Automated** — No external dependencies or oracles required  
🔒 **Commit–Reveal Fairness** — Ensures no one can manipulate results after committing  
⚡ **Instant Verification** — Anyone can verify the fairness of the outcome  
🧩 **Customizable Draws** — Each draw can have its own timeframes  
📜 **Open Source & Minimal Gas Cost** — Simple yet powerful Solidity implementation  
🌐 **Deployed on Celo Sepolia Testnet**

---

## 🔗 Deployed Smart Contract

**Network:** Celo Sepolia Testnet  
**Contract Address:** [`0x208D3f5ef0e544192FDa41e8db581D35875c5412`](https://celo-sepolia.blockscout.com/address/0x208D3f5ef0e544192FDa41e8db581D35875c5412)

You can interact with it directly via the [Celo Blockscout Explorer](https://celo-sepolia.blockscout.com/address/0x208D3f5ef0e544192FDa41e8db581D35875c5412).

---



## 🧠 Smart Contract Code

```solidity
//paste your code
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/// @title DrawChain — Simple provably-fair on-chain draw via commit-reveal
/// @notice Each draw has a commit phase and a reveal phase. Participants submit a hash(commitSecret)
///         during commit phase and reveal the secret during reveal phase. Winner chosen deterministically.
contract DrawChain {
    struct Draw {
        address creator;
        uint256 commitEnd;        // timestamp when commit phase ends
        uint256 revealEnd;        // timestamp when reveal phase ends
        address[] entrants;       // addresses who committed
        mapping(address => bytes32) commitments; // commit hash => participants
        mapping(address => bytes32) revealed;    // revealed secrets (bytes32)
        address[] revealedAddrs;  // ordered list of those who revealed
        bool finalized;
        address winner;
    }

    uint256 public nextDrawId;
    mapping(uint256 => Draw) private draws;

    event DrawCreated(uint256 indexed drawId, address indexed creator, uint256 commitEnd, uint256 revealEnd);
    event Committed(uint256 indexed drawId, address indexed participant, bytes32 commitment);
    event Revealed(uint256 indexed drawId, address indexed participant, bytes32 secret);
    event Finalized(uint256 indexed drawId, address indexed winner);

    modifier drawExists(uint256 drawId) {
        require(drawId < nextDrawId, "Draw does not exist");
        _;
    }

    function createDraw(uint256 commitDuration, uint256 revealDuration) external returns (uint256 drawId) {
        require(commitDuration > 0 && revealDuration > 0, "Durations must be > 0");
        drawId = nextDrawId++;
        Draw storage d = draws[drawId];
        d.creator = msg.sender;
        d.commitEnd = block.timestamp + commitDuration;
        d.revealEnd = d.commitEnd + revealDuration;
        emit DrawCreated(drawId, msg.sender, d.commitEnd, d.revealEnd);
    }

    function commit(uint256 drawId, bytes32 commitment) external drawExists(drawId) {
        Draw storage d = draws[drawId];
        require(block.timestamp <= d.commitEnd, "Commit phase is over");
        require(d.commitments[msg.sender] == bytes32(0), "Already committed");
        d.commitments[msg.sender] = commitment;
        d.entrants.push(msg.sender);
        emit Committed(drawId, msg.sender, commitment);
    }

    function reveal(uint256 drawId, bytes32 secret) external drawExists(drawId) {
        Draw storage d = draws[drawId];
        require(block.timestamp > d.commitEnd, "Reveal phase not started");
        require(block.timestamp <= d.revealEnd, "Reveal phase is over");
        bytes32 expected = d.commitments[msg.sender];
        require(expected != bytes32(0), "No commitment found");
        require(keccak256(abi.encodePacked(secret)) == expected, "Secret does not match commitment");
        require(d.revealed[msg.sender] == bytes32(0), "Already revealed");

        d.revealed[msg.sender] = secret;
        d.revealedAddrs.push(msg.sender);
        emit Revealed(drawId, msg.sender, secret);
    }

    function finalize(uint256 drawId) external drawExists(drawId) {
        Draw storage d = draws[drawId];
        require(block.timestamp > d.revealEnd, "Reveal phase not finished");
        require(!d.finalized, "Already finalized");
        uint256 revealedCount = d.revealedAddrs.length;
        require(revealedCount > 0, "No reveals - cannot finalize");

        uint256 seed = 0;
        for (uint256 i = 0; i < revealedCount; i++) {
            bytes32 s = d.revealed[d.revealedAddrs[i]];
            seed ^= uint256(s);
        }
        seed ^= uint256(blockhash(block.number - 1));

        uint256 winnerIndex = seed % revealedCount;
        address winner = d.revealedAddrs[winnerIndex];
        d.winner = winner;
        d.finalized = true;

        emit Finalized(drawId, winner);
    }

    function getDrawInfo(uint256 drawId) external view drawExists(drawId) returns (
        address creator,
        uint256 commitEnd,
        uint256 revealEnd,
        uint256 entrantCount,
        uint256 revealedCount,
        bool finalized,
        address winner
    ) {
        Draw storage d = draws[drawId];
        creator = d.creator;
        commitEnd = d.commitEnd;
        revealEnd = d.revealEnd;
        entrantCount = d.entrants.length;
        revealedCount = d.revealedAddrs.length;
        finalized = d.finalized;
        winner = d.winner;
    }

    function entrantAt(uint256 drawId, uint256 idx) external view drawExists(drawId) returns (address) {
        return draws[drawId].entrants[idx];
    }

    function revealedAt(uint256 drawId, uint256 idx) external view drawExists(drawId) returns (address) {
        return draws[drawId].revealedAddrs[idx];
    }

    function commitmentOf(uint256 drawId, address participant) external view drawExists(drawId) returns (bytes32) {
        return draws[drawId].commitments[participant];
    }

    function revealedSecretOf(uint256 drawId, address participant) external view drawExists(drawId) returns (bytes32) {
        return draws[drawId].revealed[participant];
    }
}

```
## 🧩 How to Use

- Deploy or interact with the existing contract on Celo Sepolia.

- Call createDraw(commitDuration, revealDuration) to start a new draw.

- During the commit phase, call commit(drawId, commitment) where
commitment = keccak256(abi.encodePacked(secret)).

- Once the reveal phase starts, call reveal(drawId, secret) to publish your secret.

- After the reveal phase ends, call finalize(drawId) to automatically pick a winner.

- View all details using getDrawInfo(drawId) or check winners via the explorer.

## 🧰 Tech Stack

- Language: Solidity ^0.8.19

- Network: Celo Sepolia Testnet

- Compiler: Remix / Hardhat compatible

- License: MIT

## 💡 Future Enhancements

🔗 Integration with Chainlink VRF for cryptographic randomness

💰 Add entry fees & on-chain prize pool distribution

🧠 Enhanced UI for tracking live draws

🧾 Add participant incentives for revealing secrets

## 👨‍💻 Author

Rupsa Bhattacharjee

📬 [LinkedIn](https://www.linkedin.com/in/rupsa-bhattacharjee/)

💻[GitHub](https://github.com/rupsaaa/)

---


