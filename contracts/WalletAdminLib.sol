pragma solidity ^0.4.23;

/**
 * @title Wallet Admin Library
 * @author Modular.network
 *
 * version 1.2.0
 * Copyright (c) 2017 Modular, Inc
 * The MIT License (MIT)
 * https://github.com/Modular-Network/ethereum-libraries/blob/master/LICENSE
 *
 * The Wallet Library family is inspired by the multisig wallets built by Consensys
 * at https://github.com/ConsenSys/MultiSigWallet and Parity at
 * https://github.com/paritytech/contracts/blob/master/Wallet.sol with added
 * functionality. Modular works on open source projects in the Ethereum
 * community with the purpose of testing, documenting, and deploying reusable
 * code onto the blockchain to improve security and usability of smart contracts.
 * Modular also strives to educate non-profits, schools, and other community
 * members about the application of blockchain technology. For further
 * information: modular.network, consensys.net, paritytech.io
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
 * IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
 * CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
 * TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
 * SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

import "./WalletMainLib.sol";

library WalletAdminLib {
  using WalletMainLib for WalletMainLib.WalletData;

  uint256 constant CHANGEOWNER = 1;
  uint256 constant ADDOWNER = 2;
  uint256 constant REMOVEOWNER = 3;
  uint256 constant CHANGEREQUIRED = 4;
  uint256 constant CHANGETHRESHOLD = 5;

  /*Events*/
  event LogTransactionConfirmed(bytes32 txid, address sender, uint256 confirmsNeeded);
  event LogOwnerAdded(address newOwner);
  event LogOwnerRemoved(address ownerRemoved);
  event LogOwnerChanged(address from, address to);
  event LogRequirementChange(uint256 newRequired);
  event LogThresholdChange(address token, uint256 newThreshold);
  event LogErrorMsg(uint256 amount, string msg);

  /*Checks*/

  /// @dev Validates arguments for changeOwner function
  /// @param _from Index of current owner removing
  /// @param _to Index of new potential owner, should be 0
  /// @return Returns true if check passes, false otherwise
  function checkChangeOwnerArgs(uint256 _from, uint256 _to)
           private returns (bool)
  {
    if(_from == 0){
      emit LogErrorMsg(_from, "Change from address is not an owner");
      return false;
    }
    if(_to != 0){
      emit LogErrorMsg(_to, "Change to address is an owner");
      return false;
    }
    return true;
  }

  /// @dev Validates arguments for addOwner function
  /// @param _index Index of new owner, should be 0
  /// @param _length Current length of owner array
  /// @return Returns true if check passes, false otherwise
  function checkNewOwnerArgs(uint256 _index, uint256 _length, uint256 _max)
           private returns (bool)
  {
    if(_index != 0){
      emit LogErrorMsg(_index, "New owner already owner");
      return false;
    }
    if((_length + 1) > _max){
      emit LogErrorMsg(_length, "Too many owners");
      return false;
    }
    return true;
  }

  /// @dev Validates arguments for removeOwner function
  /// @param _index Index of owner removing
  /// @param _length Current number of owners
  /// @param _min Minimum owners currently required to meet sig requirements
  /// @return Returs true if check passes, false otherwise
  function checkRemoveOwnerArgs(uint256 _index, uint256 _length, uint256 _min)
           private returns (bool)
  {
    if(_index == 0){
      emit LogErrorMsg(_index, "Owner removing not an owner");
      return false;
    }
    if(_length - 2 < _min) {
      emit LogErrorMsg(_index, "Must reduce requiredAdmin first");
      return false;
    }
    return true;
  }

  /// @dev Validates arguments for changing any of the sig requirement parameters
  /// @param _newRequired The new sig requirement
  /// @param _length Current number of owners
  /// @return Returns true if checks pass, false otherwise
  function checkRequiredChange(uint256 _newRequired, uint256 _length)
           private returns (bool)
  {
    if(_newRequired == 0){
      emit LogErrorMsg(_newRequired, "Cant reduce to 0");
      return false;
    }
    if(_length - 2 < _newRequired){
      emit LogErrorMsg(_length, "Making requirement too high");
      return false;
    }
    return true;
  }

  /// @dev adds/removes confirmations for new or existing transactions
  /// @param _checkID The ID of the type of transaction
  /// @param _confirm bool that shows if the owner is confirming or revoking the transaction
  /// @param _id  ID hash of the transaction and parameters
  /// @param _from address being removed as an owner
  /// @param _to either the address being added as an owner or the new number of confirmations/threshold. Had to combine the two because of stack depth issues
  function updateAdminConfirms(WalletMainLib.WalletData storage self, 
                        uint256 _checkID, 
                        bool _confirm, 
                        bytes32 _id, 
                        address _from, 
                        address _to) private returns (bool,uint256) 
  {
    uint256 _txIndex = self.transactionInfo[_id].length;
    bool allGood;
    // ensure that it is a valid transaction type
    require((_checkID > 0) && (_checkID <= 5));

    if(msg.sender != address(this)) {
      // caller is an external address
      if(!_confirm) {
        //revoke the callers confirmation
        allGood = self.revokeConfirm(_id);
        return (allGood,_txIndex);
      } else { // the caller is trying to confirm a new or existing change

        // if it is a new transaction or if the last same transaction has already succeeded, (new transaction)
        if(_txIndex == 0 || self.transactionInfo[_id][_txIndex - 1].success){
          require(self.ownerIndex[msg.sender] > 0);  // require that the sender is an owner
          
          if (_checkID == CHANGEOWNER) {
            //require(_to != 0);
            allGood = checkChangeOwnerArgs(self.ownerIndex[_from], self.ownerIndex[_to]);
          } else if (_checkID == ADDOWNER) {
            require(_to != 0);
            allGood = checkNewOwnerArgs(self.ownerIndex[_to],
                                        self.owners.length,
                                        self.maxOwners);
          } else if (_checkID == REMOVEOWNER) {
            allGood = checkRemoveOwnerArgs(self.ownerIndex[_from],
                                           self.owners.length,
                                           self.requiredAdmin);
          } else if (_checkID == CHANGEREQUIRED) {
            allGood = checkRequiredChange(uint256(_to), self.owners.length);
          }

          if((_checkID != CHANGETHRESHOLD) && (!allGood)) {
            return (false,0);
          }

          self.transactionInfo[_id].length++;  // add the new transaction
          self.transactionInfo[_id][_txIndex].confirmRequired = self.requiredAdmin;  // set the number of required signatures
          self.transactionInfo[_id][_txIndex].day = now / 1 days;   // set the date of the transaction
          self.transactions[now / 1 days].push(_id);  // add this transaction to the day's record
        } else { // means this is an existing transaction
          _txIndex--;
          allGood = self.checkNotConfirmed(_id, _txIndex);  // check that the sender has not already confirmed
          if(!allGood)
            return (false,0);
        }
      }
      // add the sender to the list of confirmed owners and update the confirm count
      self.transactionInfo[_id][_txIndex].confirmedOwners[msg.sender] = true;
    } else {
      // this means the contract sent it
      _txIndex--;
    }

    return (true,_txIndex);
  }

  /*Administrative Functions*/

  /// @dev Changes owner address to a new address
  /// @param self Wallet in contract storage
  /// @param _from Current owner address
  /// @param _to New address
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function changeOwner(WalletMainLib.WalletData storage self,
                       address _from,
                       address _to,
                       bool _confirm,
                       bytes _data)
                       external
                       returns (bool,bytes32)
  {
    bytes32 _id = keccak256("changeOwner",_from,_to);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,CHANGEOWNER,_confirm,_id,_from,_to);
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      uint256 i = self.ownerIndex[_from];
      self.ownerIndex[_from] = 0;
      self.owners[i] = _to;
      self.ownerIndex[_to] = i;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogOwnerChanged(_from, _to);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
    }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Adds owner to wallet
  /// @param self Wallet in contract storage
  /// @param _newOwner Address for new owner
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function addOwner(WalletMainLib.WalletData storage self,
                    address _newOwner,
                    bool _confirm,
                    bytes _data)
                    external
                    returns (bool,bytes32)
  {
    bytes32 _id = keccak256("addOwner",_newOwner);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,ADDOWNER,_confirm,_id,0,_newOwner);
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.owners.push(_newOwner);
      self.ownerIndex[_newOwner] = self.owners.length - 1;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogOwnerAdded(_newOwner);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Removes owner from wallet
  /// @param self Wallet in contract storage
  /// @param _ownerRemoving Address of owner to be removed
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function removeOwner(WalletMainLib.WalletData storage self,
                       address _ownerRemoving,
                       bool _confirm,
                       bytes _data)
                       external
                       returns (bool,bytes32)
  {
    bytes32 _id = keccak256("removeOwner",_ownerRemoving);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,REMOVEOWNER,_confirm,_id,_ownerRemoving,0);
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.owners[self.ownerIndex[_ownerRemoving]] = self.owners[self.owners.length - 1];
      self.ownerIndex[self.owners[self.owners.length - 1]] = self.ownerIndex[_ownerRemoving];
      self.ownerIndex[_ownerRemoving] = 0;
      self.owners.length--;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogOwnerRemoved(_ownerRemoving);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Changes required sigs to change wallet parameters
  /// @param self Wallet in contract storage
  /// @param _requiredAdmin The new signature requirement
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function changeRequiredAdmin(WalletMainLib.WalletData storage self,
                               uint256 _requiredAdmin,
                               bool _confirm,
                               bytes _data)
                               external
                               returns (bool,bytes32)
  {
    bytes32 _id = keccak256("changeRequiredAdmin",_requiredAdmin);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,CHANGEREQUIRED,_confirm,_id,0,address(_requiredAdmin));
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.requiredAdmin = _requiredAdmin;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogRequirementChange(_requiredAdmin);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Changes required sigs for major transactions
  /// @param self Wallet in contract storage
  /// @param _requiredMajor The new signature requirement
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function changeRequiredMajor(WalletMainLib.WalletData storage self,
                               uint256 _requiredMajor,
                               bool _confirm,
                               bytes _data)
                               external
                               returns (bool,bytes32)
  {
    bytes32 _id = keccak256("changeRequiredMajor",_requiredMajor);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,CHANGEREQUIRED,_confirm,_id,0,address(_requiredMajor));
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.requiredMajor = _requiredMajor;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogRequirementChange(_requiredMajor);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Changes required sigs for minor transactions
  /// @param self Wallet in contract storage
  /// @param _requiredMinor The new signature requirement
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function changeRequiredMinor(WalletMainLib.WalletData storage self,
                               uint256 _requiredMinor,
                               bool _confirm,
                               bytes _data)
                               external
                               returns (bool,bytes32)
  {
    bytes32 _id = keccak256("changeRequiredMinor",_requiredMinor);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,CHANGEREQUIRED,_confirm,_id,0,address(_requiredMinor));
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.requiredMinor = _requiredMinor;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogRequirementChange(_requiredMinor);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}

  /// @dev Changes threshold for major transaction day spend per token
  /// @param self Wallet in contract storage
  /// @param _token Address of token, ether is 0
  /// @param _majorThreshold New threshold
  /// @param _confirm True if confirming, false if revoking confirmation
  /// @param _data Message data passed from wallet contract
  /// @return bool Returns true if successful, false otherwise
  /// @return bytes32 Returns the tx ID, can be used for confirm/revoke functions
  function changeMajorThreshold(WalletMainLib.WalletData storage self,
                                address _token,
                                uint256 _majorThreshold,
                                bool _confirm,
                                bytes _data)
                                external
                                returns (bool,bytes32)
  {
    bytes32 _id = keccak256("changeMajorThreshold", _token, _majorThreshold);
    uint256 _txIndex;
    bool allGood;

    (allGood,_txIndex) = updateAdminConfirms(self,CHANGETHRESHOLD,_confirm,_id,0,0);
    if(msg.sender != address(this)) {
      if(!_confirm) {
        return (allGood,_id);
      } else {
        if (!allGood) {
          return (false,_id);
        }
      }
    }

    if(self.checkConfirmationsComplete(_id,_txIndex))
    {
      self.transactionInfo[_id][_txIndex].success = true;
      self.majorThreshold[_token] = _majorThreshold;
      delete self.transactionInfo[_id][_txIndex].data;
      emit LogThresholdChange(_token, _majorThreshold);
    } else {
      if(self.transactionInfo[_id][_txIndex].data.length == 0) {
        self.transactionInfo[_id][_txIndex].data = _data;
      }
      self.findConfirmsNeeded(_id, _txIndex);
    }

    return (true,_id);
	}
}
