// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IVibeFactory.sol";

/**
 * @title VibeKiosk
 * @dev Standalone contract that manages tickets for ALL vibestreams
 * Uses mappings to track ticket configurations and sales per vibestream
 * Significantly reduces deployment costs and complexity
 */
contract VibeKiosk is ERC721, ERC721URIStorage, ReentrancyGuard, Ownable {
    
    // Structs
    struct TicketConfig {
        uint256 vibeId;
        address creator;
        uint256 ticketsAmount;
        uint256 ticketPrice;
        uint256 distance;
        uint256 ticketsSold;
        bool isActive;
    }

    struct TicketData {
        uint256 vibeId;
        uint256 ticketId;
        address originalOwner;
        uint256 purchasePrice;
        uint256 purchaseTimestamp;
        string name;
        uint256 ticketNumber;
    }

    // State variables
    IVibeFactory public vibeFactory;
    address public treasuryReceiver;
    uint256 public currentTicketId;

    // Mappings
    mapping(uint256 => TicketConfig) public vibeConfigs;        // vibeId => TicketConfig
    mapping(uint256 => TicketData) public tickets;             // ticketId => TicketData
    mapping(address => uint256[]) public userTickets;          // user => ticketIds[]
    mapping(uint256 => mapping(address => bool)) public hasTicketForVibe; // vibeId => user => hasTicket
    mapping(uint256 => uint256[]) public vibeTickets;          // vibeId => ticketIds[]

    // Events
    event VibestreamRegistered(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        uint256 distance
    );

    event TicketMinted(
        uint256 indexed vibeId,
        uint256 indexed ticketId,
        address indexed buyer,
        string ticketName,
        uint256 price
    );

    event RevenueDistributed(
        uint256 indexed vibeId,
        address indexed creator,
        address indexed treasury,
        uint256 creatorAmount,
        uint256 treasuryAmount
    );

    modifier onlyVibeFactory() {
        require(msg.sender == address(vibeFactory), "Only VibeFactory can call this");
        _;
    }

    modifier validVibeId(uint256 vibeId) {
        require(vibeConfigs[vibeId].isActive, "Vibestream not registered or inactive");
        _;
    }

    constructor(
        address _vibeFactory,
        address _treasuryReceiver,
        address _owner
    ) ERC721("VibesFlow Tickets", "VIBE-TIX") Ownable(_owner) {
        require(_vibeFactory != address(0), "Invalid VibeFactory address");
        require(_treasuryReceiver != address(0), "Invalid treasury receiver");
        
        vibeFactory = IVibeFactory(_vibeFactory);
        treasuryReceiver = _treasuryReceiver;
        currentTicketId = 1;
    }

    /**
     * @dev Register a vibestream for ticket sales
     * Called by VibeFactory when a vibestream with tickets is created
     */
    function registerVibestream(
        uint256 vibeId,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        uint256 distance
    ) external onlyVibeFactory {
        require(ticketsAmount > 0, "Must have at least 1 ticket");
        require(!vibeConfigs[vibeId].isActive, "Vibestream already registered");

        // Get vibestream data from VibeFactory
        IVibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        require(vibeData.creator != address(0), "Vibestream does not exist");

        // Register the vibestream
        vibeConfigs[vibeId] = TicketConfig({
            vibeId: vibeId,
            creator: vibeData.creator,
            ticketsAmount: ticketsAmount,
            ticketPrice: ticketPrice,
            distance: distance,
            ticketsSold: 0,
            isActive: true
        });

        emit VibestreamRegistered(vibeId, vibeData.creator, ticketsAmount, ticketPrice, distance);
    }

    /**
     * @dev Purchase a ticket for a specific vibestream
     */
    function purchaseTicket(uint256 vibeId) external payable nonReentrant validVibeId(vibeId) returns (uint256 ticketId) {
        TicketConfig storage config = vibeConfigs[vibeId];
        require(config.ticketsSold < config.ticketsAmount, "All tickets sold");
        require(msg.value >= config.ticketPrice, "Insufficient payment");

        ticketId = currentTicketId++;
        
        // Generate ticket name: vibestream{vibeId}_ticket{ticketId}
        string memory ticketName = string(abi.encodePacked(
            "vibestream",
            _toString(vibeId),
            "_ticket",
            _toString(ticketId)
        ));

        // Get metadata from VibeFactory
        string memory metadataURI = "";
        try vibeFactory.tokenURI(vibeId) returns (string memory uri) {
            metadataURI = uri;
        } catch {
            // Continue without metadata if call fails
        }
        
        // Mint NFT ticket
        _mint(msg.sender, ticketId);
        if (bytes(metadataURI).length > 0) {
            _setTokenURI(ticketId, metadataURI);
        }
        
        // Store ticket data
        tickets[ticketId] = TicketData({
            vibeId: vibeId,
            ticketId: ticketId,
            originalOwner: msg.sender,
            purchasePrice: config.ticketPrice,
            purchaseTimestamp: block.timestamp,
            name: ticketName,
            ticketNumber: config.ticketsSold + 1
        });
        
        // Update mappings
        userTickets[msg.sender].push(ticketId);
        hasTicketForVibe[vibeId][msg.sender] = true;
        vibeTickets[vibeId].push(ticketId);
        config.ticketsSold++;
        
        // Calculate and distribute revenue: 80% creator, 20% treasury
        uint256 totalRevenue = config.ticketPrice;
        uint256 creatorShare = (totalRevenue * 80) / 100;
        uint256 treasuryShare = totalRevenue - creatorShare;
        
        // Distribute revenue
        bool creatorSuccess = false;
        bool treasurySuccess = false;
        
        if (creatorShare > 0) {
            (creatorSuccess, ) = payable(config.creator).call{value: creatorShare}("");
        }
        
        if (treasuryShare > 0) {
            (treasurySuccess, ) = payable(treasuryReceiver).call{value: treasuryShare}("");
        }
        
        require(creatorSuccess || creatorShare == 0, "Creator payment failed");
        require(treasurySuccess || treasuryShare == 0, "Treasury payment failed");
        
        // Refund excess payment
        if (msg.value > config.ticketPrice) {
            payable(msg.sender).transfer(msg.value - config.ticketPrice);
        }
        
        emit TicketMinted(vibeId, ticketId, msg.sender, ticketName, config.ticketPrice);
        emit RevenueDistributed(vibeId, config.creator, treasuryReceiver, creatorShare, treasuryShare);
        
        return ticketId;
    }

    /**
     * @dev Get ticket information
     */
    function getTicketInfo(uint256 ticketId) external view returns (
        uint256 vibeId,
        address owner,
        address originalOwner,
        uint256 purchasePrice,
        uint256 purchaseTimestamp,
        string memory name,
        uint256 distance,
        string memory metadataURI,
        uint256 ticketNumber,
        uint256 totalTickets
    ) {
        require(_ownerOf(ticketId) != address(0), "Ticket does not exist");
        
        TicketData storage ticket = tickets[ticketId];
        TicketConfig storage config = vibeConfigs[ticket.vibeId];
        
        return (
            ticket.vibeId,
            ownerOf(ticketId),
            ticket.originalOwner,
            ticket.purchasePrice,
            ticket.purchaseTimestamp,
            ticket.name,
            config.distance,
            tokenURI(ticketId),
            ticket.ticketNumber,
            config.ticketsAmount
        );
    }

    /**
     * @dev Get vibestream ticket configuration
     */
    function getVibeConfig(uint256 vibeId) external view returns (TicketConfig memory) {
        return vibeConfigs[vibeId];
    }

    /**
     * @dev Get sales info for a vibestream
     */
    function getSalesInfo(uint256 vibeId) external view validVibeId(vibeId) returns (
        uint256 totalTickets,
        uint256 soldTickets,
        uint256 remainingTickets,
        uint256 price,
        uint256 distance
    ) {
        TicketConfig storage config = vibeConfigs[vibeId];
        return (
            config.ticketsAmount,
            config.ticketsSold,
            config.ticketsAmount - config.ticketsSold,
            config.ticketPrice,
            config.distance
        );
    }

    /**
     * @dev Get user's tickets for a specific vibestream
     */
    function getUserTicketsForVibe(address user, uint256 vibeId) external view returns (uint256[] memory) {
        uint256[] storage allUserTickets = userTickets[user];
        uint256 count = 0;
        
        // Count tickets for this vibestream
        for (uint256 i = 0; i < allUserTickets.length; i++) {
            if (tickets[allUserTickets[i]].vibeId == vibeId) {
                count++;
            }
        }
        
        // Create array with correct size
        uint256[] memory vibeUserTickets = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allUserTickets.length; i++) {
            if (tickets[allUserTickets[i]].vibeId == vibeId) {
                vibeUserTickets[index] = allUserTickets[i];
                index++;
            }
        }
        
        return vibeUserTickets;
    }

    /**
     * @dev Get all user's tickets
     */
    function getUserTickets(address user) external view returns (uint256[] memory) {
        return userTickets[user];
    }

    /**
     * @dev Check if user has ticket for specific vibestream
     */
    function hasTicketForVibestream(address user, uint256 vibeId) external view returns (bool) {
        return hasTicketForVibe[vibeId][user];
    }

    /**
     * @dev Get all tickets for a vibestream
     */
    function getVibeTickets(uint256 vibeId) external view returns (uint256[] memory) {
        return vibeTickets[vibeId];
    }

    /**
     * @dev Check if tickets are available for a vibestream
     */
    function isAvailable(uint256 vibeId) external view validVibeId(vibeId) returns (bool) {
        return vibeConfigs[vibeId].ticketsSold < vibeConfigs[vibeId].ticketsAmount;
    }

    /**
     * @dev Update configuration (only owner)
     */
    function updateVibeFactory(address _vibeFactory) external onlyOwner {
        require(_vibeFactory != address(0), "Invalid VibeFactory address");
        vibeFactory = IVibeFactory(_vibeFactory);
    }

    function updateTreasuryReceiver(address _treasuryReceiver) external onlyOwner {
        require(_treasuryReceiver != address(0), "Invalid treasury receiver");
        treasuryReceiver = _treasuryReceiver;
    }

    /**
     * @dev Deactivate a vibestream (emergency only)
     */
    function deactivateVibestream(uint256 vibeId) external onlyOwner {
        vibeConfigs[vibeId].isActive = false;
    }

    /**
     * @dev Helper function to convert uint to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Override required by Solidity for multiple inheritance
    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // Emergency functions
    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            (bool success, ) = payable(owner()).call{value: balance}("");
            require(success, "Emergency withdraw failed");
        }
    }
}