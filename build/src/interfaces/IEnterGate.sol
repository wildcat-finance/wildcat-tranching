// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Morpho Association
// Mirrored verbatim from morpho-org/midnight, src/interfaces/IGate.sol. The tranche layer
// consumes only canIncreaseCredit (there is no borrower side here); adopting the interface
// unchanged lets one gate deployment serve Midnight markets and tranche sets alike.
pragma solidity >=0.5.0;

interface IEnterGate {
    function canIncreaseCredit(address account) external view returns (bool);
    function canIncreaseDebt(address account) external view returns (bool);
}
