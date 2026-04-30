// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {dTSLA} from "../src/dTSLA.sol";

contract DeployDTsla is Script {
    string constant alpacaMintSource = "./functions/sources/alpacaBalance.js";
    string constant alpacaRedeemSource = "";
    uint64 constant subId = 6524;

    function run() public {
        string memory mintSource = vm.readFile(alpacaMintSource);
        vm.startBroadcast();
        dTSLA dTsla = new dTSLA(mintSource, subId, alpacaRedeemSource);
        vm.stopBroadcast();
        console.log("dTSLA deployed to:", address(dTsla));
    }
}
