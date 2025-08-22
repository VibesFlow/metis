// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title IVibeKiosk
 * @dev Interface for standalone VibeKiosk that manages tickets for ALL vibestreams
 */
interface IVibeKiosk is IERC721 {
    
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
    
    // Core Functions
    function registerVibestream(
        uint256 vibeId,
        address creator,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        uint256 distance
    ) external;
    
    function purchaseTicket(uint256 vibeId) external payable returns (uint256 ticketId);
    
    // View Functions
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
    );

    function getVibeConfig(uint256 vibeId) external view returns (TicketConfig memory);
    
    function getUserTicketsForVibe(address user, uint256 vibeId) external view returns (uint256[] memory);
    
    function getUserTickets(address user) external view returns (uint256[] memory);
    
    function hasTicketForVibestream(address user, uint256 vibeId) external view returns (bool);
    
    function getSalesInfo(uint256 vibeId) external view returns (
        uint256 totalTickets,
        uint256 soldTickets,
        uint256 remainingTickets,
        uint256 price,
        uint256 distance
    );

    function getVibeTickets(uint256 vibeId) external view returns (uint256[] memory);
    
    function isAvailable(uint256 vibeId) external view returns (bool);

    // Configuration Functions
    function updateVibeFactory(address _vibeFactory) external;
    function updateTreasuryReceiver(address _treasuryReceiver) external;
    function deactivateVibestream(uint256 vibeId) external;
} 