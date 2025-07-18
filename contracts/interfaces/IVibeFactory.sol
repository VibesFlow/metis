// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVibeFactory
 * Defines all external functions, structs, and events that other contracts can interact with.
 */
interface IVibeFactory {
    // --- Structs ---
    // The core data structure for a Vibestream, returned by getVibestream().
    struct VibeData {
        address creator;
        uint256 startDate;
        string mode;           // 'solo' or 'group'
        bool storeToFilecoin;
        uint256 distance;      // for group mode (1-10 meters)
        string metadataURI;
        address vibeKioskAddress;
        bool finalized;
    }

    // --- Events ---
    event VibestreamCreated(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 startDate,
        string mode,
        string metadataURI,
        address vibeKioskAddress
    );
    event MetadataUpdated(uint256 indexed vibeId, string newMetadataURI);
    event VibestreamFinalized(uint256 indexed vibeId);

    // --- Core Functions ---

    /**
     * @dev Creates a new RTA NFT Vibestream.
     */
    function createVibestream(
        address creator,
        uint256 startDate,
        string calldata mode,           // 'solo' or 'group'
        bool storeToFilecoin,
        uint256 distance,      // for group mode (1-10 meters)
        string calldata metadataURI,
        address vibeKioskAddress,
        bool finalized
    ) external returns (uint256 vibeId);

    /**
     * @dev Creates a new RTA NFT Vibestream for a specific creator.
     */
    function createVibestreamForCreator(
        address creator,
        uint256 startDate,
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId);

    // --- State-Changing Functions (Callable only by VibeManager) ---

    /**
     * @dev Allows the authorized VibeManager to update the metadata URI.
     */
    function setMetadataURI(uint256 vibeId, string memory newMetadataURI) external;


    /**
     * @dev Allows the authorized VibeManager to finalize a Vibestream.
     */
    function finalized(uint256 vibeId) external;

    // --- View Functions ---

    /**
     * @dev Retrieves the complete data for a specific Vibestream.
     */
    function getVibestream(uint256 vibeId) external view returns (VibeData memory);

    /**
     * @dev Returns the VibetKiosk address for a specific Vibestream.
     */
    function getVibeKiosk(uint256 vibeId) external view returns (address);

    /**
     * @dev Returns all VibeKiosk addresses and their corresponding Vibestream IDs.
     */
    function getAllVibeKiosks() external view returns (uint256[] memory vibeIds, address[] memory kioskAddresses);

    /**
     * @dev Returns the owner of the specified RTA NFT. From ERC721.
     */
    function ownerOf(uint256 vibeId) external view returns (address);
}