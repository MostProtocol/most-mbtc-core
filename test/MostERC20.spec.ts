import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { BigNumber } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader, deployContract } from 'ethereum-waffle'

import { expandTo9Decimals, expandTo15Decimals, mineBlock } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'
import Oracle from '../build/MostOracle.json'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

const TOTAL_SUPPLY = expandTo9Decimals(420000)
const TEST_AMOUNT = expandTo9Decimals(10)
const tokenAmount = expandTo9Decimals(5)
const tokenLargeAmount = expandTo9Decimals(10)
const tokenAnotherAmount = expandTo15Decimals(10)
const tokenAnotherSmallAmount = expandTo15Decimals(5)
const tokenClose0Amount = expandTo9Decimals(50)
const tokenClose1Amount = expandTo15Decimals(52)

describe('MostERC20', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet, other] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token: Contract
  let token0: Contract
  let token1: Contract
  let pair: Contract
  let factory: Contract
  let orchestrator: Contract

  async function addLiquidity(amountA: BigNumber, amountB: BigNumber) {
    if (token0.address === token.address) {
      await token0.transfer(pair.address, amountA)
      await token1.transfer(pair.address, amountB)
    } else {
      await token0.transfer(pair.address, amountB)
      await token1.transfer(pair.address, amountA)
    }
    await pair.mint(wallet.address, overrides)
  }

  beforeEach(async () => {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    token = fixture.token
    pair = fixture.pair
    factory = fixture.factoryV2
    orchestrator = fixture.orchestrator
  })

  it('name, symbol, decimals, totalSupply, balanceOf', async () => {
    const name = await token.name()
    expect(name).to.eq('mBTC')
    expect(await token.symbol()).to.eq('mBTC')
    expect(await token.decimals()).to.eq(9)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY)
  })

  it('approve', async () => {
    await expect(token.approve(other.address, TEST_AMOUNT))
      .to.emit(token, 'Approval')
      .withArgs(wallet.address, other.address, TEST_AMOUNT)
    expect(await token.allowance(wallet.address, other.address)).to.eq(TEST_AMOUNT)
  })

  it('transfer', async () => {
    await expect(token.transfer(other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT))
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT)
  })

  it('transfer:fail', async () => {
    await expect(token.transfer(other.address, TOTAL_SUPPLY.add(1))).to.be.reverted // ds-math-sub-underflow
    await expect(token.connect(other).transfer(wallet.address, 1)).to.be.reverted // ds-math-sub-underflow
  })

  it('transferFrom', async () => {
    await token.approve(other.address, TEST_AMOUNT)
    await expect(token.connect(other).transferFrom(wallet.address, other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT)
    expect(await token.allowance(wallet.address, other.address)).to.eq(0)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT))
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT)
  })

  it('transferFrom:max', async () => {
    await token.approve(other.address, MaxUint256)
    await expect(token.connect(other).transferFrom(wallet.address, other.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, other.address, TEST_AMOUNT)
    expect(await token.allowance(wallet.address, other.address)).to.eq(MaxUint256)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT))
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT)
  })

  it('rebase', async () => {
    await addLiquidity(tokenAmount, tokenAnotherAmount)
    expect(await token.creator()).to.eq(wallet.address)
    const oracle = await deployContract(wallet, Oracle, [factory.address, token.address, token0.address === token.address ? token1.address : token0.address])
    await token.initialize(oracle.address)
    await token.setRebaseSetter(orchestrator.address)
    await token.setCreator('0x0000000000000000000000000000000000000000')
    expect(await token.creator()).to.eq('0x0000000000000000000000000000000000000000')
    await expect(token.initialize(oracle.address)).to.be.reverted
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 23)
    await expect(orchestrator.rebase(overrides)).to.be.reverted
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    await expect(oracle.update()).to.be.reverted
    expect(await token.epoch()).to.eq(0)
    await orchestrator.rebase(overrides)
    expect(await token.epoch()).to.eq(1)

    expect(await oracle.consult(token.address, 100)).to.eq('200000000')
  })

  it('rebase deflation', async () => {
    await addLiquidity(tokenAmount, tokenAnotherAmount)
    const oracle = await deployContract(wallet, Oracle, [factory.address, token.address, token0.address === token.address ? token1.address : token0.address])
    await token.initialize(oracle.address)
    await token.setRebaseSetter(orchestrator.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('419995000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenAmount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    expect(await token.epoch()).to.eq(0)
    await orchestrator.rebase(overrides)
    expect(await token.epoch()).to.eq(1)
    expect(await oracle.consult(token.address, 100)).to.eq('200000000')
    expect(await token.totalSupply()).to.eq('399000000000000')
    expect(await token.balanceOf(wallet.address)).to.eq('398995250000000')
    expect(await token.balanceOf(pair.address)).to.eq('4750000000')

    expect(await oracle.consult(token.address, 100)).to.eq('200000000')
  })

  it('rebase inflation', async () => {
    await addLiquidity(tokenLargeAmount, tokenAnotherSmallAmount)
    const oracle = await deployContract(wallet, Oracle, [factory.address, token.address, token0.address === token.address ? token1.address : token0.address])
    await token.initialize(oracle.address)
    await token.setRebaseSetter(orchestrator.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('419990000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenLargeAmount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    expect(await token.epoch()).to.eq(0)
    await orchestrator.rebase(overrides)
    expect(await token.epoch()).to.eq(1)
    expect(await oracle.consult(token.address, 100)).to.eq('50000000')
    expect(await token.totalSupply()).to.eq('441000000000000')
    expect(await token.balanceOf(wallet.address)).to.eq('440989500000000')
    expect(await token.balanceOf(pair.address)).to.eq('10500000000')

    expect(await oracle.consult(token.address, 100)).to.eq('50000000')
  })

  it('rebase stable', async () => {
    await addLiquidity(tokenClose0Amount, tokenClose1Amount)
    const oracle = await deployContract(wallet, Oracle, [factory.address, token.address, token0.address === token.address ? token1.address : token0.address])
    await token.initialize(oracle.address)
    await token.setRebaseSetter(orchestrator.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('419950000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenClose0Amount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    expect(await token.epoch()).to.eq(0)
    await orchestrator.rebase(overrides)
    expect(await token.epoch()).to.eq(1)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('419950000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenClose0Amount)

    expect(await oracle.consult(token.address, 100)).to.eq(104000000)
  })
})
