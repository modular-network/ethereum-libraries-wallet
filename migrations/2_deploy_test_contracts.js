var BasicMathLib = artifacts.require("ethereum-libraries-basic-math/contracts/BasicMathLib.sol");
//var Array256Lib = artifacts.require("ethereum-libraries-array-utils/contracts/Array256Lib.sol");
var TokenLib = artifacts.require("ethereum-libraries-token/contracts/TokenLib.sol");
var TestToken = artifacts.require("./TestToken.sol");
var WalletMainLib = artifacts.require("./WalletMainLib.sol");
var WalletAdminLib = artifacts.require("./WalletAdminLib.sol");
var WalletGetterLib = artifacts.require("./WalletGetterLib.sol");
var WalletLibTestContract = artifacts.require("./WalletLibTestContract.sol");

module.exports = function(deployer, network, accounts) {
  deployer.deploy(BasicMathLib,{overwrite: false});
  //deployer.deploy(Array256Lib, {overwrite: false});
  deployer.link(BasicMathLib, WalletMainLib);
  //deployer.link(Array256Lib, WalletMainLib);
  deployer.deploy(WalletMainLib,{overwrite: false});
  deployer.link(WalletMainLib,WalletAdminLib);
  deployer.link(WalletMainLib,WalletGetterLib);
  deployer.deploy(WalletAdminLib,{overwrite: false});
  deployer.deploy(WalletGetterLib,{overwrite: false});
  deployer.link(BasicMathLib, TokenLib);
  deployer.deploy(TokenLib, {overwrite: false});

  if(network === "development" || network === "coverage"){
    deployer.link(WalletMainLib, WalletLibTestContract);
    deployer.link(WalletAdminLib, WalletLibTestContract);
    deployer.link(WalletGetterLib, WalletLibTestContract);
    deployer.deploy(WalletLibTestContract);
    deployer.link(TokenLib, TestToken);
    deployer.deploy(TestToken, accounts[1], "Tester Token", "TST", 18, 20000000000000000000000000, false, {from:accounts[5]});
  }
};
