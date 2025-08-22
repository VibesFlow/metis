// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VibeKiosk
 * @dev Simplified standalone contract for vibestream tickets
 * Simple mapping-based system without complex cross-contract calls
 */
contract VibeKiosk is ERC721, ERC721URIStorage, ReentrancyGuard, Ownable {
    
    // Simple ticket configuration
    struct TicketConfig {
        uint256 vibeId;
        address creator;
        uint256 ticketsAmount;
        uint256 ticketPrice;
        uint256 distance;
        uint256 ticketsSold;
        bool isActive;
    }

    // Ticket data
    struct TicketData {
        uint256 vibeId;
        uint256 ticketId;
        address originalOwner;
        uint256 purchasePrice;
        uint256 purchaseTimestamp;
        uint256 ticketNumber;
    }

    // State variables
    address public vibeFactory;
    address public treasuryReceiver;
    uint256 public currentTicketId;

    // Simple mappings
    mapping(uint256 => TicketConfig) public vibeConfigs;
    mapping(uint256 => TicketData) public tickets;
    mapping(address => uint256[]) public userTickets;
    mapping(uint256 => mapping(address => bool)) public hasTicketForVibe;
    mapping(uint256 => uint256[]) public vibeTickets;

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
        uint256 price
    );

    modifier onlyVibeFactory() {
        require(msg.sender == vibeFactory, "Only VibeFactory can call this");
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
        
        vibeFactory = _vibeFactory;
        treasuryReceiver = _treasuryReceiver;
        currentTicketId = 1;
    }

    /**
     * @dev Register a vibestream for ticket sales
     * Simple registration without cross-contract calls
     */
    function registerVibestream(
        uint256 vibeId,
        address creator,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        uint256 distance
    ) external onlyVibeFactory {
        require(creator != address(0), "Invalid creator address");
        require(ticketsAmount > 0, "Must have at least 1 ticket");
        require(!vibeConfigs[vibeId].isActive, "Vibestream already registered");

        // Simple registration with creator passed from VibeFactory
        vibeConfigs[vibeId] = TicketConfig({
            vibeId: vibeId,
            creator: creator,
            ticketsAmount: ticketsAmount,
            ticketPrice: ticketPrice,
            distance: distance,
            ticketsSold: 0,
            isActive: true
        });

        emit VibestreamRegistered(vibeId, creator, ticketsAmount, ticketPrice, distance);
    }

    /**
     * @dev Purchase a ticket for a specific vibestream
     */
    function purchaseTicket(uint256 vibeId) external payable nonReentrant validVibeId(vibeId) returns (uint256 ticketId) {
        TicketConfig storage config = vibeConfigs[vibeId];
        require(config.ticketsSold < config.ticketsAmount, "All tickets sold");
        require(msg.value >= config.ticketPrice, "Insufficient payment");

        ticketId = currentTicketId++;
        
        // Simple token URI
        string memory tokenUri = string(abi.encodePacked("vibestream-", _toString(vibeId), "-ticket-", _toString(ticketId)));
        
        // Mint NFT ticket
        _mint(msg.sender, ticketId);
        _setTokenURI(ticketId, tokenUri);
        
        // Store ticket data
        tickets[ticketId] = TicketData({
            vibeId: vibeId,
            ticketId: ticketId,
            originalOwner: msg.sender,
            purchasePrice: config.ticketPrice,
            purchaseTimestamp: block.timestamp,
            ticketNumber: config.ticketsSold + 1
        });
        
        // Update mappings
        userTickets[msg.sender].push(ticketId);
        hasTicketForVibe[vibeId][msg.sender] = true;
        vibeTickets[vibeId].push(ticketId);
        config.ticketsSold++;
        
        // Simple revenue distribution: 80% creator, 20% treasury
        if (config.ticketPrice > 0) {
            uint256 creatorShare = (config.ticketPrice * 80) / 100;
            uint256 treasuryShare = config.ticketPrice - creatorShare;
            
            if (creatorShare > 0) {
                payable(config.creator).transfer(creatorShare);
            }
            if (treasuryShare > 0) {
                payable(treasuryReceiver).transfer(treasuryShare);
            }
        }
        
        // Refund excess payment
        if (msg.value > config.ticketPrice) {
            payable(msg.sender).transfer(msg.value - config.ticketPrice);
        }
        
        emit TicketMinted(vibeId, ticketId, msg.sender, config.ticketPrice);
        return ticketId;
    }

    /**
     * @dev Get vibestream ticket configuration
     */
    function getVibeConfig(uint256 vibeId) external view returns (TicketConfig memory) {
        return vibeConfigs[vibeId];
    }

    /**
     * @dev Check if user has ticket for specific vibestream
     */
    function hasTicketForVibestream(address user, uint256 vibeId) external view returns (bool) {
        return hasTicketForVibe[vibeId][user];
    }

    /**
     * @dev Get user's tickets for a specific vibestream
     */
    function getUserTicketsForVibe(address user, uint256 vibeId) external view returns (uint256[] memory) {
        uint256[] storage allUserTickets = userTickets[user];
        uint256 count = 0;
        
        for (uint256 i = 0; i < allUserTickets.length; i++) {
            if (tickets[allUserTickets[i]].vibeId == vibeId) {
                count++;
            }
        }
        
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
            string(abi.encodePacked("vibestream", _toString(ticket.vibeId), "_ticket", _toString(ticketId))),
            config.distance,
            tokenURI(ticketId),
            ticket.ticketNumber,
            config.ticketsAmount
        );
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
     * @dev Update configuration (only owner)
     */
    function updateVibeFactory(address _vibeFactory) external onlyOwner {
        require(_vibeFactory != address(0), "Invalid VibeFactory address");
        vibeFactory = _vibeFactory;
    }

    function updateTreasuryReceiver(address _treasuryReceiver) external onlyOwner {
        require(_treasuryReceiver != address(0), "Invalid treasury receiver");
        treasuryReceiver = _treasuryReceiver;
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