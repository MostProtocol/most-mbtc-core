import { Wallet, Contract } from 'ethers'
import { Web3Provider } from 'ethers/providers'
import { deployContract } from 'ethereum-waffle'

import { expandTo18Decimals } from './utilities'

import UniswapV2Factory from '@uniswap/v2-core/build/UniswapV2Factory.json'
import IUniswapV2Pair from '@uniswap/v2-core/build/IUniswapV2Pair.json'

import ERC20 from '../../build/ERC20.json'
import MostERC20 from '../../build/MostERC20.json'
import Orchestrator from '../../build/Orchestrator.json'
import SyncHelper from '../../build/SyncHelper.json'
import MultipleTokenTimeLock from '../../build/MultipleTokenTimeLock.json'

interface V2Fixture {
  token: Contract
  token0: Contract
  token1: Contract
  factoryV2: Contract
  pair: Contract
  orchestrator: Contract
  syncHelper: Contract
  timelock: Contract
}

export async function v2Fixture(provider: Web3Provider, [wallet]: Wallet[]): Promise<V2Fixture> {
  // deploy tokens
  const tokenA = await deployContract(wallet, MostERC20)
  const tokenB = await deployContract(wallet, ERC20, [expandTo18Decimals(100000000)])

  // deploy V2
  const factoryV2 = await deployContract(wallet, UniswapV2Factory, [wallet.address])

  // initialize V2
  await factoryV2.createPair(tokenA.address, tokenB.address)
  const pairAddress = await factoryV2.getPair(tokenA.address, tokenB.address)
  const pair = new Contract(pairAddress, JSON.stringify(IUniswapV2Pair.abi), provider).connect(wallet)

  const orchestrator = await deployContract(wallet, Orchestrator, [tokenA.address])
  await orchestrator.addTransaction(pair.address, '0xfff6cae9') // sync()

  const syncHelper = await deployContract(wallet, SyncHelper)
  const timelock = await deployContract(wallet, MultipleTokenTimeLock, [wallet.address, Math.floor(Date.now() / 1000) + 24 * 3600])

  const token0Address = await pair.token0()
  const token = tokenA
  const token0 = tokenA.address === token0Address ? tokenA : tokenB
  const token1 = tokenA.address === token0Address ? tokenB : tokenA

  return {
    token,
    token0,
    token1,
    factoryV2,
    pair,
    orchestrator,
    syncHelper,
    timelock
  }
}
