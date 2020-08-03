import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { MaxUint256 } from 'ethers/constants'
import { BigNumber } from 'ethers/utils'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import { expandTo9Decimals, mineBlock } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

chai.use(solidity)

const overrides = {
  gasLimit: 9999999
}

const TOTAL_SUPPLY = expandTo9Decimals(1000000)
const TEST_AMOUNT = expandTo9Decimals(10)
const tokenAmount = expandTo9Decimals(5)
const tokenAnotherAmount = expandTo9Decimals(10)
const tokenClose0Amount = expandTo9Decimals(50)
const tokenClose1Amount = expandTo9Decimals(52)

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
  })

  it('name, symbol, decimals, totalSupply, balanceOf', async () => {
    const name = await token.name()
    expect(name).to.eq('MOST')
    expect(await token.symbol()).to.eq('MOST')
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
    await token.initialize(factory.address, token0.address === token.address ? token1.address : token0.address)
    expect(await token.creator()).to.eq('0x0000000000000000000000000000000000000000')
    await expect(token.initialize(factory.address, token0.address === token.address ? token1.address : token0.address)).to.be.reverted
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 23)
    await expect(token.rebase(overrides)).to.be.reverted
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    await token.rebase(overrides)

    expect(await token.consult(token.address, 100)).to.eq(200)
  })

  it('rebase deflation', async () => {
    await addLiquidity(tokenAmount, tokenAnotherAmount)
    await token.initialize(factory.address, token0.address === token.address ? token1.address : token0.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('999995000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenAmount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    await token.rebase(overrides)
    expect(await token.totalSupply()).to.eq('950000000000000')
    expect(await token.balanceOf(wallet.address)).to.eq('949995250000000')
    expect(await token.balanceOf(pair.address)).to.eq('4750000000')

    expect(await token.consult(token.address, 100)).to.eq(200)
  })

  it('rebase inflation', async () => {
    await addLiquidity(tokenAnotherAmount, tokenAmount)
    await token.initialize(factory.address, token0.address === token.address ? token1.address : token0.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('999990000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenAnotherAmount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    await token.rebase(overrides)
    expect(await token.totalSupply()).to.eq('1050000000000000')
    expect(await token.balanceOf(wallet.address)).to.eq('1049989500000000')
    expect(await token.balanceOf(pair.address)).to.eq('10500000000')

    expect(await token.consult(token.address, 100)).to.eq(50)
  })

  it('rebase stable', async () => {
    await addLiquidity(tokenClose1Amount, tokenClose0Amount)
    await token.initialize(factory.address, token0.address === token.address ? token1.address : token0.address)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('999948000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenClose1Amount)
    const blockTimestamp = (await pair.getReserves())[2]
    await mineBlock(provider, blockTimestamp + 60 * 60 * 24)
    await token.rebase(overrides)
    expect(await token.totalSupply()).to.eq(TOTAL_SUPPLY)
    expect(await token.balanceOf(wallet.address)).to.eq('999948000000000')
    expect(await token.balanceOf(pair.address)).to.eq(tokenClose1Amount)

    expect(await token.consult(token.address, 100)).to.eq(96)
  })
})
