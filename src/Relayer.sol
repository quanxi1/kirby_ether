// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./MockERC20.sol";
import "./MockERC20WithPermit.sol";

contract Relayer {
    using ECDSA for bytes32;

    struct UserInfo {
        address[] subAccounts;
        address[] permitTokens;
        address[] nonPermitTokens;
    }
    mapping(address => UserInfo) userInfos;
    mapping(address => bool) registered;

    mapping(address => bool) public validPermitTokens;
    mapping(address => bool) public validNonPermitTokens;

    address public owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "Not authorized");
        _;
    }

    constructor(
        address[] memory permitTokens,
        address[] memory nonPermitTokens
    ) {
        owner = msg.sender;
        for (uint i = 0; i < permitTokens.length; i++) {
            validPermitTokens[permitTokens[i]] = true;
        }
        for (uint i = 0; i < nonPermitTokens.length; i++) {
            validNonPermitTokens[nonPermitTokens[i]] = true;
        }
    }

    function registerUser(
        address[] calldata tokens,
        address[] calldata subAccounts
    ) external {
        require(tokens.length > 0, "No tokens provided");
        require(subAccounts.length > 0, "No subaccounts provided");
        require(!registered[msg.sender], "User already registered");
        UserInfo storage user = userInfos[msg.sender];

        for (uint256 i = 0; i < tokens.length; i++) {
            if (validPermitTokens[tokens[i]]) {
                user.permitTokens.push(tokens[i]);
            } else if (validNonPermitTokens[tokens[i]]) {
                user.nonPermitTokens.push(tokens[i]);
            } else {
                revert("Invalid token address");
            }
        }

        user.subAccounts = subAccounts;
    }

    function sweep(
        address user,
        address destination,
        bytes[] calldata permitSignatures,
        uint256[] calldata permitDeadlines
    ) external {
        UserInfo storage userInfo = userInfos[user];

        uint count = 0;
        for (uint256 i = 0; i < userInfo.permitTokens.length; i++) {
            address token = userInfo.permitTokens[i];
            for (uint256 j = 0; j < userInfo.subAccounts.length; j++) {
                address subAccount = userInfo.subAccounts[j];
                uint256 balance = IERC20(token).balanceOf(subAccount);
                if (balance > 0) {
                    {
                        bytes calldata signature = permitSignatures[count];
                        uint256 deadline = permitDeadlines[count];
                        (uint8 v, bytes32 r, bytes32 s) = _splitSignature(
                            signature
                        );
                        IERC20Permit(token).permit(
                            subAccount,
                            address(this),
                            balance,
                            deadline,
                            v,
                            r,
                            s
                        );
                    }
                    IERC20(token).transferFrom(
                        subAccount,
                        destination,
                        balance
                    );
                    count++;
                }
            }
        }

        for (uint256 i = 0; i < userInfo.nonPermitTokens.length; i++) {
            address token = userInfo.nonPermitTokens[i];
            for (uint256 j = 0; j < userInfo.subAccounts.length; j++) {
                address subAccount = userInfo.subAccounts[j];
                uint256 balance = IERC20(token).balanceOf(subAccount);
                if (balance > 0) {
                    require(
                        IERC20(token).allowance(subAccount, address(this)) >=
                            balance,
                        "Token not approved"
                    );
                    IERC20(token).transferFrom(
                        subAccount,
                        destination,
                        balance
                    );
                }
            }
        }
    }

    function _splitSignature(
        bytes memory signature
    ) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        require(signature.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
    }

    function addValidToken(
        address token,
        bool isPermitToken
    ) external onlyOwner {
        if (isPermitToken) {
            validPermitTokens[token] = true;
        } else {
            validNonPermitTokens[token] = true;
        }
    }
}
