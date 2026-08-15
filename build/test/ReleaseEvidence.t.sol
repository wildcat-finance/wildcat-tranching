// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";

import {TrancheFactory} from "../src/TrancheFactory.sol";
import {TrancheManager} from "../src/TrancheManager.sol";

/// @notice Compile-time release gates for contracts introduced by this prototype.
/// @dev These checks use the production Foundry profile. Changing compiler or optimizer settings
///      therefore changes the measured artefacts and must pass this test again.
contract ReleaseEvidenceTest is Test {
    uint256 internal constant EIP_170_RUNTIME_LIMIT = 24_576;
    uint256 internal constant EIP_3860_INITCODE_LIMIT = 49_152;

    function test_releaseArtefactsFitEthereumCodeLimits() public {
        assertLt(_runtimeSize("TrancheFactory.sol:TrancheFactory"), EIP_170_RUNTIME_LIMIT, "factory runtime");
        assertLt(_runtimeSize("TrancheFactory.sol:TrancheManagerDeployer"), EIP_170_RUNTIME_LIMIT, "deployer runtime");
        assertLt(_runtimeSize("TrancheManager.sol:TrancheManager"), EIP_170_RUNTIME_LIMIT, "manager runtime");
        assertLt(_runtimeSize("TrancheOpenTermHooks.sol:TrancheOpenTermHooks"), EIP_170_RUNTIME_LIMIT, "hooks runtime");
        assertLt(_runtimeSize("TrancheToken.sol:TrancheToken"), EIP_170_RUNTIME_LIMIT, "tranche token runtime");

        bytes memory factoryInitCode =
            abi.encodePacked(type(TrancheFactory).creationCode, abi.encode(address(1), address(2), address(3)));
        bytes memory managerInitCode = abi.encodePacked(type(TrancheManager).creationCode, abi.encode(address(1)));
        assertLt(factoryInitCode.length, EIP_3860_INITCODE_LIMIT, "factory initcode");
        assertLt(managerInitCode.length, EIP_3860_INITCODE_LIMIT, "manager initcode");
    }

    function _runtimeSize(string memory artifact) internal view returns (uint256) {
        return vm.getDeployedCode(artifact).length;
    }
}
