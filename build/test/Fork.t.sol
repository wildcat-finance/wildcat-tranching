// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {IUnderlying4626, IWildcatMarket, MarketState} from "../src/interfaces/IExternal.sol";

/// @notice Read-only ABI smoke tests against the current canonical wrapper. A full manager fork
///         deployment needs a market pre-bound to its predicted singleton lender and belongs in
///         the deployment integration suite.
contract ForkTest is Test {
    string constant RPC = "https://eth-main.hinterlight.net";
    address constant WRAPPER = 0xF65460B84c13eeb911303336Ab0f9D63CC79839f;
    bool forked;

    function setUp() public {
        try vm.createSelectFork(RPC) {
            forked = true;
        } catch {}
    }

    function test_fork_wrapperAndMarketAbi() public {
        if (!forked) return;
        IUnderlying4626 wrapper = IUnderlying4626(WRAPPER);
        IWildcatMarket market = IWildcatMarket(wrapper.market());
        assertEq(wrapper.asset(), address(market));
        // The supplied address may still point at a V2 market while #124 is unmerged. Probe the
        // V2.5 getter without making deployment of that branch a prerequisite for this smoke test.
        (bool hasRegisteredWrapper, bytes memory data) =
            address(market).staticcall(abi.encodeWithSelector(IWildcatMarket.registeredWrapper.selector));
        if (hasRegisteredWrapper && data.length >= 32) assertEq(abi.decode(data, (address)), WRAPPER);
        MarketState memory state = market.currentState();
        assertGt(state.scaleFactor, 0);
    }
}
