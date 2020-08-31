import chai, { expect } from 'chai'
import { Contract } from 'ethers'
import { solidity, MockProvider, createFixtureLoader } from 'ethereum-waffle'

import { expandTo9Decimals } from './shared/utilities'
import { v2Fixture } from './shared/fixtures'

chai.use(solidity)

const TOTAL_SUPPLY = expandTo9Decimals(420000)
const TEST_AMOUNT = expandTo9Decimals(10)

describe('SyncHelper', () => {
  const provider = new MockProvider({
    hardfork: 'istanbul',
    mnemonic: 'horn horn horn horn horn horn horn horn horn horn horn horn',
    gasLimit: 9999999
  })
  const [wallet, other] = provider.getWallets()
  const loadFixture = createFixtureLoader(provider, [wallet])

  let token: Contract
  let pair: Contract
  let syncHelper: Contract

  beforeEach(async () => {
    const fixture = await loadFixture(v2Fixture)
    token = fixture.token
    pair = fixture.pair
    syncHelper = fixture.syncHelper
  })

  it('transferAndSyc:noSync', async () => {
    await expect(token.transfer(syncHelper.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, syncHelper.address, TEST_AMOUNT)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT))
    expect(await token.balanceOf(syncHelper.address)).to.eq(TEST_AMOUNT)

    await expect(syncHelper.connect(other).transferAndSync(token.address, other.address, TEST_AMOUNT, false)).to.be.reverted // only owner
    await expect(syncHelper.connect(other).transferAndSync(token.address, other.address, TEST_AMOUNT, true)).to.be.reverted // only owner
    await expect(syncHelper.connect(wallet).transferAndSync(token.address, other.address, TEST_AMOUNT, true)).to.be.reverted // no sync available
    await expect(syncHelper.connect(wallet).transferAndSync(token.address, other.address, TEST_AMOUNT, false))
      .to.emit(token, 'Transfer')
      .withArgs(syncHelper.address, other.address, TEST_AMOUNT)

    expect(await token.balanceOf(syncHelper.address)).to.eq(0)
    expect(await token.balanceOf(other.address)).to.eq(TEST_AMOUNT)
  })

  it('transferAndSyc:shouldSync', async () => {
    await expect(token.transfer(syncHelper.address, TEST_AMOUNT))
      .to.emit(token, 'Transfer')
      .withArgs(wallet.address, syncHelper.address, TEST_AMOUNT)
    expect(await token.balanceOf(wallet.address)).to.eq(TOTAL_SUPPLY.sub(TEST_AMOUNT))
    expect(await token.balanceOf(syncHelper.address)).to.eq(TEST_AMOUNT)

    await expect(syncHelper.connect(other).transferAndSync(token.address, pair.address, TEST_AMOUNT, false)).to.be.reverted // only owner
    await expect(syncHelper.connect(other).transferAndSync(token.address, pair.address, TEST_AMOUNT, true)).to.be.reverted // only owner
    await expect(syncHelper.connect(wallet).transferAndSync(token.address, pair.address, TEST_AMOUNT, true)) // sync available
      .to.emit(token, 'Transfer')
      .withArgs(syncHelper.address, pair.address, TEST_AMOUNT)

    expect(await token.balanceOf(syncHelper.address)).to.eq(0)
    expect(await token.balanceOf(pair.address)).to.eq(TEST_AMOUNT)
  })
})
