// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RTAWrapper} from "../src/RTAWrapper.sol";
import {VibeFactory} from "../src/VibeFactory.sol";
import {VibeKiosk} from "../src/VibeKiosk.sol";
import {VibeManager} from "../src/VibeManager.sol";
import {Delegation} from "../src/Delegation.sol";

contract VibesFlowTest is Test {
    VibeFactory public vibeFactory;
    VibeManager public vibeManager;
    RTAWrapper public rtaWrapper;
    
    address public owner = address(0x1);
    address public creator = address(0x2);
    address public delegatee = address(0x3);
    address public treasury = address(0x4);
    address public buyer = address(0x5);
    
    string public constant DEFAULT_MODE = "group";
    bool public constant DEFAULT_STORE_TO_FILECOIN = true;
    uint256 public constant DEFAULT_DISTANCE = 5;
    string public constant DEFAULT_TITLE = "Test Vibestream";
    string public constant DEFAULT_METADATA = "ipfs://QmTestHash";
    uint256 public constant DEFAULT_START_DATE = 1700000000;
    uint256 public constant DEFAULT_TICKETS_AMOUNT = 100;
    uint256 public constant DEFAULT_TICKET_PRICE = 0.1 ether;
    
    event VibestreamCreated(
        uint256 indexed vibeId,
        address indexed creator,
        uint256 startDate,
        string mode,
        string title,
        string metadataURI,
        address vibeKioskAddress
    );
    
    event TicketMinted(
        uint256 indexed ticketId,
        address indexed buyer,
        string ticketName,
        string title,
        uint256 price
    );

    function setUp() public {
        vm.startPrank(owner);
        
        // Deploy VibeFactory
        vibeFactory = new VibeFactory();
        
        // Deploy VibeManager
        vibeManager = new VibeManager();
        
        // Initialize contracts
        vibeManager.initialize(owner, address(vibeFactory));
        vibeFactory.initialize(owner, address(vibeManager), address(0), treasury);
        
        // Deploy RTAWrapper
        rtaWrapper = new RTAWrapper(address(vibeFactory), address(vibeManager));
        
        // Set RTAWrapper in VibeManager
        vibeManager.setRTAWrapper(address(rtaWrapper));
        
        vm.stopPrank();
    }
    
    function testSetup() public view {
        assertEq(vibeFactory.owner(), owner);
        assertEq(vibeManager.owner(), owner);
        assertEq(address(vibeManager.vibeFactory()), address(vibeFactory));
        assertEq(vibeManager.RTAWrapper(), address(rtaWrapper));
    }
    
    function testCreateVibestream() public {
        vm.startPrank(creator);
        
        vm.expectEmit(true, true, false, false);
        emit VibestreamCreated(0, creator, DEFAULT_START_DATE, DEFAULT_MODE, DEFAULT_TITLE, DEFAULT_METADATA, address(0));
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        assertEq(vibeId, 0);
        assertEq(vibeFactory.ownerOf(vibeId), creator);
        assertEq(vibeFactory.totalVibestreams(), 1);
        
        // Check vibestream data
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.creator, creator);
        assertEq(vibeData.startDate, DEFAULT_START_DATE);
        assertEq(vibeData.mode, DEFAULT_MODE);
        assertEq(vibeData.storeToFilecoin, DEFAULT_STORE_TO_FILECOIN);
        assertEq(vibeData.distance, DEFAULT_DISTANCE);
        assertEq(vibeData.metadataURI, DEFAULT_METADATA);
        assertFalse(vibeData.finalized);
        assertTrue(vibeData.vibeKioskAddress != address(0));
        
        vm.stopPrank();
    }
    
    function testCreateVibestreamWithDefaultTitle() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            "", // Empty title should use default
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.title, "Vibe 0");
        
        vm.stopPrank();
    }
    
    function testVibeKioskDeployment() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        VibeKiosk vibeKiosk = VibeKiosk(vibeData.vibeKioskAddress);
        
        // Test VibeKiosk properties
        assertEq(vibeKiosk.vibeId(), vibeId);
        assertEq(vibeKiosk.creator(), creator);
        assertEq(vibeKiosk.ticketsAmount(), DEFAULT_TICKETS_AMOUNT);
        assertEq(vibeKiosk.ticketPrice(), DEFAULT_TICKET_PRICE);
        assertEq(vibeKiosk.ticketsSold(), 0);
        assertTrue(vibeKiosk.isAvailable());
        
        vm.stopPrank();
    }
    
    function testPurchaseTicket() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        VibeKiosk vibeKiosk = VibeKiosk(vibeData.vibeKioskAddress);
        
        vm.stopPrank();
        
        // Purchase ticket as buyer
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        
        uint256 ticketId = vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}();
        
        assertEq(ticketId, 1);
        assertEq(vibeKiosk.ownerOf(ticketId), buyer);
        assertEq(vibeKiosk.ticketsSold(), 1);
        assertTrue(vibeKiosk.hasTicketForVibestream(buyer, vibeId));
        
        // Check ticket data
        (
            uint256 returnedVibeId,
            address owner_,
            address originalOwner,
            uint256 purchasePrice,
            uint256 purchaseTimestamp,
            string memory name,
            string memory title,
            string memory metadataURI,
            uint256 ticketNumber,
            uint256 totalTickets
        ) = vibeKiosk.getTicketInfo(ticketId);
        
        assertEq(returnedVibeId, vibeId);
        assertEq(owner_, buyer);
        assertEq(originalOwner, buyer);
        assertEq(purchasePrice, DEFAULT_TICKET_PRICE);
        assertEq(name, "rta0_ticket1");
        assertEq(title, DEFAULT_TITLE);
        assertEq(metadataURI, DEFAULT_METADATA);
        assertEq(ticketNumber, 1);
        assertEq(totalTickets, DEFAULT_TICKETS_AMOUNT);
        
        vm.stopPrank();
    }
    
    function testDelegationProxy() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        // Create delegation proxy
        vibeManager.createDelegationProxy(vibeId, delegatee);
        
        address proxyAddress = vibeManager.vibeDelegationProxy(vibeId);
        assertTrue(proxyAddress != address(0));
        
        Delegation delegation = Delegation(proxyAddress);
        assertEq(delegation.vibeId(), vibeId);
        assertEq(delegation.vibeFactory(), address(vibeFactory));
        assertEq(delegation.delegatee(), delegatee);
        assertEq(delegation.initializer(), address(vibeManager));
        
        vm.stopPrank();
        
        // Test delegatee can update metadata
        vm.startPrank(delegatee);
        string memory newMetadata = "ipfs://QmNewHash";
        vibeManager.updateMetadata(vibeId, newMetadata);
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.metadataURI, newMetadata);
        
        vm.stopPrank();
    }
    
    function testRTAWrapperCreateVibestreamAndDelegate() public {
        vm.startPrank(creator);
        
        rtaWrapper.createVibestreamAndDelegate(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE,
            delegatee
        );
        
        // Check vibestream was created
        assertEq(vibeFactory.totalVibestreams(), 1);
        assertEq(vibeFactory.ownerOf(0), creator);
        
        // Check delegation proxy was created
        address proxyAddress = vibeManager.vibeDelegationProxy(0);
        assertTrue(proxyAddress != address(0));
        assertEq(vibeManager.vibeDelegates(0), delegatee);
        
        vm.stopPrank();
    }
    
    function testSoloModeVibestream() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            "solo",
            true,
            0, // Distance should be 0 for solo mode
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        assertEq(vibeData.mode, "solo");
        assertEq(vibeData.distance, 0);
        
        vm.stopPrank();
    }
    
    function testRevenueDistribution() public {
        vm.startPrank(creator);
        
        uint256 vibeId = vibeFactory.createVibestream(
            DEFAULT_START_DATE,
            DEFAULT_MODE,
            DEFAULT_STORE_TO_FILECOIN,
            DEFAULT_DISTANCE,
            DEFAULT_TITLE,
            DEFAULT_METADATA,
            DEFAULT_TICKETS_AMOUNT,
            DEFAULT_TICKET_PRICE
        );
        
        VibeFactory.VibeData memory vibeData = vibeFactory.getVibestream(vibeId);
        VibeKiosk vibeKiosk = VibeKiosk(vibeData.vibeKioskAddress);
        
        vm.stopPrank();
        
        // Record initial balances
        uint256 creatorInitialBalance = creator.balance;
        uint256 treasuryInitialBalance = treasury.balance;
        
        // Purchase ticket
        vm.deal(buyer, 1 ether);
        vm.startPrank(buyer);
        
        vibeKiosk.purchaseTicket{value: DEFAULT_TICKET_PRICE}();
        
        // Check revenue distribution (80% creator, 20% treasury)
        uint256 expectedCreatorShare = (DEFAULT_TICKET_PRICE * 80) / 100;
        uint256 expectedTreasuryShare = DEFAULT_TICKET_PRICE - expectedCreatorShare;
        
        assertEq(creator.balance - creatorInitialBalance, expectedCreatorShare);
        assertEq(treasury.balance - treasuryInitialBalance, expectedTreasuryShare);
        
        vm.stopPrank();
    }
}