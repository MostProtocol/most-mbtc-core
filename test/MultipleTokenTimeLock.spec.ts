import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import { expandTo9Decimals, mineBlock } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

chai.use(solidity)

const TEST_AMOUNT = expandTo9Decimals(10)

describe('MultipleTokenTimeLock.spec', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet, other] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token0: Contract
  let token1: Contract
  let timelock: Contract

  beforeEach(async () => {
    const fixture = await loadFixture(v2Fixture)
    token0 = fixture.token0
    token1 = fixture.token1
    timelock = fixture.timelock
  })

  it('release', async () => {
    await token0.transfer(timelock.address, TEST_AMOUNT)
    await token1.transfer(timelock.address, TEST_AMOUNT)
    expect(await token0.balanceOf(timelock.address)).to.eq(TEST_AMOUNT)
    expect(await token1.balanceOf(timelock.address)).to.eq(TEST_AMOUNT)

    await expect(timelock.release(token0.address)).to.be.reverted
    await expect(timelock.release(token1.address)).to.be.reverted
  
    await mineBlock(provider, Math.floor(Date.now() / 1000) + 60 * 60 * 24)

    await expect(timelock.connect(other).release(token0.address))
      .to.emit(token0, 'Transfer')
      .withArgs(timelock.address, wallet.address, TEST_AMOUNT)
    await expect(timelock.connect(other).release(token1.address))
      .to.emit(token1, 'Transfer')
      .withArgs(timelock.address, wallet.address, TEST_AMOUNT)
})

  it('newReleaseTime', async () => {
    await token0.transfer(timelock.address, TEST_AMOUNT)
    expect(await token0.balanceOf(timelock.address)).to.eq(TEST_AMOUNT)

    await expect(timelock.release(token0.address)).to.be.reverted
    await mineBlock(provider, Math.floor(Date.now() / 1000) + 60 * 60 * 24)

    await expect(timelock.connect(other).newReleaseTime(60 * 60 * 24)).to.be.reverted // only owner
    await timelock.newReleaseTime(60 * 60 * 24)

    await expect(timelock.connect(other).release(token0.address)).to.be.reverted // no enough time

    await mineBlock(provider, Math.floor(Date.now() / 1000) + 60 * 60 * 48)
    await expect(timelock.connect(other).release(token0.address))
      .to.emit(token0, 'Transfer')
      .withArgs(timelock.address, wallet.address, TEST_AMOUNT)
  })
})
