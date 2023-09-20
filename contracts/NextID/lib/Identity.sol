//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * TAKE CARE !!! if the platform is Ethereum! please use lowercase for identityValue
 */
struct Identity {
    string platform;
    string identityValue;
    address chainIdentity;
}
