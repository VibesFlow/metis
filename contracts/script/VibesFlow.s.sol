// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

// --- Import contract interfaces and implementations ---
// Note: Adjust paths if your project structure is different.
import {VibeFactory} from "../src/VibeFactory.sol";
import {VibeManager} from "../src/VibeManager.sol";
import {Delegation} from "../src/Delegation.sol";
import {Distributor} from "../src/Distributor.sol";
import {RTAWrapper} from "../src/RTAWrapper.sol";

contract VibesFlowDeploy is Script {
    // --- Configuration ---
    address treasuryReceiver = vm.envAddress("TREASURY_RECEIVER");

    // --- Deployment artifacts ---
    ProxyAdmin public proxyAdmin;

    // Implementation contracts
    VibeFactory public vibeFactoryImpl;
    VibeManager public vibeManagerImpl;
    Distributor public distributorImpl;
    Delegation public delegationImpl;

    // Final contract instances (proxies or direct addresses)
    VibeFactory public vibeFactory;
    VibeManager public vibeManager;
    Distributor public distributor;
    RTAWrapper public rtaWrapper;

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        
        console2.log("Deploying contracts with address:", deployerAddress);
        console2.log("Treasury receiver:", treasuryReceiver);
        
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy ProxyAdmin: Manages all proxy upgrades
        proxyAdmin = new ProxyAdmin(deployerAddress);
        
        // 2. Deploy all implementation contracts first
        _deployImplementations();
        
        // 3. Deploy proxies and final contracts, wiring them up
        _deployAndInitializeContracts(deployerAddress);

        // 4. Deploy the utility RTAWrapper
        rtaWrapper = new RTAWrapper(address(vibeFactory), address(vibeManager));
        
        // 5. Configure VibeManager with RTAWrapper address
        vibeManager.setRTAWrapper(address(rtaWrapper));
        
        vm.stopBroadcast();
        _logDeploymentAddresses();
    }
    
    function _deployImplementations() internal {
        console2.log("\nDeploying implementations...");
        vibeFactoryImpl = new VibeFactory();
        vibeManagerImpl = new VibeManager();
        distributorImpl = new Distributor();
        delegationImpl = new Delegation();
        
        console2.log("  VibeFactory Impl:", address(vibeFactoryImpl));
        console2.log("  VibeManager Impl:", address(vibeManagerImpl));
        console2.log("  Distributor Impl:", address(distributorImpl));
        console2.log("  Delegation Impl:", address(delegationImpl));
    }
    
    function _deployAndInitializeContracts(address owner) internal {
        console2.log("\nDeploying proxies and initializing contracts...");

        // Deploy VibeFactory (non-upgradeable) FIRST to resolve circular dependencies
        // It's non-upgradeable by design to be the base of the system.
        vibeFactory = new VibeFactory();
        console2.log("VibeFactory deployed at:", address(vibeFactory));

        // Deploy VibeManager Proxy
        bytes memory vibeManagerInitData = abi.encodeWithSelector(VibeManager.initialize.selector, owner, address(vibeFactory), address(delegationImpl));
        TransparentUpgradeableProxy vibeManagerProxy = new TransparentUpgradeableProxy(address(vibeManagerImpl), address(proxyAdmin), vibeManagerInitData);
        vibeManager = VibeManager(payable(address(vibeManagerProxy)));
        console2.log("VibeManager proxy deployed at:", address(vibeManager));
        
        // Deploy Distributor Proxy with VibeFactory address
        bytes memory distributorInitData = abi.encodeWithSelector(Distributor.initialize.selector, owner, address(vibeFactory), address(0), address(0), treasuryReceiver);
        TransparentUpgradeableProxy distributorProxy = new TransparentUpgradeableProxy(address(distributorImpl), address(proxyAdmin), distributorInitData);
        distributor = Distributor(payable(address(distributorProxy)));
        console2.log("Distributor proxy deployed at:", address(distributor));

        // Initialize VibeFactory with all the deployed contract addresses
        vibeFactory.initialize(owner, address(vibeManager), address(distributor), treasuryReceiver);
        
        console2.log("All contracts deployed and initialized successfully.");
    }
    
    function _logDeploymentAddresses() internal view {
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("ProxyAdmin:      ", address(proxyAdmin));
        console2.log("----------------------------------");
        console2.log("VibeFactory:    ", address(vibeFactory));
        console2.log("VibeManager:    ", address(vibeManager));
        console2.log("Distributor:     ", address(distributor));
        console2.log("Delegation Impl: ", address(delegationImpl));
        console2.log("RTAWrapper: ", address(rtaWrapper));
        console2.log("----------------------------------");
        console2.log("Treasury:        ", treasuryReceiver);
        console2.log("=========================\n");
    }
}