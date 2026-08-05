// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IEnterGate} from "./interfaces/IEnterGate.sol";

/// @title WhitelistGate
/// @notice Minimal owner-managed whitelist implementing Morpho Midnight's IEnterGate.
///         The default junior gate: the controller consults canIncreaseCredit(receiver) on
///         every exposure-increasing edge (deposit, transfer-in), so policy lives here and
///         the audited controller stays policy-free. Never reverts; returns false instead.
contract WhitelistGate is IEnterGate {
    address public owner;
    address public pendingOwner;
    mapping(address => bool) public allowed;

    event Allowed(address indexed account, bool allowed);
    event OwnerProposed(address indexed pending);
    event OwnerTransferred(address indexed from, address indexed to);

    constructor(address _owner) {
        require(_owner != address(0), "ZERO_OWNER");
        owner = _owner;
        emit OwnerTransferred(address(0), _owner);
    }

    function setAllowed(address account, bool a) external {
        require(msg.sender == owner, "ONLY_OWNER");
        allowed[account] = a;
        emit Allowed(account, a);
    }

    function transferOwner(address next) external {
        require(msg.sender == owner, "ONLY_OWNER");
        require(next != address(0), "ZERO_OWNER");
        pendingOwner = next;
        emit OwnerProposed(next);
    }

    function acceptOwner() external {
        require(msg.sender == pendingOwner, "NOT_PENDING");
        emit OwnerTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }

    function canIncreaseCredit(address account) external view returns (bool) {
        return allowed[account];
    }

    function canIncreaseDebt(address account) external view returns (bool) {
        return allowed[account];
    }
}
