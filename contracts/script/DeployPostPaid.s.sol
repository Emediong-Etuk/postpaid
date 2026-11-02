// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {PostPaidEscrow} from "../PostPaidEscrow.sol";

/// @notice Deploys PostPaidEscrow with the production constructor arguments.
/// @dev The signer is chosen on the command line (`--account <keystore>`), never in code.
///      Run against Arc mainnet (chain 5042) with maxFeePerGas >= 20 gwei.
contract DeployPostPaid is Script {
    IERC20 internal constant USDC = IERC20(0x3600000000000000000000000000000000000000); // Arc USDC (6 decimals)
    address internal constant OWNER = 0x553f9D115bCCafD5d4b4a254f2B2d6E23B66CA17; // Greg, wallet A
    address internal constant FEE_RECIPIENT = OWNER;
    uint16 internal constant FEE_BPS = 100; // 1%

    function run() external returns (PostPaidEscrow escrow) {
        require(block.chainid == 5042 || block.chainid == 5042002, "not an Arc network");
        require(address(USDC).code.length > 0, "USDC predeploy missing");
        vm.startBroadcast();
        escrow = new PostPaidEscrow(USDC, OWNER, FEE_RECIPIENT, FEE_BPS);
        vm.stopBroadcast();
        require(escrow.owner() == OWNER && escrow.feeRecipient() == FEE_RECIPIENT, "bad owner/fee recipient");
        require(escrow.protocolFeeBps() == FEE_BPS && address(escrow.usdc()) == address(USDC), "bad fee/usdc");
        console2.log("PostPaidEscrow deployed at", address(escrow));
    }
}
