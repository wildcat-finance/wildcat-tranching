// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20} from "../lib/solady/src/tokens/ERC20.sol";

interface ITrancheManagerView {
    function beforeTrancheTransfer(address token, address from, address to, uint256 amount) external view;
    function trancheTotalAssets(bool isSenior) external view returns (uint256); // base-asset terms
    function underlying() external view returns (address);
}

/// @notice Tranche share token, built on Solady's ERC20 (incl. EIP-2612 permit). Mint/burn
///         and the canonical deposit / requestRedeem entrypoints live on the manager (which
///         holds the accounting logic); this token exposes an ERC-4626 *view* surface so integrators
///         read it as a standard vault. Transfers are gated by the manager (sanctions + junior whitelist).
/// @dev Redemption is async (ERC-7540 style) on the manager, so withdraw/redeem are not exposed
///      synchronously here; deposit + valuation views follow ERC-4626.
contract TrancheToken is ERC20 {
    string private _name;
    string private _symbol;
    uint8 private immutable _decimals;
    address public immutable manager;
    bool public immutable isSenior;

    modifier onlyManager() {
        require(msg.sender == manager, "ONLY_MANAGER");
        _;
    }

    constructor(string memory n, string memory s, uint8 d, bool _isSenior) {
        _name = n;
        _symbol = s;
        _decimals = d;
        isSenior = _isSenior;
        manager = msg.sender;
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

    // ---- manager-only supply ops ----
    function mint(address to, uint256 amount) external onlyManager {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyManager {
        _burn(from, amount);
    }

    /// @dev Gate real transfers (not mint/burn) through the manager's sanctions + whitelist checks.
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal view override {
        if (from != address(0) && to != address(0)) {
            ITrancheManagerView(manager).beforeTrancheTransfer(address(this), from, to, amount);
        }
    }

    // ---- ERC4626 view surface (asset = the Wildcat market's base asset) ----
    function asset() external view returns (address) {
        return ITrancheManagerView(manager).underlying();
    }

    function totalAssets() public view returns (uint256) {
        return ITrancheManagerView(manager).trancheTotalAssets(isSenior);
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
