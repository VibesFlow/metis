// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "../interfaces/IVibeFactory.sol";
import "./Delegation.sol";

/**
 * @title VibeManager
 * @dev Manages post-creation operations for RTA vibestreams, including delegation via proxies.
 * This contract is upgradeable and is the single point of contact for permissioned actions.
 */
contract VibeManager is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    // Address of the main VibeFactory
    IVibeFactory public vibeFactory;
    
    // Address of the master implementation for our delegation proxies.
    address public delegationContract;
    
    // Address of the RTAWrapper contract that can create delegation proxies on behalf of users
    address public RTAWrapper;

    // Mapping from vibeId to its dedicated delegation proxy contract
    mapping(uint256 => address) public vibeDelegationProxy;
    
    // Mapping to store who is the authorized delegate for a vibe's proxy
    mapping(uint256 => address) public vibeDelegates;

    // --- Events ---
    event DelegationProxyCreated(uint256 indexed vibeId, address proxyAddress, address indexed delegatee);
    event DelegateUpdated(uint256 indexed vibeId, address indexed newDelegatee);
    event RTAWrapperUpdated(address indexed newRTAWrapper);

    // --- Errors ---
    error OnlyVibeCreator();
    error ProxyAlreadyExists();
    error NotAuthorized();
    error InvalidAddress();
    error OnlyRTAWrapper();

    /**
     * @dev Initializes the VibeManager.
     */
    function initialize(address _owner, address _vibeFactoryAddress, address _delegationContract) public initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
        vibeFactory = IVibeFactory(_vibeFactoryAddress);
        
        // Set the master implementation for our delegation contract
        delegationContract = _delegationContract;
    }

    /**
     * @dev Sets the RTAWrapper contract address. Only owner can call this.
     */
    function setRTAWrapper(address _RTAWrapper) external onlyOwner {
        if (_RTAWrapper == address(0)) {
            revert InvalidAddress();
        }
        RTAWrapper = _RTAWrapper;
        emit RTAWrapperUpdated(_RTAWrapper);
    }

    /**
     * @dev Deploys a lightweight, clonable proxy for a vibestream to handle delegation.
     * Only the creator of the vibe can initiate this.
     * @param vibeId The ID of the vibestream to create a delegation proxy for.
     * @param delegatee The address that will be granted delegation powers.
     */
    function createDelegationProxy(uint256 vibeId, address delegatee) external {
        // 1. Authorization Check: Only the original creator of the NFT can set up delegation.
        if (vibeFactory.ownerOf(vibeId) != msg.sender) {
            revert OnlyVibeCreator();
        }
        if (vibeDelegationProxy[vibeId] != address(0)) {
            revert ProxyAlreadyExists();
        }
        if (delegatee == address(0)) {
            revert InvalidAddress();
        }

        // 2. Deploy Proxy: Use the cheaper Clones library to deploy a minimal proxy.
        // This proxy points to 'delegationContract'.
        address proxy = Clones.clone(delegationContract);
        
        // 3. Initialize Proxy: Set the initial state of the new proxy contract.
        Delegation(proxy).initialize(vibeId, address(vibeFactory), delegatee);

        // 4. Store State
        vibeDelegationProxy[vibeId] = proxy;
        vibeDelegates[vibeId] = delegatee;

        emit DelegationProxyCreated(vibeId, proxy, delegatee);
    }

    /**
     * @dev Deploys a delegation proxy on behalf of a user. Only the RTAWrapper can call this.
     * This allows the RTAWrapper to create vibes and set up delegation in a single transaction.
     * @param vibeId The ID of the vibestream to create a delegation proxy for.
     * @param vibeCreator The address of the vibestream creator (who owns the NFT).
     * @param delegatee The address that will be granted delegation powers.
     */
    function createDelegationProxyForUser(
        uint256 vibeId, 
        address vibeCreator, 
        address delegatee
    ) external {
        // 1. Authorization Check: Only the RTAWrapper contract can call this
        if (msg.sender != RTAWrapper) {
            revert OnlyRTAWrapper();
        }
        
        // 2. Verify the vibeCreator actually owns the NFT
        if (vibeFactory.ownerOf(vibeId) != vibeCreator) {
            revert OnlyVibeCreator();
        }
        
        if (vibeDelegationProxy[vibeId] != address(0)) {
            revert ProxyAlreadyExists();
        }
        if (delegatee == address(0)) {
            revert InvalidAddress();
        }

        // 3. Deploy Proxy: Use the cheaper Clones library to deploy a minimal proxy.
        // This proxy points to 'delegationContract'.
        address proxy = Clones.clone(delegationContract);
        
        // 4. Initialize Proxy: Set the initial state of the new proxy contract.
        Delegation(proxy).initialize(vibeId, address(vibeFactory), delegatee);

        // 5. Store State
        vibeDelegationProxy[vibeId] = proxy;
        vibeDelegates[vibeId] = delegatee;

        emit DelegationProxyCreated(vibeId, proxy, delegatee);
    }

    /**
     * @dev Main function to update a vibestream's metadata.
     * Checks if the caller is the creator OR the authorized delegate via the proxy.
     */
    function updateMetadata(uint256 vibeId, string memory newMetadataURI) external {
        // Authorization: Caller must be the original creator or the registered delegate for this vibestream.
        if (vibeFactory.ownerOf(vibeId) != msg.sender && vibeDelegates[vibeId] != msg.sender) {
            revert NotAuthorized();
        }
        
        // If authorized, this contract calls the VibeFactory to perform the state change.
        _authorize(vibeId);
        vibeFactory.setMetadataURI(vibeId, newMetadataURI);
    }

    /**
     * @dev Finalizes an RTA Vibestream.
     */
    function finalize(uint256 vibeId) external {
        if (vibeFactory.ownerOf(vibeId) != msg.sender && vibeDelegates[vibeId] != msg.sender) {
            revert NotAuthorized();
        }
        _authorize(vibeId);
        vibeFactory.finalized(vibeId);
    }

    // --- Internal Functions ---
    
    /**
     * @dev Internal function to authorize access to vibstream operations.
     * Checks if the caller is the vibe owner or authorized delegate.
     */
    function _authorize(uint256 vibeId) internal view {
        if (vibeFactory.ownerOf(vibeId) != msg.sender && vibeDelegates[vibeId] != msg.sender) {
            revert NotAuthorized();
        }
    }

    // --- Other Management Functions ---
    
    function updateDelegate(uint256 vibeId, address newDelegatee) external {
        if (vibeFactory.ownerOf(vibeId) != msg.sender) {
            revert OnlyVibeCreator();
        }
        if (newDelegatee == address(0)) {
            revert InvalidAddress();
        }
        vibeDelegates[vibeId] = newDelegatee;
        emit DelegateUpdated(vibeId, newDelegatee);
    }

    // This contract itself is upgradeable.
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}