// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/// @notice Entry policy for accounts increasing their exposure to a tranche.
interface IEnterGate {
    function canIncreaseCredit(address account) external view returns (bool);
}
