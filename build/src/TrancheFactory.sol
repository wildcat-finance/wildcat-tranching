// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {TrancheManager} from "./TrancheManager.sol";
import {IUnderlying4626, IArchControllerLike} from "./interfaces/IExternal.sol";

/// @title TrancheFactory
/// @notice Protocol-level factory for senior/junior tranche sets, one per Wildcat market.
/// @dev Mirrors `Wildcat4626WrapperFactory`: takes the `WildcatArchController` and gates
///      deployment on `isRegisteredMarket`, so tranching rides the protocol's own deployment
///      rails. Derives the market from the wrapper (`underlying.market()`). One set per market.
contract TrancheFactory {
    IArchControllerLike public immutable archController;
    /// @notice Only the owner may deploy tranche sets. Deployment is caller-supplied (governance,
    ///         sentinel, the vault itself), so leaving it open lets anyone front-run and squat the
    ///         canonical managerForMarket slot, or register a fake vault whose market() returns a
    ///         real registered market. Gating to a trusted owner closes both.
    address public owner;
    address public pendingOwner;

    mapping(address => address) public managerForMarket; // market => TrancheManager
    address[] public allManagers;

    event TrancheManagerDeployed(
        address indexed market, address indexed underlying, address manager, address senior, address junior
    );
    event OwnerProposed(address indexed pending);
    event OwnerTransferred(address indexed from, address indexed to);

    constructor(address _archController) {
        require(_archController != address(0), "ZERO_ARCH");
        archController = IArchControllerLike(_archController);
        owner = msg.sender;
        emit OwnerTransferred(address(0), msg.sender);
    }

    /// @notice Two-step ownership transfer, mirroring TrancheManager's governance rotation: the
    ///         owner proposes a successor who must accept, so ownership can never be stranded on a
    ///         typo'd or uncontrolled address.
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

    function deployTranches(DeployParams calldata p) external returns (address managerAddr) {
        require(msg.sender == owner, "ONLY_OWNER");
        require(p.governance != address(0), "ZERO_GOV");
        require(p.sentinel != address(0), "ZERO_SENTINEL");
        require(p.borrower != address(0), "ZERO_BORROWER");
        address market = IUnderlying4626(p.underlyingVault).market();
        require(archController.isRegisteredMarket(market), "MARKET_NOT_REGISTERED");
        require(managerForMarket[market] == address(0), "TRANCHES_EXIST");

        TrancheManager c = new TrancheManager(
            TrancheManager.Params({
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

        managerForMarket[market] = address(c);
        allManagers.push(address(c));
        managerAddr = address(c);
        emit TrancheManagerDeployed(market, p.underlyingVault, managerAddr, address(c.senior()), address(c.junior()));
    }

    function managersLength() external view returns (uint256) {
        return allManagers.length;
    }
}
