// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/VibeFactory.sol";
import "../src/VibeKiosk.sol";
import "../src/PPM.sol";
import "../src/Subscriptions.sol";
import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

/**
 * @title Deploy
 * @dev Streamlined VibesFlow architecture
 * Features: VibeFactory with integrated delegation + standalone VibeKiosk + ProxyAdmin
 * Eliminated: RTAWrapper, Distributor, per-vibestream VibeKiosk deployments
 */
contract Deploy is Script {
    // Deployment configuration
    struct DeploymentConfig {
        address owner;
        address treasuryReceiver;
        uint256 deployerPrivateKey;
    }
    
    // Deployed contract addresses
    struct DeployedContracts {
        address vibeFactory;
        address vibeKiosk;
        address ppm;
        address subscriptions;
        address proxyAdmin;
    }

    function run() external {
        // Load environment variables
        DeploymentConfig memory config = DeploymentConfig({
            owner: vm.envAddress("TREASURY_RECEIVER"),
            treasuryReceiver: vm.envAddress("TREASURY_RECEIVER"),
            deployerPrivateKey: vm.envUint("PRIVATE_KEY")
        });

        vm.startBroadcast(config.deployerPrivateKey);

        // Deploy contracts
        DeployedContracts memory contracts = deployAllContracts(config);
        
        // Configure contracts
        configureContracts(contracts, config);
        
        // Verify deployment
        verifyDeployment(contracts);
        
        vm.stopBroadcast();

        // Log deployment addresses
        logDeploymentAddresses(contracts);
    }

    function deployAllContracts(DeploymentConfig memory config) 
        internal 
        returns (DeployedContracts memory contracts) 
    {
        console.log("=== Starting Simplified VibesFlow Deployment ===");
        
        // 1. Deploy ProxyAdmin for delegation management
        console.log("Deploying ProxyAdmin...");
        contracts.proxyAdmin = address(new ProxyAdmin(config.owner));
        console.log("ProxyAdmin deployed at:", contracts.proxyAdmin);

        // 2. Deploy VibeFactory with integrated delegation
        console.log("Deploying VibeFactory...");
        contracts.vibeFactory = address(new VibeFactory(
            config.owner,
            config.treasuryReceiver
        ));
        console.log("VibeFactory deployed at:", contracts.vibeFactory);

        // 3. Deploy standalone VibeKiosk
        console.log("Deploying standalone VibeKiosk...");
        contracts.vibeKiosk = address(new VibeKiosk(
            contracts.vibeFactory,
            config.treasuryReceiver,
            config.owner
        ));
        console.log("VibeKiosk deployed at:", contracts.vibeKiosk);

        // 4. Deploy PPM contract
        console.log("Deploying PPM contract...");
        contracts.ppm = address(new PPM(
            config.owner,
            contracts.vibeFactory,
            config.treasuryReceiver
        ));
        console.log("PPM deployed at:", contracts.ppm);

        // 5. Deploy Subscriptions contract
        console.log("Deploying Subscriptions contract...");
        contracts.subscriptions = address(new Subscriptions(
            config.owner,
            config.treasuryReceiver
        ));
        console.log("Subscriptions deployed at:", contracts.subscriptions);

        return contracts;
    }

    function configureContracts(
        DeployedContracts memory contracts, 
        DeploymentConfig memory config
    ) internal {
        console.log("=== Configuring Simplified Architecture ===");

        // Configure VibeFactory
        console.log("Configuring VibeFactory...");
        VibeFactory vibeFactory = VibeFactory(contracts.vibeFactory);
        vibeFactory.setProxyAdmin(contracts.proxyAdmin);
        vibeFactory.setVibeKiosk(contracts.vibeKiosk);
        vibeFactory.setPPMContract(contracts.ppm);

        // Configure PPM contract
        console.log("Configuring PPM contract...");
        PPM ppm = PPM(payable(contracts.ppm));
        
        // Verify PPM configuration
        console.log("PPM VibeFactory:", address(ppm.vibeFactory()));
        console.log("PPM Treasury:", ppm.treasuryReceiver());
        console.log("PPM Treasury Fee:", ppm.treasuryFeePercent());
        
        // Configure Subscriptions contract
        console.log("Configuring Subscriptions contract...");
        Subscriptions subscriptions = Subscriptions(payable(contracts.subscriptions));
        
        // Verify Subscriptions configuration
        console.log("Subscriptions Treasury:", subscriptions.treasuryReceiver());
        console.log("Subscriptions Price:", subscriptions.getSubscriptionPrice());
        console.log("Subscriptions Duration:", subscriptions.getSubscriptionDuration());
        
        // Ensure contracts are unpaused (Pausable contracts start unpaused by default)
        // ppm.unpause(); // Only call if needed
        // subscriptions.unpause(); // Only call if needed

        console.log("Complete VibesFlow architecture configuration complete!");
    }

    function verifyDeployment(DeployedContracts memory contracts) internal view {
        console.log("=== Verifying Simplified Deployment ===");

        // Verify all contracts have code
        require(contracts.vibeFactory.code.length > 0, "VibeFactory deployment failed");
        require(contracts.vibeKiosk.code.length > 0, "VibeKiosk deployment failed");
        require(contracts.ppm.code.length > 0, "PPM deployment failed");
        require(contracts.subscriptions.code.length > 0, "Subscriptions deployment failed");
        require(contracts.proxyAdmin.code.length > 0, "ProxyAdmin deployment failed");

        // Verify VibeFactory configuration
        VibeFactory vibeFactory = VibeFactory(contracts.vibeFactory);
        require(vibeFactory.proxyAdmin() == contracts.proxyAdmin, "VibeFactory proxyAdmin not set");
        require(vibeFactory.vibeKiosk() == contracts.vibeKiosk, "VibeFactory vibeKiosk not set");
        require(vibeFactory.ppmContract() == contracts.ppm, "VibeFactory PPM not set");

        // Verify VibeKiosk configuration
        VibeKiosk vibeKiosk = VibeKiosk(contracts.vibeKiosk);
        require(address(vibeKiosk.vibeFactory()) == contracts.vibeFactory, "VibeKiosk factory not set");

        // Verify Subscriptions configuration
        Subscriptions subscriptions = Subscriptions(payable(contracts.subscriptions));
        require(subscriptions.getSubscriptionPrice() == 10 ether, "Subscriptions price not set correctly");
        require(subscriptions.getSubscriptionDuration() == 30 days, "Subscriptions duration not set correctly");

        console.log("All simplified architecture verifications passed!");
    }

    function logDeploymentAddresses(DeployedContracts memory contracts) internal pure {
        console.log("\n=== COMPLETE VIBESFLOW DEPLOYMENT ===");
        console.log("VibeFactory:     ", contracts.vibeFactory);
        console.log("VibeKiosk:       ", contracts.vibeKiosk);
        console.log("PPM:             ", contracts.ppm);
        console.log("Subscriptions:   ", contracts.subscriptions);
        console.log("ProxyAdmin:      ", contracts.proxyAdmin);
        console.log("\n=== UPDATE YOUR .env FILES ===");
        console.log("VIBE_FACTORY_ADDRESS=", contracts.vibeFactory);
        console.log("VIBE_KIOSK_ADDRESS=", contracts.vibeKiosk);
        console.log("PPM_ADDRESS=", contracts.ppm);
        console.log("SUBSCRIPTIONS_ADDRESS=", contracts.subscriptions);
        console.log("PROXY_ADMIN_ADDRESS=", contracts.proxyAdmin);
        console.log("\n=== SIMPLIFIED ARCHITECTURE BENEFITS ===");
        console.log("[SUCCESS] RTAWrapper eliminated - createVibestreamWithDelegate in VibeFactory");
        console.log("[SUCCESS] Distributor eliminated - not needed for current functionality");
        console.log("[SUCCESS] Per-vibestream VibeKiosk deployment eliminated - single standalone contract");
        console.log("[SUCCESS] Reduced gas costs and complexity");
        console.log("[SUCCESS] Single transaction vibestream creation + delegation");
        console.log("[SUCCESS] ProxyAdmin handles all delegation management");
        console.log("[SUCCESS] Standalone VibeKiosk handles all ticket sales via mappings");
        console.log("[SUCCESS] Subscriptions contract for Vibe Market access management");
    }

    // Helper function for local testing
    function deployForTesting() external returns (DeployedContracts memory) {
        DeploymentConfig memory config = DeploymentConfig({
            owner: msg.sender,
            treasuryReceiver: msg.sender,
            deployerPrivateKey: 0 // Not used in testing
        });

        return deployAllContracts(config);
    }
}