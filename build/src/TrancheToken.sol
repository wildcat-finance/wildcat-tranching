// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "solady/tokens/ERC20.sol";

interface ITrancheControllerView {
    function beforeTrancheTransfer(address token, address from, address to, uint256 amount) external view;
    function trancheTotalAssets(bool isSenior) external view returns (uint256); // in underlying (v-wmtUSDC) share terms
    function underlying() external view returns (address);
}

/// @notice Tranche share token, built on Solady's ERC20 (incl. EIP-2612 permit). Mint/burn
///         and the canonical deposit / requestRedeem entrypoints live on the controller (which
///         holds the accounting logic); this token exposes an ERC-4626 *view* surface so integrators
///         read it as a standard vault. Transfers are gated by the controller (sanctions + junior whitelist).
/// @dev Redemption is async (ERC-7540 style) on the controller, so withdraw/redeem are not exposed
///      synchronously here; deposit + valuation views follow ERC-4626.
contract TrancheToken is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address public immutable controller;
    bool public immutable isSenior;

    modifier onlyController() {
        require(msg.sender == controller, "ONLY_CONTROLLER");
        _;
    }

    constructor(string memory n, string memory s, uint8 d, bool _isSenior) {
        _name = n;
        _symbol = s;
        _decimals = d;
        isSenior = _isSenior;
        controller = msg.sender;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    // ---- controller-only supply ops ----
    function mint(address to, uint256 amount) external onlyController {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyController {
        _burn(from, amount);
    }

    /// @dev Gate real transfers (not mint/burn) through the controller's sanctions + whitelist checks.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        if (from != address(0) && to != address(0)) {
            ITrancheControllerView(controller).beforeTrancheTransfer(address(this), from, to, amount);
        }
    }

    // ---- ERC4626 view surface (asset = the underlying v-wmtUSDC) ----
    function asset() external view returns (address) {
        return ITrancheControllerView(controller).underlying();
    }

    function totalAssets() public view returns (uint256) {
        return ITrancheControllerView(controller).trancheTotalAssets(isSenior);
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply();
        return supply == 0 ? shares : (shares * totalAssets()) / supply;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply();
        uint256 ta = totalAssets();
        return (supply == 0 || ta == 0) ? assets : (assets * supply) / ta;
    }

    function pricePerShare() external view returns (uint256) {
        return convertToAssets(1e18);
    }
}
