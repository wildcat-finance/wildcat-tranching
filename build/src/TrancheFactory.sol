// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TrancheController} from "./TrancheController.sol";
import {IWildcatMarket, IArchControllerLike, IWrapperFactoryLike} from "./interfaces/IExternal.sol";

/// @title TrancheFactory
/// @notice Ownerless, borrower-gated factory for senior/junior tranche sets: one live set per
///         registered Wildcat market. All neutrality lives in hard-coded bounds (enforced by the
///         controller's constructor) plus the registration check and wrapper resolution below --
///         there is no discretion anywhere, so the factory has no privileged role at all.
/// @dev    Squatting is impossible by construction: for any market exactly one address can deploy,
///         and it is the one with the legal identity behind the facility. Deployment and capital
///         formation are separable besides -- a fresh set cannot accept senior until whitelisted
///         first-loss capital funds it to the floor, so parameters are ratified by the first
///         junior deposit.
contract TrancheFactory {
    IArchControllerLike public immutable archController;
    IWrapperFactoryLike public immutable wrapperFactory;
    /// @notice The canonical sanctions sentinel, fixed for every deployment; never caller-supplied.
    address public immutable sentinel;

    mapping(address => address) public controllerForMarket; // market => current TrancheController
    address[] public allControllers; // full history, superseded sets included

    event TranchesDeployed(
        address indexed market, address indexed underlying, address controller, address senior, address junior
    );
    event TranchesSuperseded(address indexed market, address indexed retired, address indexed current);

    constructor(address _archController, address _wrapperFactory, address _sentinel) {
        require(_archController != address(0), "ZERO_ARCH");
        require(_wrapperFactory != address(0), "ZERO_WRAPPER_FACTORY");
        require(_sentinel != address(0), "ZERO_SENTINEL");
        archController = IArchControllerLike(_archController);
        wrapperFactory = IWrapperFactoryLike(_wrapperFactory);
        sentinel = _sentinel;
    }

    /// @dev Everything else the controller needs is resolved or derived: the wrapper from the
    ///      wrapper factory (deployed if missing), the sentinel from this factory, the borrower
    ///      and token metadata from the market itself.
    struct DeployParams {
        address governance;
        address defaultDeclarer; // zero unless a Loan Agreement names one
        address seniorGate;      // zero = senior open (sanctions-only)
        address juniorGate;      // mandatory
        uint256 seniorShareBips;
        uint256 minJuniorBips;
        uint256 defaultPenaltyWindow;
        bool borrowerRecovery;
    }

    function deployTranches(address market, DeployParams calldata p) external returns (address controllerAddr) {
        require(msg.sender == IWildcatMarket(market).borrower(), "ONLY_BORROWER");
        require(archController.isRegisteredMarket(market), "MARKET_NOT_REGISTERED");

        // One live set per market. Replacement (supersession) only once the incumbent is wound
        // down or empty; a retired set keeps paying claims forever, the registry just moves on.
        address incumbent = controllerForMarket[market];
        if (incumbent != address(0)) {
            TrancheController old = TrancheController(incumbent);
            bool wound = old.status() == TrancheController.Status.WindDown;
            bool empty = old.senior().totalSupply() == 0 && old.junior().totalSupply() == 0;
            require(wound || empty, "INCUMBENT_LIVE");
        }

        // Resolve the market's canonical 4626 wrapper; bring it into existence if it is missing.
        // The wrapper factory is permissionless and enforces one wrapper per market, so this is
        // idempotent, and the "a market must have a wrapping facility" rule is made true rather
        // than checked.
        address wrapper = wrapperFactory.wrapperForMarket(market);
        if (wrapper == address(0)) {
            wrapper = wrapperFactory.createWrapper(market);
        }

        TrancheController c = new TrancheController(
            TrancheController.Params({
                underlyingVault: wrapper,
                sentinel: sentinel,
                governance: p.governance,
                defaultDeclarer: p.defaultDeclarer,
                seniorGate: p.seniorGate,
                juniorGate: p.juniorGate,
                seniorShareBips: p.seniorShareBips,
                minJuniorBips: p.minJuniorBips,
                defaultPenaltyWindow: p.defaultPenaltyWindow,
                shareDecimals: 18,
                borrowerRecovery: p.borrowerRecovery
            })
        );

        if (incumbent != address(0)) {
            emit TranchesSuperseded(market, incumbent, address(c));
        }
        controllerForMarket[market] = address(c);
        allControllers.push(address(c));
        controllerAddr = address(c);
        emit TranchesDeployed(market, wrapper, controllerAddr, address(c.senior()), address(c.junior()));
    }

    function controllersLength() external view returns (uint256) {
        return allControllers.length;
    }
}
