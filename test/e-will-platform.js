const EWillToken = artifacts.require("EWillToken");
const EWillEscrow = artifacts.require("EWillEscrow");
const EWillAccount = artifacts.require("EWillAccount");
const EWillFinance = artifacts.require("EWillFinance");
const EWillPlatform = artifacts.require("EWillPlatform");
const keccak256 = require('js-sha3').keccak256;
const BN = require('bn.js');
const TestUtils = require('./test-utils.js');

contract('EWillPlatform', function(accounts) {
  const admin = accounts[0];
  const user  = accounts[1];
  const prov  = accounts[2];
  const benf  = accounts[3];
  const deleg = accounts[0];
  //todo: add tests for delegating

  const willId = (new BN(prov.slice(2), 16)).iushln(96).iadd(new BN(0x31111d, 16)).toString(10);
  const ewTokenSupply = 100.0e+21;

  const ProviderState = {
    None: 0,
    Pending: 1,
    Whitlisted: 2,
    Activated: 3,
    Banned: 4
  };

  const WillState = {
    None: 0,
    Created: 1,
    Activated: 2,
    Pending: 3,
    Claimed: 4,
    Declined: 5
  };

  const TOKEN_SUPPLY = 100.0e+21;   // 100,000 EWILLs
  const PLATFORM_FEE = 1500;        // cents, $15
  const PROVIDER_FEE = 2000;        // cents, $20
  const REFFERER_RWD = 10;          // %
  const RATE_TOKEN   = 1.0e+14;     // tokenweis per cent, 100 $/EWILL
  const RATE_ETHER   = 1.0e+13;     // weis per cent, 1000 $/Ether

  let ewPlatform = null;
  let ewFinance = null;
  let ewAccount = null;
  let ewEscrow = null;
  let ewToken = null;

  it("should have a correct name", async () => {
    ewToken = await EWillToken.new(ewTokenSupply);
    ewEscrow = await EWillEscrow.new(ewToken.address, 70);
    ewAccount = await EWillAccount.new(ewToken.address, 1000, admin);
    ewFinance = await EWillFinance.new(PLATFORM_FEE / 2, ewAccount.address, ewEscrow.address, ewToken.address);
    ewPlatform = await EWillPlatform.new(ewFinance.address, ewEscrow.address);

    await ewFinance.setPlatform(ewPlatform.address);
    await ewAccount.setFinance(ewFinance.address);
    await ewEscrow.setFinance(ewFinance.address);
    await ewToken.transfer(user, 15.0e+18);
    await ewToken.transfer(prov, 150.0e+18);
    await ewToken.transfer(ewFinance.address, 5.0e+21);

    const name = await ewPlatform.name.call();
    assert.equal(name, 'E-Will Platform', 'the contract has the wrong name');
  });

  it("should configure the contract", async () => {
    let txResult;
    await ewToken.addMerchant(ewEscrow.address);
    await ewToken.addMerchant(ewAccount.address);
    await ewToken.addMerchant(ewFinance.address);

    txResult = await ewFinance.setAnnaulPlatformFee(500, { from: admin });
    // 1 ether == $1000, 1 EWILL == $100
    txResult = await ewFinance.setExchangeRates(1.0e+14, 1.0e+13, { from: admin });
    txResult = await ewPlatform.setAnnaulProviderFee(1000, { from: prov });

    const annualPlatformFee = await ewFinance.annualPlatformFee.call();
    const annualProviderFee = await ewPlatform.annualProviderFee.call(prov);
    assert.equal(annualPlatformFee.toString(), '500', 'the contract has the wrong Annual Platform Fee');
    assert.equal(annualProviderFee.toString(), '1000', 'the contract has the wrong Annual Provider Fee');

    txResult = await ewEscrow.register(0x0badfeed, deleg, { from: prov });
    txResult = await ewEscrow.activateProvider(prov, ProviderState.Activated, { from: admin });
    txResult = await ewEscrow.topup(75.0e+18, { from: prov });
  });

  it("should create a will", async () => {
    let txResult, txEvent;

    let benHash = (new BN(benf.slice(2), 16)).toBuffer();
    benHash = new BN(keccak256(benHash), 16);

    txResult = await ewPlatform.createWill(willId, 0x5108a9e, benHash.toString(10), prov, '0' /*todo: referrer*/, { from: user, value: 20.0e+15 });
    txEvent = TestUtils.findEvent(txResult.logs, 'WillCreated');
    assert.equal(txEvent.args.willId.toString(10).toString(10), willId, 'the will is created with the wrong ID');
    assert.equal(txEvent.args.owner, user, 'the will is created for the wrong user');
    assert.equal(txEvent.args.provider, prov, 'the will is created for the wrong provider');

    txEvent = TestUtils.findEvent(txResult.logs, 'WillStateUpdated');
    assert.equal(txEvent.args.willId.toString(10).toString(10), willId, 'the will is created with the wrong ID');
    assert.equal(txEvent.args.owner, user, 'the will is created for the wrong user');
    assert.equal(txEvent.args.newState, WillState.Created, 'the will is created with the wrong state');
  });

  it("should activate the will", async () => {
    let txResult, txEvent;

    txResult = await ewPlatform.activateWill(willId, { from: prov });
    txEvent = TestUtils.findEvent(txResult.logs, 'WillStateUpdated');
    assert.equal(txEvent.args.willId.toString(10), willId, 'the will is created with the wrong ID');
    assert.equal(txEvent.args.owner, user, 'the will is created for the wrong user');
    assert.equal(txEvent.args.newState, WillState.Activated, 'the will is activated with the wrong state');
  });

  it("should apply the will", async () => {
    let txResult, txEvent;

    txResult = await ewPlatform.applyWill(willId, 0xe4c6, { from: prov });
    txEvent = TestUtils.findEvent(txResult.logs, 'WillStateUpdated');
    assert.equal(txEvent.args.willId.toString(10), willId, 'the will is created with the wrong ID');
    assert.equal(txEvent.args.owner, user, 'the will is created for the wrong user');
    assert.equal(txEvent.args.newState, WillState.Pending, 'the will is applied with the wrong state');
  });

  it("should claim the will", async () => {
    let txResult, txEvent;

    txResult = await ewPlatform.claimWill(willId, { from: benf });
    txEvent = TestUtils.findEvent(txResult.logs, 'WillStateUpdated');
    assert.equal(txEvent.args.willId.toString(10), willId, 'the will is created with the wrong ID');
    assert.equal(txEvent.args.owner, user, 'the will is created for the wrong user');
    assert.equal(txEvent.args.newState, WillState.Claimed, 'the will is claimed with the wrong state');
  });

/*
  it("should return user's will id", async () => {
    let txResult, txEvent;

    txResult = await ewPlatform.userWills(user, 0, { from: user });
    console.log(txResult);
    txResult = await ewPlatform.userWills(user, 1, { from: user });
    console.log(txResult);
  });
*/

  it("should not decline the will", async () => {
    let txResult, txEvent;

    try {
      txResult = await ewPlatform.declineWill(willId, { from: prov });
      txEvent = TestUtils.findEvent(txResult.logs, 'WillStateUpdated');
      assert.isNull(txEvent, 'the will declined although should not');
    } catch (err) {
      assert.isNotNull(err, 'the will declined although should not');
    }
  });
});
