// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVibeFactory
 * Defines all external functions, structs, and events for the simplified VibeFactory contract.
 * Features integrated delegation management and standalone VibeKiosk architecture.
 */
interface IVibeFactory {
    // --- Structs ---
    // The core data structure for a Vibestream, returned by getVibestream().
    struct VibeData {
        address creator;
        uint256 startDate;
        string mode;
        bool storeToFilecoin;
        uint256 distance;
        string metadataURI;
        uint256 ticketsAmount;
        uint256 ticketPrice;
        bool finalized;
    }

    // --- Events ---
    event VibestreamCreated(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 timestamp,
        string mode,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        address requestedDelegatee
    );

    event DelegateSet(uint256 indexed vibeId, address indexed delegatee);
    event AuthorizedAddressAdded(address indexed newAddress);
    event AuthorizedAddressRemoved(address indexed removedAddress);
    event ProxyAdminUpdated(address indexed newProxyAdmin);

    // --- Core Functions ---

    /**
     * @dev Creates a new RTA NFT Vibestream.
     */
    function createVibestream(
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId);

    /**
     * @dev Creates a vibestream and sets up delegation in one transaction.
     * This replaces the need for RTAWrapper.sol
     */
    function createVibestreamWithDelegate(
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        address delegatee
    ) external returns (uint256 vibeId);

    /**
     * @dev Creates a new RTA NFT Vibestream for a specific creator.
     */
    function createVibestreamForCreator(
        address creator,
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId);

    // --- ProxyAdmin-Only Delegation Functions ---

    /**
     * @dev Sets a delegate for a specific vibestream (ProxyAdmin only).
     */
    function setDelegate(uint256 vibeId, address delegatee) external;

    /**
     * @dev Removes a delegate for a specific vibestream (ProxyAdmin only).
     */
    function removeDelegate(uint256 vibeId) external;

    // --- State-Changing Functions ---

    /**
     * @dev Updates the metadata URI for a vibestream.
     */
    function setMetadataURI(uint256 vibeId, string calldata newMetadataURI) external;

    /**
     * @dev Finalizes a Vibestream.
     */
    function setFinalized(uint256 vibeId) external;

    // --- Configuration Functions ---

    /**
     * @dev Sets the standalone VibeKiosk contract address.
     */
    function setVibeKiosk(address _vibeKiosk) external;

    /**
     * @dev Adds an authorized address to the global whitelist (ProxyAdmin or owner).
     */
    function addAuthorizedAddress(address _address) external;

    /**
     * @dev Removes an authorized address from the global whitelist (ProxyAdmin or owner).
     */
    function removeAuthorizedAddress(address _address) external;

    /**
     * @dev Sets the ProxyAdmin address (owner only).
     */
    function setProxyAdmin(address _proxyAdmin) external;

    // --- View Functions ---

    /**
     * @dev Retrieves the complete data for a specific Vibestream.
     */
    function getVibestream(uint256 vibeId) external view returns (VibeData memory);

    /**
     * @dev Returns whether a vibestream is finalized.
     */
    function isFinalized(uint256 vibeId) external view returns (bool);

    /**
     * @dev Returns the delegate for a specific vibestream.
     */
    function getDelegate(uint256 vibeId) external view returns (address);

    /**
     * @dev Checks if an address is authorized.
     */
    function isAuthorized(address _address) external view returns (bool);

    /**
     * @dev Returns the owner of the specified RTA NFT. From ERC721.
     */
    function ownerOf(uint256 vibeId) external view returns (address);

    /**
     * @dev Returns the token URI for the specified RTA NFT. From ERC721URIStorage.
     */
    function tokenURI(uint256 vibeId) external view returns (string memory);

    /**
     * @dev Returns the current vibestream counter.
     */
    function currentVibeId() external view returns (uint256);

    /**
     * @dev Returns the treasury receiver address.
     */
    function treasuryReceiver() external view returns (address);

    /**
     * @dev Returns the ProxyAdmin address.
     */
    function proxyAdmin() external view returns (address);

    /**
     * @dev Returns the standalone VibeKiosk contract address.
     */
    function vibeKiosk() external view returns (address);
}