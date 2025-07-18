// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDistributor {
    function registerVibestream(uint256 vibeId, address creator) external;
}