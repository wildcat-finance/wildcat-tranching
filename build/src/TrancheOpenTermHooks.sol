// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SingletonOpenTermHooks, SingletonOpenTermHooksInputs} from "v2-protocol/src/access/SingletonOpenTermHooks.sol";
import {HookedMarket} from "v2-protocol/src/access/OpenTermHooks.sol";
import {DeployMarketInputs} from "v2-protocol/src/interfaces/WildcatStructsAndEnums.sol";
import {MarketState} from "v2-protocol/src/libraries/MarketState.sol";
import {Bit_Enabled_ExecuteWithdrawal, HooksConfig} from "v2-protocol/src/types/HooksConfig.sol";

interface ITrancheManagerCloseCallback {
    function onMarketClosed(address closedMarket, uint32 timeDelinquent) external;

    function onMarketWithdrawalExecuted(
        address executedMarket,
        uint32 expiry,
        uint128 normalizedAmount,
        MarketState calldata state
    ) external;
}

/// @notice Singleton lender hooks which give the TrancheManager an exact market-close checkpoint.
/// @dev The manager address is the same immutable lender sealed into the singleton provider. The
///      callback adds no authority: only the hooked market can reach it, and it can only end accrual.
contract TrancheOpenTermHooks is SingletonOpenTermHooks {
    address public immutable trancheManager;

    constructor(address administrator, bytes memory args) SingletonOpenTermHooks(administrator, args) {
        trancheManager = abi.decode(args, (SingletonOpenTermHooksInputs)).lender;
    }

    function version() external pure override returns (string memory) {
        return "TrancheOpenTermHooks";
    }

    /// @dev Market withdrawal execution is permissionless. Enabling this dispatch makes recovery
    ///      attribution independent of whether the manager or any other account calls execution.
    function _onCreateMarket(
        address administrator_,
        address marketAddress,
        DeployMarketInputs calldata parameters,
        bytes calldata hooksData
    ) internal override returns (HooksConfig marketHooksConfig) {
        marketHooksConfig = super._onCreateMarket(administrator_, marketAddress, parameters, hooksData);
        marketHooksConfig = marketHooksConfig.setFlag(Bit_Enabled_ExecuteWithdrawal);
    }

    function onCloseMarket(MarketState calldata state, bytes calldata) external override {
        HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];
        if (!hookedMarket.isHooked) revert NotHookedMarket();
        if (trancheManager.code.length != 0) {
            ITrancheManagerCloseCallback(trancheManager).onMarketClosed(msg.sender, state.timeDelinquent);
        }
    }

    function onExecuteWithdrawal(
        address lender,
        uint32 expiry,
        uint128 normalizedAmountWithdrawn,
        MarketState calldata state,
        bytes calldata
    ) external override {
        HookedMarket storage hookedMarket = _hookedMarkets[msg.sender];
        if (!hookedMarket.isHooked) revert NotHookedMarket();
        if (lender == trancheManager && trancheManager.code.length != 0) {
            ITrancheManagerCloseCallback(trancheManager).onMarketWithdrawalExecuted(
                msg.sender, expiry, normalizedAmountWithdrawn, state
            );
        }
    }
}
