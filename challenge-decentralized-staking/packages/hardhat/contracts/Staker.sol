// SPDX-License-Identifier: MIT
pragma solidity 0.8.20; //Do not change the solidity version as it negatively impacts submission grading

import "hardhat/console.sol";
import "./ExampleExternalContract.sol";

contract Staker {
    ExampleExternalContract public exampleExternalContract;

    // Mapping lưu số dư của từng người dùng
    mapping(address => uint256) public balances;

    // Ngưỡng tối thiểu để chuyển tiền sang contract ngoài
    uint256 public constant threshold = 1 ether;

    // Thời hạn kết thúc việc stake
    uint256 public deadline = block.timestamp + 72 hours;

    // Trạng thái cho phép rút tiền nếu không đạt threshold
    bool public openForWithdraw = false;

    // Event để theo dõi lịch sử stake
    event Stake(address indexed staker, uint256 amount);

    constructor(address exampleExternalContractAddress) {
        exampleExternalContract = ExampleExternalContract(exampleExternalContractAddress);
    }

    // Hàm stake() cho phép người dùng gửi ETH vào contract
    function stake() public payable {
        // Cập nhật số dư người gửi
        balances[msg.sender] += msg.value;
        // Phát event
        emit Stake(msg.sender, msg.value);
    }

    // Hàm execute() quyết định số phận của số ETH đã gom được sau khi hết hạn
    function execute() public {
        require(block.timestamp >= deadline, "Deadline has not passed yet");

        if (address(this).balance >= threshold) {
            // Nếu đủ tiền, gửi sang ExampleExternalContract
            exampleExternalContract.complete{value: address(this).balance}();
        } else {
            // Nếu không đủ tiền, cho phép mọi người rút lại
            openForWithdraw = true;
        }
    }

    // Hàm withdraw() cho phép rút lại tiền nếu không đạt threshold
    function withdraw() public {
        require(openForWithdraw, "Withdrawals are not open");
        uint256 amount = balances[msg.sender];
        require(amount > 0, "Nothing to withdraw");

        balances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Failed to send Ether");
    }

    // Hàm timeLeft() trả về thời gian còn lại trước deadline
    function timeLeft() public view returns (uint256) {
        if (block.timestamp >= deadline) {
            return 0;
        }
        return deadline - block.timestamp;
    }

    // Hàm receive() để nhận ETH và gọi stake()
    receive() external payable {
        stake();
    }
}
