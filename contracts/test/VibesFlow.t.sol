// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/VibeFactory.sol";
import "../src/VibeKiosk.sol";
import "../src/PPM.sol";
import "../src/Subscriptions.sol";
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
    PPM public ppm;
    Subscriptions public subscriptions;
    ProxyAdmin public proxyAdmin;
    
    // Test addresses
    address public owner;
    address public creator;
    address public delegatee;
    address public treasury;
    address public ticketBuyer;
    address public participant1;
    address public participant2;
    address public subscriber1;
    address public subscriber2;
    address public subscriber3;
    
    // Test constants
    uint256 public constant DEFAULT_START_DATE = 1785000000; // Future timestamp
    string public constant DEFAULT_METADATA = "ipfs://vibesflow/test";
    uint256 public constant DEFAULT_TICKET_PRICE = 100000000000000000; // 0.1 ETH
    uint256 public constant DEFAULT_STREAM_PRICE = 50000000000000000; // 0.05 ETH per minute

    function setUp() public {
        // Set up test addresses
        owner = makeAddr("owner");
        creator = makeAddr("creator");
        delegatee = makeAddr("delegatee");
        treasury = makeAddr("treasury");
        ticketBuyer = makeAddr("ticketBuyer");
        participant1 = makeAddr("participant1");
        participant2 = makeAddr("participant2");
        subscriber1 = makeAddr("subscriber1");
        subscriber2 = makeAddr("subscriber2");
        subscriber3 = makeAddr("subscriber3");
        
        vm.startPrank(owner);
        
        // Deploy ProxyAdmin
        proxyAdmin = new ProxyAdmin(owner);
        
        // Deploy VibeFactory
        vibeFactory = new VibeFactory(owner, treasury);
        
        // Deploy standalone VibeKiosk
        vibeKiosk = new VibeKiosk(address(vibeFactory), treasury, owner);
        
        // Deploy PPM contract
        ppm = new PPM(owner, address(vibeFactory), treasury);
        
        // Deploy Subscriptions contract
        subscriptions = new Subscriptions(owner, treasury);
        
        // Configure contracts
        vibeFactory.setProxyAdmin(address(proxyAdmin));
        vibeFactory.setVibeKiosk(address(vibeKiosk));
        vibeFactory.setPPMContract(address(ppm));
        
        vm.stopPrank();

        // Give test addresses some ETH for ticket purchases and PPM allowances
        vm.deal(ticketBuyer, 10 ether);
        vm.deal(creator, 1 ether);
        vm.deal(participant1, 5 ether);
        vm.deal(participant2, 5 ether);
        vm.deal(subscriber1, 50 ether);
        vm.deal(subscriber2, 50 ether);
        vm.deal(subscriber3, 50 ether);
    }

    function testSoloModeVibestream() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "solo",
            true,
            1, // Distance doesn't matter for solo mode
            "ipfs://QmSoloHash",
            0, // No tickets in solo mode
            0, // No ticket price in solo mode
            false, // No pay-per-stream in solo mode
            0  // No stream price in solo mode
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            false, // No pay-per-stream
            0, // No stream price
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            0,
            false, // No pay-per-stream
            0 // No stream price
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
            false, // No pay-per-stream
            0, // No stream price
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
            0,
            false, // No pay-per-stream
            0 // No stream price
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
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
            0,
            false, // No pay-per-stream
            0 // No stream price
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
            1 ether, // 1 ETH ticket price
            false, // No pay-per-stream
            0 // No stream price
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

    // =============================================================================
    // PPM CONTRACT TESTS
    // =============================================================================

    function testPPMVibestreamRegistration() public {
        vm.startPrank(creator);
        
        // Create a pay-per-stream vibestream
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true, // Pay-per-stream enabled
            DEFAULT_STREAM_PRICE // 0.05 ETH per minute
        );
        
        vm.stopPrank();
        
        // Verify vibestream was registered with PPM
        assertTrue(ppm.isVibestreamRegistered(vibeId));
        
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.vibeId, vibeId);
        assertEq(config.creator, creator);
        assertEq(config.payPerMinute, DEFAULT_STREAM_PRICE);
        assertTrue(config.isActive);
        assertEq(config.totalParticipants, 0);
        assertEq(config.totalRevenue, 0);
    }

    function testPPMAllowanceAuthorization() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        // Participant authorizes spending
        vm.startPrank(participant1);
        
        uint256 allowanceAmount = 1 ether; // 1 tMETIS allowance
        ppm.authorizeSpending{value: allowanceAmount}(vibeId, allowanceAmount);
        
        // Verify allowance was set
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertEq(allowance.vibeId, vibeId);
        assertEq(allowance.participant, participant1);
        assertEq(allowance.authorizedAmount, allowanceAmount);
        assertEq(allowance.spentAmount, 0);
        assertEq(allowance.payPerMinute, DEFAULT_STREAM_PRICE);
        assertFalse(allowance.isActive);
        assertEq(allowance.creator, creator);
        
        // Verify remaining allowance
        assertEq(ppm.getRemainingAllowance(vibeId, participant1), allowanceAmount);
        
        vm.stopPrank();
    }

    function testPPMIncreaseAllowance() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        // Initial authorization
        uint256 initialAmount = 1 ether;
        ppm.authorizeSpending{value: initialAmount}(vibeId, initialAmount);
        
        // Increase allowance
        uint256 additionalAmount = 0.5 ether;
        ppm.increaseAllowance{value: additionalAmount}(vibeId, additionalAmount);
        
        // Verify increased allowance
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertEq(allowance.authorizedAmount, initialAmount + additionalAmount);
        assertEq(ppm.getRemainingAllowance(vibeId, participant1), initialAmount + additionalAmount);
        
        vm.stopPrank();
    }

    function testPPMJoinVibestream() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        // Authorize spending
        uint256 allowanceAmount = 1 ether;
        ppm.authorizeSpending{value: allowanceAmount}(vibeId, allowanceAmount);
        
        // Join vibestream
        ppm.joinVibestream(vibeId);
        
        // Verify participant joined
        assertTrue(ppm.isParticipantActive(vibeId, participant1));
        
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertTrue(allowance.isActive);
        assertGt(allowance.joinedAt, 0);
        assertGt(allowance.lastDeduction, 0);
        
        // Verify participant count updated
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalParticipants, 1);
        
        // Verify active participants list
        address[] memory activeParticipants = ppm.getActiveParticipants(vibeId);
        assertEq(activeParticipants.length, 1);
        assertEq(activeParticipants[0], participant1);
        
        vm.stopPrank();
    }

    function testPPMLeaveVibestream() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        // Authorize and join
        uint256 allowanceAmount = 1 ether;
        ppm.authorizeSpending{value: allowanceAmount}(vibeId, allowanceAmount);
        ppm.joinVibestream(vibeId);
        
        // Wait some time and leave
        vm.warp(block.timestamp + 65); // Wait 65 seconds
        ppm.leaveVibestream(vibeId);
        
        // Verify participant left
        assertFalse(ppm.isParticipantActive(vibeId, participant1));
        
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertFalse(allowance.isActive);
        
        // Verify payment was processed
        assertGt(allowance.spentAmount, 0);
        assertEq(allowance.spentAmount, DEFAULT_STREAM_PRICE); // 1 minute payment
        
        // Verify participant count updated
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalParticipants, 0);
        
        vm.stopPrank();
    }

    function testPPMPaymentProcessing() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        uint256 allowanceAmount = 1 ether;
        ppm.authorizeSpending{value: allowanceAmount}(vibeId, allowanceAmount);
        ppm.joinVibestream(vibeId);
        
        vm.stopPrank();
        
        // Record initial balances
        uint256 creatorBalanceBefore = creator.balance;
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Fast forward 65 seconds and process payment
        vm.warp(block.timestamp + 65);
        ppm.processParticipantPayment(vibeId, participant1);
        
        // Verify payment was processed
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertEq(allowance.spentAmount, DEFAULT_STREAM_PRICE);
        
        // Verify revenue distribution (80% creator, 20% treasury)
        uint256 creatorShare = (DEFAULT_STREAM_PRICE * 80) / 100;
        uint256 treasuryShare = DEFAULT_STREAM_PRICE - creatorShare;
        
        assertEq(creator.balance - creatorBalanceBefore, creatorShare);
        assertEq(treasury.balance - treasuryBalanceBefore, treasuryShare);
        
        // Verify total revenue tracking
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalRevenue, DEFAULT_STREAM_PRICE);
    }

    function testPPMMultipleParticipants() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        // Participant 1 joins
        vm.startPrank(participant1);
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        ppm.joinVibestream(vibeId);
        vm.stopPrank();
        
        // Participant 2 joins
        vm.startPrank(participant2);
        ppm.authorizeSpending{value: 2 ether}(vibeId, 2 ether);
        ppm.joinVibestream(vibeId);
        vm.stopPrank();
        
        // Verify both participants are active
        assertTrue(ppm.isParticipantActive(vibeId, participant1));
        assertTrue(ppm.isParticipantActive(vibeId, participant2));
        
        address[] memory activeParticipants = ppm.getActiveParticipants(vibeId);
        assertEq(activeParticipants.length, 2);
        
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalParticipants, 2);
        
        // Process payments for both
        vm.warp(block.timestamp + 65);
        ppm.processPayments(vibeId);
        
        // Verify both were charged
        assertEq(ppm.getParticipantAllowance(vibeId, participant1).spentAmount, DEFAULT_STREAM_PRICE);
        assertEq(ppm.getParticipantAllowance(vibeId, participant2).spentAmount, DEFAULT_STREAM_PRICE);
        
        // Verify total revenue
        config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalRevenue, DEFAULT_STREAM_PRICE * 2);
    }

    function testPPMInsufficientAllowance() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        // Authorize minimal allowance (less than 2 minutes)
        uint256 allowanceAmount = DEFAULT_STREAM_PRICE + (DEFAULT_STREAM_PRICE / 2); // 1.5 minutes worth
        ppm.authorizeSpending{value: allowanceAmount}(vibeId, allowanceAmount);
        ppm.joinVibestream(vibeId);
        
        vm.stopPrank();
        
        // Process payment after 1 minute - should work
        vm.warp(block.timestamp + 65);
        ppm.processParticipantPayment(vibeId, participant1);
        assertTrue(ppm.isParticipantActive(vibeId, participant1));
        
        // Process payment after another minute - should auto-remove participant
        vm.warp(block.timestamp + 130); // Total 130 seconds = 2+ minutes
        ppm.processParticipantPayment(vibeId, participant1);
        
        // Participant should be removed due to insufficient allowance
        assertFalse(ppm.isParticipantActive(vibeId, participant1));
        
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalParticipants, 0);
    }

    function testPPMEmergencyStop() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        ppm.joinVibestream(vibeId);
        vm.stopPrank();
        
        // Creator can emergency stop participant
        vm.startPrank(creator);
        ppm.emergencyStop(vibeId, participant1, "Test emergency stop");
        vm.stopPrank();
        
        // Verify participant was removed
        assertFalse(ppm.isParticipantActive(vibeId, participant1));
        
        IPPM.VibestreamConfig memory config = ppm.getVibestreamConfig(vibeId);
        assertEq(config.totalParticipants, 0);
    }

    function testPPMPauseUnpause() public {
        // First create a vibestream to test PPM operations
        vm.startPrank(creator);
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Test pause
        ppm.pause();
        
        vm.stopPrank();
        
        vm.startPrank(participant1);
        
        // PPM operations should revert when paused
        vm.expectRevert();
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        
        vm.stopPrank();
        
        // Unpause
        vm.startPrank(owner);
        ppm.unpause();
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(participant1);
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        
        // Verify allowance was set
        IPPM.ParticipantAllowance memory allowance = ppm.getParticipantAllowance(vibeId, participant1);
        assertEq(allowance.authorizedAmount, 1 ether);
        
        vm.stopPrank();
    }

    function testPPMFailures() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            true,
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
        
        // Test authorization failures
        vm.startPrank(participant1);
        
        // Should fail with zero amount
        vm.expectRevert("PPM: Authorized amount must be greater than 0");
        ppm.authorizeSpending{value: 0}(vibeId, 0);
        
        // Should fail with insufficient payment
        vm.expectRevert("PPM: Insufficient payment");
        ppm.authorizeSpending{value: 0.5 ether}(vibeId, 1 ether);
        
        // Should fail joining without allowance
        vm.expectRevert("PPM: No allowance authorized");
        ppm.joinVibestream(vibeId);
        
        // Authorize and join
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        ppm.joinVibestream(vibeId);
        
        // Should fail joining again
        vm.expectRevert("PPM: Already in vibestream");
        ppm.joinVibestream(vibeId);
        
        vm.stopPrank();
        
        // Test unauthorized access
        vm.startPrank(makeAddr("unauthorized"));
        
        vm.expectRevert("PPM: Not authorized for emergency stop");
        ppm.emergencyStop(vibeId, participant1, "Unauthorized");
        
        vm.stopPrank();
    }

    function testPPMOnlyPayPerStreamVibestreams() public {
        vm.startPrank(creator);
        
        // Create non-pay-per-stream vibestream
        uint256 vibeId = vibeFactory.createVibestream(
            "group",
            true,
            5,
            DEFAULT_METADATA,
            10,
            DEFAULT_TICKET_PRICE,
            false, // No pay-per-stream
            0 // No stream price
        );
        
        vm.stopPrank();
        
        // Should not be registered with PPM
        assertFalse(ppm.isVibestreamRegistered(vibeId));
        
        // Should fail to authorize spending for non-PPM vibestream
        vm.startPrank(participant1);
        vm.expectRevert("PPM: Vibestream not registered");
        ppm.authorizeSpending{value: 1 ether}(vibeId, 1 ether);
        vm.stopPrank();
    }

    function testPPMSoloModeRestriction() public {
        vm.startPrank(creator);
        
        // Should revert when trying to create solo mode with pay-per-stream
        vm.expectRevert("Pay-per-stream only available for group mode");
        vibeFactory.createVibestream(
            "solo",
            true,
            1,
            DEFAULT_METADATA,
            0,
            0,
            true, // Pay-per-stream not allowed for solo
            DEFAULT_STREAM_PRICE
        );
        
        vm.stopPrank();
    }

    function testPPMAdminFunctions() public {
        address newTreasury = makeAddr("newTreasury");
        address newVibeFactory = makeAddr("newVibeFactory");
        
        vm.startPrank(owner);
        
        // Test treasury receiver update
        ppm.setTreasuryReceiver(newTreasury);
        assertEq(ppm.treasuryReceiver(), newTreasury);
        
        // Test treasury fee update
        ppm.setTreasuryFeePercent(30);
        assertEq(ppm.treasuryFeePercent(), 30);
        
        // Test VibeFactory update
        ppm.setVibeFactory(newVibeFactory);
        assertEq(address(ppm.vibeFactory()), newVibeFactory);
        
        vm.stopPrank();
        
        // Test unauthorized access
        vm.startPrank(makeAddr("unauthorized"));
        
        vm.expectRevert();
        ppm.setTreasuryReceiver(newTreasury);
        
        vm.expectRevert();
        ppm.setTreasuryFeePercent(50);
        
        vm.expectRevert();
        ppm.setVibeFactory(newVibeFactory);
        
        vm.stopPrank();
    }

    // =============================================================================
    // SUBSCRIPTIONS CONTRACT TESTS
    // =============================================================================

    function testSubscriptionBasics() public {
        // Test initial state
        assertEq(subscriptions.getSubscriptionPrice(), 10 ether);
        assertEq(subscriptions.getSubscriptionDuration(), 30 days);
        assertEq(subscriptions.getActiveSubscriberCount(), 0);
        assertEq(subscriptions.getTotalRevenue(), 0);
        assertEq(subscriptions.treasuryReceiver(), treasury);
    }

    function testSuccessfulSubscription() public {
        vm.startPrank(subscriber1);
        
        // Subscribe with correct amount
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Verify subscription
        assertTrue(subscriptions.isSubscribed(subscriber1));
        assertEq(subscriptions.getActiveSubscriberCount(), 1);
        assertEq(subscriptions.getTotalRevenue(), subscriptionPrice);
        
        // Check subscription details
        ISubscriptions.Subscription memory sub = subscriptions.getSubscription(subscriber1);
        assertEq(sub.startTime, block.timestamp);
        assertEq(sub.endTime, block.timestamp + 30 days);
        assertEq(sub.amountPaid, subscriptionPrice);
        assertTrue(sub.isActive);
        assertEq(sub.renewalCount, 0);
        
        // Check time remaining
        assertEq(subscriptions.getTimeRemaining(subscriber1), 30 days);
        
        vm.stopPrank();
    }

    function testSubscriptionPaymentToTreasury() public {
        uint256 treasuryBalanceBefore = treasury.balance;
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Verify treasury received payment
        assertEq(treasury.balance - treasuryBalanceBefore, subscriptionPrice);
    }

    function testSubscriptionFailures() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Test insufficient payment
        vm.expectRevert("Subscriptions: Incorrect payment amount");
        subscriptions.subscribe{value: subscriptionPrice - 1}();
        
        // Test overpayment
        vm.expectRevert("Subscriptions: Incorrect payment amount");
        subscriptions.subscribe{value: subscriptionPrice + 1}();
        
        // Test zero payment
        vm.expectRevert("Subscriptions: Incorrect payment amount");
        subscriptions.subscribe{value: 0}();
        
        vm.stopPrank();
    }

    function testMultipleSubscribers() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        // First subscriber
        vm.startPrank(subscriber1);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Second subscriber
        vm.startPrank(subscriber2);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Third subscriber
        vm.startPrank(subscriber3);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Verify all are subscribed
        assertTrue(subscriptions.isSubscribed(subscriber1));
        assertTrue(subscriptions.isSubscribed(subscriber2));
        assertTrue(subscriptions.isSubscribed(subscriber3));
        
        assertEq(subscriptions.getActiveSubscriberCount(), 3);
        assertEq(subscriptions.getTotalRevenue(), subscriptionPrice * 3);
    }

    function testSubscriptionRenewal() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Initial subscription
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Fast forward 15 days (still active)
        vm.warp(block.timestamp + 15 days);
        
        // Renew subscription
        subscriptions.renewSubscription{value: subscriptionPrice}();
        
        // Should extend from original end time
        ISubscriptions.Subscription memory sub = subscriptions.getSubscription(subscriber1);
        assertEq(sub.endTime, block.timestamp - 15 days + 60 days); // Original 30 + new 30 - 15 elapsed
        assertEq(sub.amountPaid, subscriptionPrice * 2);
        assertEq(sub.renewalCount, 1);
        assertTrue(sub.isActive);
        
        vm.stopPrank();
    }

    function testExpiredSubscriptionRenewal() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Initial subscription
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 31 days);
        
        // Should be expired
        assertFalse(subscriptions.isSubscribed(subscriber1));
        assertTrue(subscriptions.hasExpiredSubscription(subscriber1));
        assertEq(subscriptions.getTimeRemaining(subscriber1), 0);
        
        // Renew expired subscription
        subscriptions.renewSubscription{value: subscriptionPrice}();
        
        // Should start new period from now
        assertTrue(subscriptions.isSubscribed(subscriber1));
        assertEq(subscriptions.getTimeRemaining(subscriber1), 30 days);
        
        vm.stopPrank();
    }

    function testSubscriptionExtension() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Initial subscription
        subscriptions.subscribe{value: subscriptionPrice}();
        uint256 originalEndTime = subscriptions.getSubscription(subscriber1).endTime;
        
        // Subscribe again while active (should extend)
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Should extend the subscription
        ISubscriptions.Subscription memory sub = subscriptions.getSubscription(subscriber1);
        assertEq(sub.endTime, originalEndTime + 30 days);
        assertEq(sub.amountPaid, subscriptionPrice * 2);
        assertEq(sub.renewalCount, 1);
        
        vm.stopPrank();
    }

    function testRenewalFailures() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Try to renew without existing subscription
        vm.expectRevert("Subscriptions: No existing subscription");
        subscriptions.renewSubscription{value: subscriptionPrice}();
        
        // Subscribe first
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Try to renew with wrong amount
        vm.expectRevert("Subscriptions: Incorrect payment amount");
        subscriptions.renewSubscription{value: subscriptionPrice - 1}();
        
        vm.stopPrank();
    }

    function testAdminFunctions() public {
        vm.startPrank(owner);
        
        // Test price update
        uint256 newPrice = 15 ether;
        subscriptions.setSubscriptionPrice(newPrice);
        assertEq(subscriptions.getSubscriptionPrice(), newPrice);
        
        // Test duration update
        uint256 newDuration = 60 days;
        subscriptions.setSubscriptionDuration(newDuration);
        assertEq(subscriptions.getSubscriptionDuration(), newDuration);
        
        // Test treasury update
        address newTreasury = makeAddr("newTreasury");
        subscriptions.setTreasuryReceiver(newTreasury);
        assertEq(subscriptions.treasuryReceiver(), newTreasury);
        
        vm.stopPrank();
    }

    function testAdminFailures() public {
        vm.startPrank(makeAddr("unauthorized"));
        
        // Unauthorized price update
        vm.expectRevert();
        subscriptions.setSubscriptionPrice(15 ether);
        
        // Unauthorized duration update
        vm.expectRevert();
        subscriptions.setSubscriptionDuration(60 days);
        
        // Unauthorized treasury update
        vm.expectRevert();
        subscriptions.setTreasuryReceiver(makeAddr("newTreasury"));
        
        // Unauthorized pause
        vm.expectRevert();
        subscriptions.pause();
        
        vm.stopPrank();
        
        vm.startPrank(owner);
        
        // Test invalid values
        vm.expectRevert("Subscriptions: Price must be greater than 0");
        subscriptions.setSubscriptionPrice(0);
        
        vm.expectRevert("Subscriptions: Duration must be greater than 0");
        subscriptions.setSubscriptionDuration(0);
        
        vm.expectRevert("Subscriptions: Invalid treasury address");
        subscriptions.setTreasuryReceiver(address(0));
        
        vm.stopPrank();
    }

    function testPauseUnpause() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        // Pause contract
        vm.startPrank(owner);
        subscriptions.pause();
        assertTrue(subscriptions.paused());
        vm.stopPrank();
        
        // Try to subscribe while paused
        vm.startPrank(subscriber1);
        vm.expectRevert();
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Unpause contract
        vm.startPrank(owner);
        subscriptions.unpause();
        assertFalse(subscriptions.paused());
        vm.stopPrank();
        
        // Should work after unpause
        vm.startPrank(subscriber1);
        subscriptions.subscribe{value: subscriptionPrice}();
        assertTrue(subscriptions.isSubscribed(subscriber1));
        vm.stopPrank();
    }

    function testCleanupExpiredSubscriptions() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        // Create subscriptions
        vm.startPrank(subscriber1);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        vm.startPrank(subscriber2);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        assertEq(subscriptions.getActiveSubscriberCount(), 2);
        
        // Fast forward past expiration
        vm.warp(block.timestamp + 31 days);
        
        // Count should still be 2 until cleanup
        assertEq(subscriptions.getActiveSubscriberCount(), 2);
        
        // Cleanup expired subscriptions
        address[] memory usersToCleanup = new address[](2);
        usersToCleanup[0] = subscriber1;
        usersToCleanup[1] = subscriber2;
        
        subscriptions.cleanupExpiredSubscriptions(usersToCleanup);
        
        // Count should now be 0
        assertEq(subscriptions.getActiveSubscriberCount(), 0);
        assertFalse(subscriptions.isSubscribed(subscriber1));
        assertFalse(subscriptions.isSubscribed(subscriber2));
    }

    function testEmergencyWithdraw() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        // Subscribe to add balance
        vm.startPrank(subscriber1);
        subscriptions.subscribe{value: subscriptionPrice}();
        vm.stopPrank();
        
        // Send some extra funds directly to contract for testing
        vm.deal(address(subscriptions), address(subscriptions).balance + 1 ether);
        
        uint256 contractBalance = subscriptions.getContractBalance();
        uint256 treasuryBalanceBefore = treasury.balance;
        
        // Emergency withdraw
        vm.startPrank(owner);
        subscriptions.emergencyWithdraw();
        vm.stopPrank();
        
        // Verify withdrawal
        assertEq(subscriptions.getContractBalance(), 0);
        assertEq(treasury.balance - treasuryBalanceBefore, contractBalance);
    }

    function testFallbackFunctions() public {
        // Test receive function
        vm.startPrank(subscriber1);
        vm.expectRevert("Subscriptions: Use subscribe() function");
        payable(address(subscriptions)).transfer(1 ether);
        vm.stopPrank();
        
        // Test fallback function
        vm.startPrank(subscriber1);
        vm.expectRevert("Subscriptions: Use subscribe() function");
        (bool success, ) = address(subscriptions).call{value: 1 ether}("invalidFunction()");
        assertFalse(success);
        vm.stopPrank();
    }

    function testSubscriptionEdgeCases() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Subscribe
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Fast forward to exactly expiration time
        vm.warp(block.timestamp + 30 days);
        
        // Should be expired exactly at end time
        assertFalse(subscriptions.isSubscribed(subscriber1));
        assertTrue(subscriptions.hasExpiredSubscription(subscriber1));
        
        // One second before expiration
        vm.warp(block.timestamp - 1);
        assertTrue(subscriptions.isSubscribed(subscriber1));
        assertFalse(subscriptions.hasExpiredSubscription(subscriber1));
        
        vm.stopPrank();
    }

    function testSubscriptionEvents() public {
        uint256 subscriptionPrice = subscriptions.getSubscriptionPrice();
        
        vm.startPrank(subscriber1);
        
        // Test Subscribed event
        vm.expectEmit(true, false, false, true);
        emit ISubscriptions.Subscribed(
            subscriber1,
            block.timestamp,
            block.timestamp + 30 days,
            subscriptionPrice
        );
        subscriptions.subscribe{value: subscriptionPrice}();
        
        // Test SubscriptionRenewed event
        vm.expectEmit(true, false, false, true);
        emit ISubscriptions.SubscriptionRenewed(
            subscriber1,
            block.timestamp + 60 days,
            subscriptionPrice,
            1
        );
        subscriptions.renewSubscription{value: subscriptionPrice}();
        
        vm.stopPrank();
        
        // Test admin events
        vm.startPrank(owner);
        
        vm.expectEmit(false, false, false, true);
        emit ISubscriptions.SubscriptionPriceUpdated(subscriptionPrice, 15 ether);
        subscriptions.setSubscriptionPrice(15 ether);
        
        vm.expectEmit(false, false, false, true);
        emit ISubscriptions.SubscriptionDurationUpdated(30 days, 60 days);
        subscriptions.setSubscriptionDuration(60 days);
        
        address newTreasury = makeAddr("newTreasury");
        vm.expectEmit(true, true, false, false);
        emit ISubscriptions.TreasuryReceiverUpdated(treasury, newTreasury);
        subscriptions.setTreasuryReceiver(newTreasury);
        
        vm.stopPrank();
    }
}