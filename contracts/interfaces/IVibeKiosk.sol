// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IVibeKiosk is IERC721 {
    
    function purchaseTicket() external payable returns (uint256 ticketId);
    
    function getTicketInfo(uint256 ticketId) external view returns (
        uint256 vibeId,
        address owner,
        address originalOwner,
        uint256 purchasePrice,
        uint256 purchaseTimestamp,
        string memory name,
        string memory title,
        string memory metadataURI,
        uint256 ticketNumber,
        uint256 totalTickets
    );
    
    function getUserTickets(address user) external view returns (uint256[] memory);
    
    function hasTicketForVibestream(address user, uint256 vibeId) external view returns (bool);
    
    function getSalesInfo() external view returns (
        uint256 totalTickets,
        uint256 soldTickets,
        uint256 remainingTickets,
        uint256 price,
        string memory title
    );
    
    function getVibeMetadata() external view returns (string memory);
    
    function updateMetadata(string memory newMetadataURI) external;
    
    function totalSupply() external view returns (uint256);
    
    function isAvailable() external view returns (bool);
} 