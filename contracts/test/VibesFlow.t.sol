// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VibeFactory.sol";
import "../src/VibeKiosk.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title VibesFlow Test Suite
 * @dev Comprehensive tests for simplified VibesFlow contracts
 * Tests: VibeFactory with integrated delegation + standalone VibeKiosk + ProxyAdmin
 */
contract VibesFlowTest is Test {
    // Test contracts
    VibeFactory public vibeFactory;
    VibeKiosk public vibeKiosk;
    ProxyAdmin public proxyAdmin;
    
    // Test addresses
    address public owner;
    address public creator;
    address public delegatee;
    address public treasury;
    address public ticketBuyer;
    
    // Test constants
    uint256 public constant DEFAULT_START_DATE = 1785000000; // Future timestamp
    string public constant DEFAULT_METADATA = "ipfs://vibesflow/test";
    uint256 public constant DEFAULT_TICKET_PRICE = 100000000000000000; // 0.1 ETH

    function setUp() public {
        // Set up test addresses
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        delegatee = makeAddr("delegatee");
        treasury = makeAddr("treasury");
        ticketBuyer = makeAddr("ticketBuyer");
        
        vm.startPrank(owner);
        
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);
        
        // Deploy VibeFactory
        vibeFactory = new VibeFactory(owner, treasury);
        
        // Deploy standalone VibeKiosk
        vibeKiosk = new VibeKiosk(address(vibeFactory), treasury, owner);
        
        // Configure contracts
        vibeFactory.setProxyAdmin(address(proxyAdmin));
        vibeFactory.setVibeKiosk(address(vibeKiosk));
        
        vm.stopPrank();

        // Give test addresses some ETH for ticket purchases
        vm.deal(ticketBuyer, 10 ether);
        vm.deal(creator, 1 ether);
    }

    function testSoloModeVibestream() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "solo",
            true,
            1, // Distance doesn't matter for solo mode
            "ipfs://QmSoloHash",
            0, // No tickets in solo mode
            0  // No ticket price in solo mode
        );
        
        // Get vibestream data
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        
        // Verify vibestream was created correctly
        assertEq(vibeData.creator, creator);
        assertEq(vibeData.mode, "solo");
        assertEq(vibeData.distance, 1);
        assertEq(vibeData.metadataURI, "ipfs://QmSoloHash");
        assertEq(vibeData.ticketsAmount, 0);
        assertEq(vibeData.ticketPrice, 0);
        assertFalse(vibeData.finalized);
        
        // Verify NFT ownership
        assertEq(vibeFactory.ownerOf(vibeId), creator);
        
        vm.stopPrank();
    }

    function testGroupModeZeroTickets() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5, // Distance for group mode
            "ipfs://QmGroupZeroTicketsHash",
            0, // Zero tickets - should not register with VibeKiosk
            DEFAULT_TICKET_PRICE
        );
        
        // Get vibestream data
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        
        // Verify vibestream was created correctly
        assertEq(vibeData.creator, creator);
        assertEq(vibeData.mode, "group");
        assertEq(vibeData.distance, 5);
        assertEq(vibeData.metadataURI, "ipfs://QmGroupZeroTicketsHash");
        assertEq(vibeData.ticketsAmount, 0);
        assertEq(vibeData.ticketPrice, DEFAULT_TICKET_PRICE);
        assertFalse(vibeData.finalized);
        
        vm.stopPrank();
    }

    function testGroupModeWithTickets() public {
        vm.startPrank(creator);
        
        // Create a group vibestream with tickets
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            100, // Tickets amount >= 1
            DEFAULT_TICKET_PRICE
        );
        
        // Verify vibestream was created
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.creator, creator);
        assertEq(vibeData.mode, "group");
        assertEq(vibeData.ticketsAmount, 100);
        
        // Verify VibeKiosk was notified and registered the vibestream
        // Note: We can't directly check this without exposing internal state
        // But we can test ticket purchasing to verify registration worked
        
        vm.stopPrank();
    }

    function testCreateVibestreamWithDelegate() public {
        vm.startPrank(creator);
        
        // Test integrated creation + delegation function
        uint256 vibeId = vibeFactory.createVibestreamWithDelegate(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            50, // Tickets
            DEFAULT_TICKET_PRICE,
            delegatee // Delegate to this address
        );
        
        // Verify vibestream was created
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.creator, creator);
        assertEq(vibeData.mode, "group");
        assertEq(vibeData.ticketsAmount, 50);
        
        // Verify delegation was set
        address currentDelegate = vibeFactory.getDelegate(vibeId);
        assertEq(currentDelegate, delegatee);
        
        vm.stopPrank();
    }

    function testDelegationManagement() public {
        vm.startPrank(creator);
        
        // Create a vibestream
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            25,
            DEFAULT_TICKET_PRICE
        );
        
        vm.stopPrank();
        
        // Switch to proxyAdmin owner to set delegation (owner is the ProxyAdmin owner)
        vm.startPrank(owner);
        
        vibeFactory.setDelegate(vibeId, delegatee);
        
        // Verify delegation was created
        address currentDelegate = vibeFactory.getDelegate(vibeId);
        assertEq(currentDelegate, delegatee);
        
        // Test removing delegation
        vibeFactory.removeDelegate(vibeId);
        currentDelegate = vibeFactory.getDelegate(vibeId);
        assertEq(currentDelegate, address(0));
        
        vm.stopPrank();
    }

    function testMetadataUpdateByCreator() public {
        vm.startPrank(creator);
        
        // Create vibestream
        uint256 vibeId = vibeFactory.createVibestream(
            "solo",
            true,
            1,
            DEFAULT_METADATA,
            0,
            0
        );
        
        // Creator should be able to update their own vibestream metadata
        string memory newMetadata = "ipfs://vibesflow/updated";
        vibeFactory.setMetadataURI(vibeId, newMetadata);
        
        // Verify metadata was updated
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.metadataURI, newMetadata);
        
        vm.stopPrank();
    }

    function testMetadataUpdateByDelegatee() public {
        vm.startPrank(creator);
        
        // Create vibestream with delegation
        uint256 vibeId = vibeFactory.createVibestreamWithDelegate(
            "solo",
            true,
            1,
            DEFAULT_METADATA,
            0,
            0,
            delegatee
        );
        
        vm.stopPrank();
        
        // Switch to delegatee to update metadata
        vm.startPrank(delegatee);
        
        string memory newMetadata = "ipfs://vibesflow/delegated_update";
        vibeFactory.setMetadataURI(vibeId, newMetadata);
        
        // Verify metadata was updated
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.metadataURI, newMetadata);
        
        vm.stopPrank();
    }

    function testFinalizationByCreator() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "solo",
            true,
            1,
            DEFAULT_METADATA,
            0,
            0
        );
        
        // Creator should be able to finalize their own vibestream
        vibeFactory.setFinalized(vibeId);
        
        // Verify vibestream was finalized
        assertTrue(vibeFactory.isFinalized(vibeId));
        
        vm.stopPrank();
    }

    function testTicketPurchase() public {
        vm.startPrank(creator);
        
        // Create a vibestream with tickets
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10, // 10 tickets available
            DEFAULT_TICKET_PRICE
        );
        
        vm.stopPrank();
        
        // Purchase a ticket
        vm.startPrank(ticketBuyer);
        
        uint256 ticketId = vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}(vibeId);
        
        // Verify ticket was minted
        assertEq(vibeKiosk.ownerOf(ticketId), ticketBuyer);
        
        // Verify ticket info
        (
            uint256 returnedVibeId,
            address ticketOwner,
            address originalOwner,
            uint256 purchasePrice,
            ,
            string memory ticketName,
            ,
            ,
            uint256 ticketNumber,
            uint256 totalTickets
        ) = vibeKiosk.getTicketInfo(ticketId);
        
        assertEq(returnedVibeId, vibeId);
        assertEq(ticketOwner, ticketBuyer);
        assertEq(originalOwner, ticketBuyer);
        assertEq(purchasePrice, DEFAULT_TICKET_PRICE);
        assertEq(ticketNumber, 1); // First ticket
        assertEq(totalTickets, 10);
        
        // Verify user has ticket for this vibestream
        assertTrue(vibeKiosk.hasTicketForVibestream(ticketBuyer, vibeId));
        
        vm.stopPrank();
    }

    function testMultipleTicketPurchases() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            5, // 5 tickets available
            DEFAULT_TICKET_PRICE
        );
        
        vm.stopPrank();
        
        // Purchase multiple tickets
        vm.startPrank(ticketBuyer);
        
        uint256 ticket1 = vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}(vibeId);
        uint256 ticket2 = vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}(vibeId);
        
        // Verify both tickets exist and are owned by buyer
        assertEq(vibeKiosk.ownerOf(ticket1), ticketBuyer);
        assertEq(vibeKiosk.ownerOf(ticket2), ticketBuyer);
        
        // Verify user's tickets for this vibestream
        uint256[] memory userTickets = vibeKiosk.getUserTicketsForVibe(ticketBuyer, vibeId);
        assertEq(userTickets.length, 2);
        assertEq(userTickets[0], ticket1);
        assertEq(userTickets[1], ticket2);
        
        vm.stopPrank();
    }

    function testSalesInfo() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE
        );
        
        vm.stopPrank();
        
        // Check initial sales info
        (
            uint256 totalTickets,
            uint256 soldTickets,
            uint256 remainingTickets,
            uint256 price,
            uint256 distance
        ) = vibeKiosk.getSalesInfo(vibeId);
        
        assertEq(totalTickets, 10);
        assertEq(soldTickets, 0);
        assertEq(remainingTickets, 10);
        assertEq(price, DEFAULT_TICKET_PRICE);
        assertEq(distance, 5);
        
        // Purchase a ticket and check updated sales info
        vm.startPrank(ticketBuyer);
        vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}(vibeId);
        vm.stopPrank();
        
        (totalTickets, soldTickets, remainingTickets, price, distance) = vibeKiosk.getSalesInfo(vibeId);
        
        assertEq(totalTickets, 10);
        assertEq(soldTickets, 1);
        assertEq(remainingTickets, 9);
    }

    function testUnauthorizedAccess() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "solo",
            true,
            1,
            DEFAULT_METADATA,
            0,
            0
        );
        
        vm.stopPrank();
        
        // Try to update metadata without authorization (should fail)
        vm.startPrank(makeAddr("unauthorized"));
        
        vm.expectRevert();
        vibeFactory.setMetadataURI(vibeId, "ipfs://unauthorized");
        
        vm.expectRevert();
        vibeFactory.setFinalized(vibeId);
        
        vm.stopPrank();
    }

    function testAuthorizationManagement() public {
        address newAuthorizedAddress = makeAddr("newAuth");
        
        vm.startPrank(owner);
        
        // Test adding authorized address
        vibeFactory.addAuthorizedAddress(newAuthorizedAddress);
        assertTrue(vibeFactory.isAuthorized(newAuthorizedAddress));
        
        // Test removing authorized address
        vibeFactory.removeAuthorizedAddress(newAuthorizedAddress);
        assertFalse(vibeFactory.isAuthorized(newAuthorizedAddress));
        
        vm.stopPrank();
    }

    function testRevenueDistribution() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            1, // Only 1 ticket
            1 ether // 1 ETH ticket price
        );
        
        vm.stopPrank();
        
        // Record initial balances
        uint256 creatorBalanceBefore = creator.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Purchase ticket
        vm.startPrank(ticketBuyer);
        vibeKiosk.purchaseTicket{value: 1 ether}(vibeId);
        vm.stopPrank();
        
        // Verify revenue distribution (80% creator, 20% treasury)
        uint256 creatorBalanceAfter = creator.balance;
        uint256 treasuryBalanceAfter = treasury.balance;
        
        assertEq(creatorBalanceAfter - creatorBalanceBefore, 0.8 ether);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, 0.2 ether);
    }
}