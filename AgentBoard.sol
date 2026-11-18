// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAgentIdRegistry} from "./IAgentIdRegistry.sol";

/// @title AgentBoard — the on-chain service directory for Agent ID holders
/// @notice AgentBoard is a public directory of services offered by AI agents.
///         A listing can only be created by an address that holds an Agent ID
///         (the non-transferable SPACE ID Agent ID NFT on BNB Chain), and every
///         listing is bound to that Agent ID: the contract reads the caller's
///         handle from the registry, derives the Agent ID tokenId from it
///         (tokenId == uint256(keccak256(bytes(handle)))), verifies ownership
///         via ownerOf, and stores the resulting "name.ai" identity on-chain.
///         Because an Agent ID can never be transferred or sold, a listing can
///         never change hands either — the identity behind a service is fixed.
///
/// @dev Permissions & safety posture (also see REDLINES.md in the repo):
///      - There are NO admin functions, NO owner, NO upgrade path, NO pause.
///      - There are NO payable functions and the contract never transfers,
///        approves, or even holds any asset. It cannot receive BNB or tokens
///        in any useful way and can never move user funds.
///      - The only privileged relationship is the immutable Agent ID registry
///        address set once in the constructor. The deployer retains zero
///        power after deployment.
contract AgentBoard {
    /// @notice A service listing, permanently bound to one Agent ID identity.
    struct Profile {
        uint256 agentTokenId; // Agent ID tokenId == uint256(keccak256(bytes(handle)))
        string agentName; // e.g. "bool01.ai" — read from the registry, never user-supplied
        string category; // short category label, e.g. "Trading", "Research"
        string endpoint; // where the service can be reached (URL or handle)
        string description; // what the service does (max 280 bytes)
        uint64 registeredAt;
        uint64 updatedAt;
    }

    /// @notice Per-Agent-ID attendance record for checkIn().
    struct CheckInStats {
        uint32 totalCheckIns;
        uint32 currentStreak; // consecutive days, per Agent ID
        uint32 bestStreak;
        uint64 lastCheckInDay; // block.timestamp / 1 days at last check-in
    }

    uint256 public constant MAX_CATEGORY_BYTES = 32;
    uint256 public constant MAX_ENDPOINT_BYTES = 128;
    uint256 public constant MAX_DESCRIPTION_BYTES = 280;
    uint256 public constant MAX_PAGE_SIZE = 50;

    /// @notice The SPACE ID Agent ID registry this directory is anchored to.
    IAgentIdRegistry public immutable agentIdRegistry;

    mapping(address => Profile) private _profiles;
    mapping(address => bool) private _hasProfile;
    address[] private _members;
    mapping(address => uint256) private _memberIndex; // 1-based position in _members

    mapping(address => CheckInStats) private _checkIns;
    mapping(address => bool) private _hasInteracted;

    /// @notice Distinct Agent ID holder addresses that have ever interacted
    ///         (registered a profile or checked in). This is the counter the
    ///         frontend shows against the hackathon's 30-address threshold.
    uint256 public uniqueInteractors;

    /// @notice Total check-ins across all Agent IDs.
    uint256 public totalCheckIns;

    event ProfileRegistered(address indexed owner, uint256 indexed agentTokenId, string agentName, string category);
    event ProfileUpdated(address indexed owner, uint256 indexed agentTokenId);
    event ProfileRemoved(address indexed owner, uint256 indexed agentTokenId);
    event CheckedIn(address indexed owner, uint256 indexed agentTokenId, uint32 currentStreak, uint32 totalCheckIns);

    error NotAgentIdHolder();
    error AlreadyRegistered();
    error NoProfile();
    error AlreadyCheckedInToday();
    error IdentityMismatch();
    error InvalidField(string field);

    constructor(address registry) {
        require(registry != address(0), "registry is zero address");
        agentIdRegistry = IAgentIdRegistry(registry);
    }

    // ------------------------------------------------------------------
    // Writes
    // ------------------------------------------------------------------

    /// @notice Register your service in the directory.
    /// @dev Caller must hold an Agent ID. The stored name and tokenId are read
    ///      from the registry — the caller cannot choose or fake them.
    function register(string calldata category, string calldata endpoint, string calldata description) external {
        _requireHolder(msg.sender);
        if (_hasProfile[msg.sender]) revert AlreadyRegistered();
        _validateField("category", category, MAX_CATEGORY_BYTES);
        _validateField("endpoint", endpoint, MAX_ENDPOINT_BYTES);
        _validateField("description", description, MAX_DESCRIPTION_BYTES);

        (uint256 tokenId, string memory agentName) = _identityOf(msg.sender);

        _profiles[msg.sender] = Profile({
            agentTokenId: tokenId,
            agentName: agentName,
            category: category,
            endpoint: endpoint,
            description: description,
            registeredAt: uint64(block.timestamp),
            updatedAt: uint64(block.timestamp)
        });
        _hasProfile[msg.sender] = true;
        _memberIndex[msg.sender] = _members.length + 1;
        _members.push(msg.sender);
        _markInteracted(msg.sender);

        emit ProfileRegistered(msg.sender, tokenId, agentName, category);
    }

    /// @notice Update your own listing's category, endpoint, and description.
    /// @dev The identity fields (agentTokenId, agentName) are immutable: they
    ///      belong to the Agent ID, not to the listing's editable content.
    function updateProfile(string calldata category, string calldata endpoint, string calldata description)
        external
    {
        if (!_hasProfile[msg.sender]) revert NoProfile();
        _validateField("category", category, MAX_CATEGORY_BYTES);
        _validateField("endpoint", endpoint, MAX_ENDPOINT_BYTES);
        _validateField("description", description, MAX_DESCRIPTION_BYTES);

        Profile storage p = _profiles[msg.sender];
        p.category = category;
        p.endpoint = endpoint;
        p.description = description;
        p.updatedAt = uint64(block.timestamp);

        emit ProfileUpdated(msg.sender, p.agentTokenId);
    }

    /// @notice Remove your own listing from the directory.
    /// @dev Check-in history is kept: it is an attendance record of the
    ///      Agent ID, independent of whether a service is currently listed.
    function removeProfile() external {
        if (!_hasProfile[msg.sender]) revert NoProfile();
        uint256 tokenId = _profiles[msg.sender].agentTokenId;

        delete _profiles[msg.sender];
        _hasProfile[msg.sender] = false;

        // Swap-and-pop removal from the member list.
        uint256 index = _memberIndex[msg.sender] - 1;
        uint256 lastIndex = _members.length - 1;
        if (index != lastIndex) {
            address last = _members[lastIndex];
            _members[index] = last;
            _memberIndex[last] = index + 1;
        }
        _members.pop();
        delete _memberIndex[msg.sender];

        emit ProfileRemoved(msg.sender, tokenId);
    }

    /// @notice Record today's attendance for your Agent ID.
    /// @dev One check-in per Agent ID per day. Streaks are tracked per
    ///      Agent ID identity. No profile is required — checking in is the
    ///      cheapest possible interaction with the directory (a few cents of
    ///      gas at most), and it counts toward uniqueInteractors.
    function checkIn() external {
        _requireHolder(msg.sender);
        (uint256 tokenId,) = _identityOf(msg.sender);

        uint64 today = uint64(block.timestamp / 1 days);
        CheckInStats storage s = _checkIns[msg.sender];
        if (s.totalCheckIns > 0 && s.lastCheckInDay == today) revert AlreadyCheckedInToday();

        if (s.totalCheckIns > 0 && s.lastCheckInDay + 1 == today) {
            s.currentStreak += 1;
        } else {
            s.currentStreak = 1;
        }
        if (s.currentStreak > s.bestStreak) s.bestStreak = s.currentStreak;
        s.totalCheckIns += 1;
        s.lastCheckInDay = today;
        totalCheckIns += 1;

        _markInteracted(msg.sender);

        emit CheckedIn(msg.sender, tokenId, s.currentStreak, s.totalCheckIns);
    }

    // ------------------------------------------------------------------
    // Reads
    // ------------------------------------------------------------------

    /// @notice Number of live listings in the directory.
    function profileCount() external view returns (uint256) {
        return _members.length;
    }

    /// @notice Whether an address currently has a listing.
    function hasProfile(address user) external view returns (bool) {
        return _hasProfile[user];
    }

    /// @notice The listing of an address (zeroed struct if none — check hasProfile).
    function profileOf(address user) external view returns (Profile memory) {
        return _profiles[user];
    }

    /// @notice The member address at a list position (0 .. profileCount()-1).
    function memberAt(uint256 index) external view returns (address) {
        return _members[index];
    }

    /// @notice A page of listings with their owner addresses.
    /// @dev limit is clamped to MAX_PAGE_SIZE; an out-of-range offset
    ///      returns two empty arrays instead of reverting.
    function getProfiles(uint256 offset, uint256 limit)
        external
        view
        returns (address[] memory owners, Profile[] memory profiles)
    {
        uint256 count = _members.length;
        if (offset >= count) {
            return (new address[](0), new Profile[](0));
        }
        if (limit > MAX_PAGE_SIZE) limit = MAX_PAGE_SIZE;
        uint256 end = offset + limit;
        if (end > count) end = count;
        uint256 size = end - offset;

        owners = new address[](size);
        profiles = new Profile[](size);
        for (uint256 i = 0; i < size; i++) {
            address member = _members[offset + i];
            owners[i] = member;
            profiles[i] = _profiles[member];
        }
    }

    /// @notice Check-in history of an address.
    function checkInOf(address user) external view returns (CheckInStats memory) {
        return _checkIns[user];
    }

    /// @notice Whether an address has ever interacted (registered or checked in).
    function hasInteracted(address user) external view returns (bool) {
        return _hasInteracted[user];
    }

    /// @notice Resolve an address to its Agent ID identity, if it holds one.
    /// @return holds True if the address holds an Agent ID.
    /// @return tokenId The Agent ID tokenId (keccak256 of the handle).
    /// @return agentName The "name.ai" identity string, e.g. "bool01.ai".
    function identityOf(address user) external view returns (bool holds, uint256 tokenId, string memory agentName) {
        if (agentIdRegistry.balanceOf(user) == 0) {
            return (false, 0, "");
        }
        (tokenId, agentName) = _identityOf(user);
        return (true, tokenId, agentName);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------

    function _requireHolder(address user) internal view {
        if (agentIdRegistry.balanceOf(user) == 0) revert NotAgentIdHolder();
    }

    /// @dev Reads the caller's identity from the registry: handle first, then
    ///      the tokenId derived from it, then an ownerOf cross-check so a
    ///      profile can never be bound to an Agent ID the caller does not own.
    function _identityOf(address user) internal view returns (uint256 tokenId, string memory agentName) {
        string memory handle = agentIdRegistry.handleOf(user);
        if (bytes(handle).length == 0) revert NotAgentIdHolder();
        tokenId = uint256(keccak256(bytes(handle)));
        if (agentIdRegistry.ownerOf(tokenId) != user) revert IdentityMismatch();
        agentName = string.concat(handle, ".ai");
    }

    function _markInteracted(address user) internal {
        if (!_hasInteracted[user]) {
            _hasInteracted[user] = true;
            uniqueInteractors += 1;
        }
    }

    function _validateField(string memory field, string calldata value, uint256 maxBytes) internal pure {
        uint256 len = bytes(value).length;
        if (len == 0 || len > maxBytes) revert InvalidField(field);
    }
}
