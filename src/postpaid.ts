/**
 * Single source of truth for PostPaid's network configuration.
 * Switching to Arc mainnet only needs VITE_CHAIN=arc plus the mainnet escrow address and deploy block.
 */
import { arc, arcTestnet } from 'viem/chains'
import { isAddress, type Address, type Hash } from 'viem'

export { postPaidAbi } from './abi/postPaidEscrow'

const TESTNET_ESCROW: Address = '0x4e51c6f82fb8dadd51d650607f05cbb937d3cfe5'
const TESTNET_DEPLOY_BLOCK = 70378581n

export const CHAIN_KEY: 'arc' | 'arcTestnet' = import.meta.env.VITE_CHAIN === 'arc' ? 'arc' : 'arcTestnet'
export const ACTIVE_CHAIN = CHAIN_KEY === 'arc' ? arc : arcTestnet
export const OTHER_CHAIN = CHAIN_KEY === 'arc' ? arcTestnet : arc
export const IS_TESTNET = CHAIN_KEY === 'arcTestnet'

const envAddress = import.meta.env.VITE_ESCROW_ADDRESS
export const ESCROW_ADDRESS: Address = envAddress && isAddress(envAddress) ? envAddress : TESTNET_ESCROW

const envBlock = import.meta.env.VITE_DEPLOY_BLOCK
export const DEPLOY_BLOCK: bigint = envBlock && /^\d+$/.test(envBlock) ? BigInt(envBlock) : TESTNET_DEPLOY_BLOCK

export const USDC_ADDRESS: Address = '0x3600000000000000000000000000000000000000'
export const USDC_DECIMALS = 6

export const EXPLORER_BASE = IS_TESTNET ? 'https://explorer.testnet.arc.io' : 'https://explorer.arc.io'
export const txUrl = (hash: Hash) => `${EXPLORER_BASE}/tx/${hash}`
export const addressUrl = (addr: string) => `${EXPLORER_BASE}/address/${addr}`

/** Arc silently drops transactions priced below 20 gwei, so every write is priced at or above these floors. */
export const MIN_MAX_FEE_PER_GAS = 25_000_000_000n
export const MIN_PRIORITY_FEE_PER_GAS = 1_000_000_000n

export const MIN_MILESTONE_RAW = 10_000n
export const MAX_MILESTONES = 10
export const DISPUTE_TIMEOUT_SECONDS = 14 * 24 * 60 * 60

/** Enum orders mirror the Solidity contract. */
export const DealStatus = { Open: 0, Active: 1, Cancelled: 2, Closed: 3 } as const
export const MilestoneStatus = { Pending: 0, Submitted: 1, Disputed: 2, Released: 3, Refunded: 4, Split: 5 } as const

export const DEAL_STATUS_LABEL = ['Open', 'Active', 'Cancelled', 'Closed'] as const
export const MILESTONE_STATUS_LABEL = ['Pending', 'Submitted', 'Disputed', 'Released', 'Refunded', 'Split'] as const
