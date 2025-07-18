// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./VibeKiosk.sol";
import "../interfaces/IDistributor.sol";
import "../interfaces/IVibeManager.sol";

/**
 * @title VibeFactory
 * @dev A lightweight, modular ERC721 NFT factory for RTA Vibestreams.
 * Responsibilities:
 * 1. Mint Vibestream NFTs (ERC721).
 * 2. Deploy a unique VibeKiosk for each Vibestream.
 * 3. Act as a central registry linking vibeId to its data and associated contracts.
 * All other logic (Subscription, Pay-Per-Stream, Vibe Management) is handled by standalone contracts.
 */
contract VibeFactory is ERC721URIStorage, Ownable {
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

    // State variables
    mapping(uint256 => VibeData) public vibestreams;
    mapping(address => uint256[]) public creatorVibestreams;
    
    uint256 public currentVibeId;

    // Contract addresses
    address public vibeManagerContract;
    address public distributorContract;
    address public treasuryReceiver;

    // Events
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
    
    // Custom errors
    error InvalidInput();
    error DeploymentFailed();
    error OnlyVibeManager();
    error VibestreamAlreadyFinalized();
    error StartDateHasPassed();

    /**
     * @dev Constructor that initializes the contract
     */
    constructor() ERC721("Vibestream", "RTA") Ownable(msg.sender) {
        // Initialize with deployer as owner initially
        // The actual owner will be set during deployment
    }

    /**
     * @dev Initializes the contract addresses after deployment
     */
    function initialize(
        address _owner,
        address _vibeManager,
        address _distributor,
        address _treasuryReceiver
    ) external {
        // Only allow initialization once and only by the current owner
        require(vibeManagerContract == address(0), "Already initialized");
        require(msg.sender == owner(), "Only owner can initialize");
        
        vibeManagerContract = _vibeManager;
        distributorContract = _distributor;
        treasuryReceiver = _treasuryReceiver;
        
        // Transfer ownership to the intended owner if different
        if (_owner != owner()) {
            _transferOwnership(_owner);
        }
    }

    /**
     * @dev Creates a new RTA NFT Vibestream and deploys its associated VibeKiosk.
     */
    function createVibestream(
        uint256 startDate,
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice
    ) external returns (uint256 vibeId) {
        return createVibestreamForCreator(
            msg.sender,
            startDate,
            mode,
            storeToFilecoin,
            distance,
            metadataURI,
            ticketsAmount,
            ticketPrice
        );
    }

    /**
     * @dev Creates a new RTA NFT vibestream for a specific creator and deploys its associated VibeKiosk.
     * This version allows specifying the creator address, useful for wrapper contracts.
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
    ) public returns (uint256 vibeId) {
        uint256 newVibeId = currentVibeId++;

        // 1. Mint Vibestream NFT to the creator
        _safeMint(creator, newVibeId);
        _setTokenURI(newVibeId, metadataURI);

        // 2. Deploy VibeKiosk for this vibestream using CREATE2 for a deterministic address
        address vibeKioskAddress = _deployVibeKiosk(newVibeId, creator, ticketsAmount, ticketPrice, mode);
        if (vibeKioskAddress == address(0)) revert DeploymentFailed();

        // 3. Store vibestream data
        vibestreams[newVibeId] = VibeData({
            creator: creator,
            startDate: startDate,
            mode: mode,
            storeToFilecoin: storeToFilecoin,
            distance: distance,
            metadataURI: metadataURI,
            vibeKioskAddress: vibeKioskAddress,
            finalized: false
        });

        creatorVibestreams[creator].push(newVibeId);

        // 4. Register the new Vibestream with the Distributor
        IDistributor(distributorContract).registerVibestream(newVibeId, creator);

        emit VibestreamCreated(newVibeId, creator, startDate, mode, metadataURI, vibeKioskAddress);
        
        return newVibeId;
    }

    // --- Functions callable only by VibeManager ---

    /**
     * @dev Allows the authorized VibeManager contract to update the metadata URI.
     * The VibeManager is responsible for handling all permission logic (e.g., only creator or delegate).
     */
    function setMetadataURI(uint256 vibeId, string memory newMetadataURI) external {
        if (msg.sender != vibeManagerContract) revert("Only VibeManager allowed");
        if (vibestreams[vibeId].finalized) revert("Vibestream already finalized");
        
        vibestreams[vibeId].metadataURI = newMetadataURI;
        _setTokenURI(vibeId, newMetadataURI);
        
        emit MetadataUpdated(vibeId, newMetadataURI);
    }

    /**
     * @dev Allows the authorized VibeManager contract to finalize a vibestream.
     */
    function setFinalized(uint256 vibeId) external {
        if (msg.sender != vibeManagerContract) revert("Only VibeManager allowed");
        if (vibestreams[vibeId].finalized) revert("Vibestream already finalized");

        vibestreams[vibeId].finalized = true;
        emit VibestreamFinalized(vibeId);
    }
    
    /**
     * @dev Returns the VibeKiosk address for a specific vibestream.
     */
    function getVibeKiosk(uint256 vibeId) external view returns (address) {
        return vibestreams[vibeId].vibeKioskAddress;
    }

    /**
     * @dev Returns all VibeKiosk addresses and their corresponding vibe IDs.
     */
    function getAllVibeKiosks() external view returns (uint256[] memory vibeIds, address[] memory kioskAddresses) {
        uint256 totalVibesCount = currentVibeId;
        vibeIds = new uint256[](totalVibesCount);
        kioskAddresses = new address[](totalVibesCount);
        
        for (uint256 i = 0; i < totalVibesCount; i++) {
            vibeIds[i] = i;
            kioskAddresses[i] = vibestreams[i].vibeKioskAddress;
        }
        
        return (vibeIds, kioskAddresses);
    }

    /**
     * @dev Returns the full data struct for a given vibestream.
     * For other contracts to easily get vibe data.
     */
    function getVibestream(uint256 vibeId) external view returns (VibeData memory) {
        return vibestreams[vibeId];
    }

    /**
     * @dev Returns the total number of vibestreams created.
     */
    function totalVibestreams() external view returns (uint256) {
        return currentVibeId;
    }

    /**
     * @dev Returns the vibestreams created by a specific creator.
     */
    function getCreatorVibestreams(address creator) external view returns (uint256[] memory) {
        return creatorVibestreams[creator];
    }

    /**
     * @dev Returns the addresses of the standalone contracts.
     */
    function getStandaloneContracts() external view returns (address, address, address) {
        return (vibeManagerContract, distributorContract, treasuryReceiver);
    }

    // Internal & View Functions
    function _deployVibeKiosk(
        uint256 vibeId,
        address creator,
        uint256 ticketsAmount, 
        uint256 ticketPrice,
        string memory mode
    ) internal returns (address) {
        bytes memory bytecode = abi.encodePacked(
            type(VibeKiosk).creationCode,
            abi.encode(
                vibeId,
                address(this),
                creator,
                ticketsAmount,
                ticketPrice,
                mode,
                treasuryReceiver
            )
        );
        bytes32 salt = keccak256(abi.encodePacked(vibeId, "vibekiosk"));
        return Create2.deploy(0, salt, bytecode);
    }

    function _baseURI() internal pure override returns (string memory) {
        return ""; // URIs are set individually
    }

    // Override required by Solidity for multiple inheritance
    function tokenURI(uint256 tokenId) public view override(ERC721URIStorage) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(ERC721URIStorage) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}