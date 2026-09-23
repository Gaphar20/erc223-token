// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC223Receiver} from "./IERC223Receiver.sol";

error InsufficientBalance(uint256 available, uint256 required);
error ReceiverRejected(address recipient);
error TransferToZeroAddress();

// ERC-223 receiver magic value.
bytes4 constant ERC223_MAGIC = 0x8943ec02;

contract ERC223Token {
    event Transfer(address indexed _from, address indexed _to, uint256 _value, bytes _data);

    string private _name;
    string private _symbol;
    uint8 private _decimals;
    uint256 private _totalSupply;

    mapping(address => uint256) private _balances;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 initialSupply) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        _totalSupply = initialSupply;
        _balances[msg.sender] = initialSupply;

        emit Transfer(address(0), msg.sender, initialSupply, "");
    }

    function name() external view returns (string memory) {
        return _name;
    }

    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address _owner) external view returns (uint256) {
        return _balances[_owner];
    }

    function transfer(address _to, uint256 _value) external returns (bool) {
        return _transfer(msg.sender, _to, _value, "");
    }

    function transfer(address _to, uint256 _value, bytes calldata _data) external returns (bool) {
        return _transfer(msg.sender, _to, _value, _data);
    }

    function _transfer(address _from, address _to, uint256 _value, bytes memory _data) internal returns (bool) {
        if (_to == address(0)) revert TransferToZeroAddress();
        if (_balances[_from] < _value) {
            revert InsufficientBalance(_balances[_from], _value);
        }

        // Update balances before calling the receiver hook.
        _balances[_from] -= _value;
        _balances[_to] += _value;

        // Call ERC-223 receiver hook if recipient is a contract.
        if (_to.code.length > 0) {
            bytes4 retval = IERC223Receiver(_to).tokenReceived(_from, _value, _data);
            if (retval != ERC223_MAGIC) {
                revert ReceiverRejected(_to);
            }
        }

        emit Transfer(_from, _to, _value, _data);
        return true;
    }
}

