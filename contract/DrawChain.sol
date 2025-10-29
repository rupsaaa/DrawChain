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

    /// @notice Create a new draw
    /// @param commitDuration seconds length of commit phase
    /// @param revealDuration seconds length of reveal phase (starts after commit phase)
    /// @return drawId id of the created draw
    function createDraw(uint256 commitDuration, uint256 revealDuration) external returns (uint256 drawId) {
        require(commitDuration > 0 && revealDuration > 0, "Durations must be > 0");
        drawId = nextDrawId++;
        Draw storage d = draws[drawId];
        d.creator = msg.sender;
        d.commitEnd = block.timestamp + commitDuration;
        d.revealEnd = d.commitEnd + revealDuration;
        emit DrawCreated(drawId, msg.sender, d.commitEnd, d.revealEnd);
    }

    /// @notice Enter a draw by submitting a commitment (hash of your secret)
    /// @param drawId id of the draw
    /// @param commitment keccak256(abi.encodePacked(secret, someAddressOrNonce)) recommended
    function commit(uint256 drawId, bytes32 commitment) external drawExists(drawId) {
        Draw storage d = draws[drawId];
        require(block.timestamp <= d.commitEnd, "Commit phase is over");
        require(d.commitments[msg.sender] == bytes32(0), "Already committed");
        // store commitment
        d.commitments[msg.sender] = commitment;
        d.entrants.push(msg.sender);
        emit Committed(drawId, msg.sender, commitment);
    }

    /// @notice Reveal your secret (must match previously submitted commitment)
    /// @param drawId id of the draw
    /// @param secret your secret as bytes32 (the preimage used to compute commitment)
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

    /// @notice Finalize the draw: computes winner from revealed secrets.
    ///         Anyone can call this after revealEnd.
    /// @param drawId id of the draw
    function finalize(uint256 drawId) external drawExists(drawId) {
        Draw storage d = draws[drawId];
        require(block.timestamp > d.revealEnd, "Reveal phase not finished");
        require(!d.finalized, "Already finalized");
        uint256 revealedCount = d.revealedAddrs.length;
        require(revealedCount > 0, "No reveals - cannot finalize");

        // Build seed from revealed secrets + blockhash for added unpredictability.
        // Using XOR of secrets makes every participant's secret affect final seed.
        uint256 seed = 0;
        for (uint256 i = 0; i < revealedCount; i++) {
            bytes32 s = d.revealed[d.revealedAddrs[i]];
            seed ^= uint256(s);
        }
        // mix in a recent blockhash (block.number - 1) to reduce predictability
        // NOTE: blockhash of older than 256 blocks is zero — we use block.number - 1 here.
        seed ^= uint256(blockhash(block.number - 1));

        uint256 winnerIndex = seed % revealedCount;
        address winner = d.revealedAddrs[winnerIndex];
        d.winner = winner;
        d.finalized = true;

        emit Finalized(drawId, winner);
    }

    /// @notice Read basic draw info
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

    /// @notice Get entrant at index (for off-chain verification)
    function entrantAt(uint256 drawId, uint256 idx) external view drawExists(drawId) returns (address) {
        return draws[drawId].entrants[idx];
    }

    /// @notice Get revealed address at index (for off-chain verification)
    function revealedAt(uint256 drawId, uint256 idx) external view drawExists(drawId) returns (address) {
        return draws[drawId].revealedAddrs[idx];
    }

    /// @notice Convenience: check commitment for an address
    function commitmentOf(uint256 drawId, address participant) external view drawExists(drawId) returns (bytes32) {
        return draws[drawId].commitments[participant];
    }

    /// @notice Convenience: check revealed secret for an address (bytes32). Anyone can read it after reveal.
    function revealedSecretOf(uint256 drawId, address participant) external view drawExists(drawId) returns (bytes32) {
        return draws[drawId].revealed[participant];
    }
}
