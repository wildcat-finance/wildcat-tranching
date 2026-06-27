// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TrancheController} from "./TrancheController.sol";
import {IUnderlying4626, IArchControllerLike} from "./interfaces/IExternal.sol";

/// @title TrancheFactory
/// @notice Protocol-level factory for senior/junior tranche sets, one per Wildcat market.
/// @dev Mirrors `Wildcat4626WrapperFactory`: takes the `WildcatArchController` and gates
///      deployment on `isRegisteredMarket`, so tranching rides the protocol's own deployment
///      rails. Derives the market from the wrapper (`underlying.market()`). One set per market.
contract TrancheFactory {
    IArchControllerLike public immutable archController;

    mapping(address => address) public controllerForMarket; // market => TrancheController
    address[] public allControllers;

    event TranchesDeployed(
        address indexed market, address indexed underlying, address controller, address senior, address junior
    );

    constructor(address _archController) {
        require(_archController != address(0), "ZERO_ARCH");
        archController = IArchControllerLike(_archController);
    }

    struct DeployParams {
        address underlyingVault; // the market's ERC-4626 wrapper (v-wmtUSDC)
        address sentinel;
        address borrower;
        address governance;
        address defaultDeclarer;
        uint256 seniorShareBips;
        uint256 minJuniorBips;
        uint256 defaultPenaltyWindow;
    }

    function deployTranches(DeployParams calldata p) external returns (address controllerAddr) {
        address market = IUnderlying4626(p.underlyingVault).market();
        require(archController.isRegisteredMarket(market), "MARKET_NOT_REGISTERED");
        require(controllerForMarket[market] == address(0), "TRANCHES_EXIST");

        TrancheController c = new TrancheController(
            TrancheController.Params({
                underlyingVault: p.underlyingVault,
                sentinel: p.sentinel,
                borrower: p.borrower,
                governance: p.governance,
                defaultDeclarer: p.defaultDeclarer,
                seniorShareBips: p.seniorShareBips,
                minJuniorBips: p.minJuniorBips,
                defaultPenaltyWindow: p.defaultPenaltyWindow,
                shareDecimals: 18
            })
        );

        controllerForMarket[market] = address(c);
        allControllers.push(address(c));
        controllerAddr = address(c);
        emit TranchesDeployed(market, p.underlyingVault, controllerAddr, address(c.senior()), address(c.junior()));
    }

    function controllersLength() external view returns (uint256) {
        return allControllers.length;
    }
}
