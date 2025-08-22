// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "../interfaces/IPPM.sol";

/**
 * @title VibeFactory
 * @dev Simplified factory contract for creating Vibestream NFTs with integrated delegation
 * Using ProxyAdmin pattern for vibestream-specific delegation management
 */
contract VibeFactory is ERC721URIStorage, Ownable, ReentrancyGuard {
    // Events
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

    // State variables
    uint256 public currentVibeId;
    address public treasuryReceiver;
    address public proxyAdmin;
    address public vibeKiosk; // Single standalone VibeKiosk contract address
    address public ppmContract; // PPM contract for pay-per-minute functionality

    // Profilactic gas limits for network optimization
    uint256 private constant MIN_GAS_BUFFER = 50000; // 50k gas buffer
    
    // ProxyAdmin-based delegation mappings
    mapping(uint256 => address) public vibeDelegates; // vibeId => delegatee
    mapping(address => bool) public authorizedAddresses; // Global authorized addresses
    
    // Vibestream data structure
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
        bool payPerStream;
        uint256 streamPrice;
    }
    
    // Mappings
    mapping(uint256 => VibeData) public vibestreams;
    
    // Constructor
    constructor(
        address _owner,
        address _treasuryReceiver
    ) ERC721("VibesFlow", "VIBE") Ownable(_owner) {
        require(_treasuryReceiver != address(0), "Invalid treasury receiver");
        treasuryReceiver = _treasuryReceiver;
        proxyAdmin = _owner; // Initially set owner as proxyAdmin
        authorizedAddresses[_owner] = true; // Owner is initially authorized
    }
    
    // Modifiers
    modifier validVibeId(uint256 vibeId) {
        require(vibeId < currentVibeId, "Invalid vibe ID");
        _;
    }
    
    modifier hasEnoughGas() {
        require(gasleft() > MIN_GAS_BUFFER, "Insufficient gas for operation");
        _;
    }

    modifier canModifyVibestream(uint256 vibeId) {
        bool isCreator = vibestreams[vibeId].creator == msg.sender;
        bool isAuthorizedAddress = authorizedAddresses[msg.sender];
        bool isProxyAdmin = msg.sender == proxyAdmin;
        bool isDelegated = vibeDelegates[vibeId] == msg.sender;
        
        require(isCreator || isAuthorizedAddress || isProxyAdmin || isDelegated, "Not authorized to modify vibestream");
        _;
    }

    modifier onlyProxyAdmin() {
        bool isProxyAdmin = msg.sender == proxyAdmin;
        bool isProxyAdminOwner = proxyAdmin != address(0) && 
                                ProxyAdmin(proxyAdmin).owner() == msg.sender;
        require(isProxyAdmin || isProxyAdminOwner, "Only ProxyAdmin or ProxyAdmin owner can call this");
        _;
    }

    // ProxyAdmin-only functions for delegation management
    function setProxyAdmin(address _proxyAdmin) external onlyOwner {
        require(_proxyAdmin != address(0), "Invalid ProxyAdmin address");
        proxyAdmin = _proxyAdmin;
        emit ProxyAdminUpdated(_proxyAdmin);
    }

    function addAuthorizedAddress(address _address) external {
        require(msg.sender == proxyAdmin || msg.sender == owner(), "Only ProxyAdmin or owner");
        require(_address != address(0), "Invalid address");
        authorizedAddresses[_address] = true;
        emit AuthorizedAddressAdded(_address);
    }

    function removeAuthorizedAddress(address _address) external {
        require(msg.sender == proxyAdmin || msg.sender == owner(), "Only ProxyAdmin or owner");
        authorizedAddresses[_address] = false;
        emit AuthorizedAddressRemoved(_address);
    }

    /**
     * @dev Set standalone VibeKiosk contract address
     */
    function setVibeKiosk(address _vibeKiosk) external onlyOwner {
        require(_vibeKiosk != address(0), "Invalid VibeKiosk address");
        vibeKiosk = _vibeKiosk;
    }

    /**
     * @dev Set PPM contract address
     */
    function setPPMContract(address _ppmContract) external onlyOwner {
        require(_ppmContract != address(0), "Invalid PPM contract address");
        ppmContract = _ppmContract;
    }

    /**
     * @dev Set vibestream-specific delegate (only ProxyAdmin)
     */
    function setDelegate(uint256 vibeId, address delegatee) 
        external 
        validVibeId(vibeId) 
        onlyProxyAdmin
    {
        require(delegatee != address(0), "Invalid delegatee address");
        
        vibeDelegates[vibeId] = delegatee;
        emit DelegateSet(vibeId, delegatee);
    }

    /**
     * @dev Remove vibestream-specific delegate (only ProxyAdmin)
     */
    function removeDelegate(uint256 vibeId) 
        external 
        validVibeId(vibeId) 
        onlyProxyAdmin
    {
        delete vibeDelegates[vibeId];
        emit DelegateSet(vibeId, address(0));
    }

    // Admin functions
    function setTreasuryReceiver(address _treasuryReceiver) external onlyOwner {
        require(_treasuryReceiver != address(0), "Invalid treasury receiver");
        treasuryReceiver = _treasuryReceiver;
    }

    // Core vibestream creation functions
    function createVibestream(
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        bool payPerStream,
        uint256 streamPrice
    ) external nonReentrant hasEnoughGas returns (uint256 vibeId) {
        return _createVibestreamInternal(
            msg.sender,
            mode,
            storeToFilecoin,
            distance,
            metadataURI,
            ticketsAmount,
            ticketPrice,
            payPerStream,
            streamPrice,
            address(0) // No delegation
        );
    }

    /**
     * @dev Creates a vibestream and sets up delegation in one transaction
     */
    function createVibestreamWithDelegate(
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        bool payPerStream,
        uint256 streamPrice,
        address delegatee
    ) external nonReentrant hasEnoughGas returns (uint256 vibeId) {
        return _createVibestreamInternal(
            msg.sender,
            mode,
            storeToFilecoin,
            distance,
            metadataURI,
            ticketsAmount,
            ticketPrice,
            payPerStream,
            streamPrice,
            delegatee
        );
    }

    function createVibestreamForCreator(
        address creator,
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        bool payPerStream,
        uint256 streamPrice
    ) public nonReentrant hasEnoughGas returns (uint256 vibeId) {
        require(creator != address(0), "Invalid creator address");
        return _createVibestreamInternal(
            creator,
            mode,
            storeToFilecoin,
            distance,
            metadataURI,
            ticketsAmount,
            ticketPrice,
            payPerStream,
            streamPrice,
            address(0) // No delegation
        );
    }

    // Vibestream modification functions
    function setMetadataURI(uint256 vibeId, string calldata newMetadataURI) 
        external 
        validVibeId(vibeId)
        canModifyVibestream(vibeId)
    {
        require(bytes(newMetadataURI).length > 0, "Metadata URI cannot be empty");
        vibestreams[vibeId].metadataURI = newMetadataURI;
        _setTokenURI(vibeId, newMetadataURI);
    }
    
    function setFinalized(uint256 vibeId) 
        external 
        validVibeId(vibeId)
        canModifyVibestream(vibeId)
    {
        vibestreams[vibeId].finalized = true;
    }

    // Internal creation function
    function _createVibestreamInternal(
        address creator,
        string calldata mode,
        bool storeToFilecoin,
        uint256 distance,
        string calldata metadataURI,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        bool payPerStream,
        uint256 streamPrice,
        address delegatee
    ) internal returns (uint256 vibeId) {
        // Input validation
        require(creator != address(0), "Invalid creator address");
        require(bytes(mode).length > 0, "Mode cannot be empty");
        require(bytes(metadataURI).length > 0, "Metadata URI cannot be empty");
        
        // Validate pay-per-stream parameters
        if (payPerStream) {
            require(_stringEquals(mode, "group"), "Pay-per-stream only available for group mode");
            require(streamPrice > 0, "Stream price must be greater than 0 for pay-per-stream");
        }
        
        vibeId = currentVibeId++;

        // 1. Mint Vibestream NFT to the creator
        _mint(creator, vibeId);
        _setTokenURI(vibeId, metadataURI);

        // 2. Store vibestream data (no VibeKiosk deployment - handled by standalone contract)
        vibestreams[vibeId] = VibeData({
            creator: creator,
            startDate: block.timestamp,
            mode: mode,
            storeToFilecoin: storeToFilecoin,
            distance: distance,
            metadataURI: metadataURI,
            ticketsAmount: ticketsAmount,
            ticketPrice: ticketPrice,
            finalized: false,
            payPerStream: payPerStream,
            streamPrice: streamPrice
        });

        // 3. Set up delegation if requested
        if (delegatee != address(0)) {
            vibeDelegates[vibeId] = delegatee;
            emit DelegateSet(vibeId, delegatee);
        }

        // 4. Notify standalone VibeKiosk if tickets are needed
        if (vibeKiosk != address(0) && ticketsAmount > 0 && !_stringEquals(mode, "solo")) {
            try this._notifyVibeKiosk(vibeId, ticketsAmount, ticketPrice, distance) {
                // VibeKiosk notified successfully
            } catch {
                // Continue even if VibeKiosk notification fails
            }
        }

        // 5. Register with PPM contract if pay-per-stream is enabled
        if (payPerStream && ppmContract != address(0)) {
            (bool success, ) = ppmContract.call{gas: 200000}(
                abi.encodeWithSignature(
                    "registerVibestream(uint256,address,uint256)",
                    vibeId,
                    creator,
                    streamPrice
                )
            );
            // Continue regardless of PPM registration success/failure
            // This ensures vibestream creation never fails due to PPM issues
        }

        emit VibestreamCreated(
            vibeId,
            creator,
            block.timestamp,
            mode,
            ticketsAmount,
            ticketPrice,
            delegatee
        );
        
        return vibeId;
    }

    /**
     * @dev External function to notify VibeKiosk about new vibestream with tickets
     */
    function _notifyVibeKiosk(
        uint256 vibeId,
        uint256 ticketsAmount,
        uint256 ticketPrice,
        uint256 distance
    ) external {
        require(msg.sender == address(this), "Internal function only");
        
        if (vibeKiosk != address(0)) {
            (bool success, ) = vibeKiosk.call(
                abi.encodeWithSignature(
                    "registerVibestream(uint256,address,uint256,uint256,uint256)",
                    vibeId,
                    vibestreams[vibeId].creator,
                    ticketsAmount,
                    ticketPrice,
                    distance
                )
            );
            // Don't revert if call fails - just continue
        }
    }

    // View functions
    function getVibestream(uint256 vibeId) 
        external 
        view 
        validVibeId(vibeId) 
        returns (VibeData memory) 
    {
        return vibestreams[vibeId];
    }
    
    function isFinalized(uint256 vibeId) 
        external 
        view 
        validVibeId(vibeId) 
        returns (bool) 
    {
        return vibestreams[vibeId].finalized;
    }

    function isAuthorized(address _address) external view returns (bool) {
        return authorizedAddresses[_address];
    }

    function getDelegate(uint256 vibeId) 
        external 
        view 
        validVibeId(vibeId) 
        returns (address) 
    {
        return vibeDelegates[vibeId];
    }

    // Utility functions
    function _stringEquals(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
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