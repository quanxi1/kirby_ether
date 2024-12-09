// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "src/Relayer.sol";

contract RelayerTest is Test {
    Relayer relayer;
    address[] nonPermitTokensSamples;
    address[] permitTokensSamples;
    address[] users;
    address target;

    function setUp() public {
        for (uint i = 0; i < 3; i++) {
            nonPermitTokensSamples.push(
                address(new MockERC20("", "", 100 ether))
            );
            permitTokensSamples.push(
                address(new MockERC20WithPermit("", "", 100 ether))
            );
            users.push(vm.addr(i + 1));
        }
        target = vm.addr(4);
        relayer = new Relayer(permitTokensSamples, nonPermitTokensSamples);

        for (uint i = 0; i < users.length; i++) {
            for (uint j = 0; j < 3; j++) {
                MockERC20(nonPermitTokensSamples[j]).mint(users[i], 10 ether);
                MockERC20WithPermit(permitTokensSamples[j]).mint(
                    users[i],
                    10 ether
                );
            }
        }
        address[] memory tokens = new address[](
            permitTokensSamples.length + nonPermitTokensSamples.length
        );
        for (uint256 i = 0; i < 3; i++) {
            tokens[i] = address(permitTokensSamples[i]);
            tokens[i + 3] = address(nonPermitTokensSamples[i]);
        }
        vm.prank(users[0]);
        relayer.registerUser(tokens, users);
    }

    function testSweep() public {
        address[] memory tokensToSweep = new address[](6);
        for (uint256 i = 0; i < 3; i++) {
            tokensToSweep[i] = address(permitTokensSamples[i]);
            tokensToSweep[i + 3] = address(nonPermitTokensSamples[i]);
        }

        uint256 deadline = block.timestamp + 1 days;
        uint256[] memory deadlines = new uint256[](9);
        for (uint i = 0; i < 9; i++) {
            deadlines[i] = deadline;
        }

        for (uint256 i = 3; i < 6; i++) {
            for (uint256 j = 0; j < 3; j++) {
                vm.prank(users[j]);
                MockERC20(nonPermitTokensSamples[i - 3]).approve(
                    address(relayer),
                    10 ether
                );
            }
        }

        bytes[] memory signatures = new bytes[](9);
        uint count = 0;
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                uint256 nonce = MockERC20WithPermit(permitTokensSamples[i])
                    .nonces(users[j]);
                bytes32 permitHash = keccak256(
                    abi.encode(
                        MockERC20WithPermit(permitTokensSamples[i])
                            .PERMIT_TYPEHASH(),
                        users[j],
                        address(relayer),
                        10 ether,
                        nonce,
                        deadline
                    )
                );

                bytes32 digest = keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        MockERC20WithPermit(permitTokensSamples[i])
                            .DOMAIN_SEPARATOR(),
                        permitHash
                    )
                );

                (uint8 v, bytes32 r, bytes32 s) = vm.sign(j + 1, digest);
                signatures[count] = (abi.encodePacked(r, s, v));
                count++;
            }
        }

        vm.prank(users[0]);
        relayer.sweep(users[0], target, signatures, deadlines);

        for (uint256 i = 0; i < 3; i++) {
            assertEq(
                MockERC20WithPermit(permitTokensSamples[i]).balanceOf(target),
                30 ether,
                "Permit token balance mismatch"
            );
            assertEq(
                MockERC20(nonPermitTokensSamples[i]).balanceOf(target),
                30 ether,
                "Non-Permit token balance mismatch"
            );

            for (uint256 j = 0; j < 3; j++) {
                assertEq(
                    MockERC20WithPermit(permitTokensSamples[i]).balanceOf(
                        users[j]
                    ),
                    0 ether,
                    "Permit token sub-account balance mismatch"
                );
                assertEq(
                    MockERC20(nonPermitTokensSamples[i]).balanceOf(users[j]),
                    0 ether,
                    "Non-Permit token sub-account balance mismatch"
                );
            }
        }
    }
}
