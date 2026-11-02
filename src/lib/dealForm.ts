import { isAddress, type Address } from 'viem'
import { MAX_MILESTONES, MIN_MILESTONE_RAW } from '@/postpaid'
import { byteLength, parseUsdcInput } from '@/lib/format'

export interface MilestoneDraft {
  id: number
  label: string
  amount: string
  due: string // datetime-local value
}

export interface DealDraft {
  creator: string
  arbiter: string
  title: string
  briefURI: string
  milestones: MilestoneDraft[]
  reviewPeriod: number
  maxRevisions: number
}

export const REVIEW_PRESETS = [
  { label: '10 minutes (demo)', seconds: 600 },
  { label: '24 hours', seconds: 86_400 },
  { label: '72 hours', seconds: 259_200 },
  { label: '7 days', seconds: 604_800 },
] as const

export const DEFAULT_REVIEW = 259_200
/** Due dates must be this many seconds ahead so they are still in the future when the transaction lands. */
export const DUE_MARGIN = 60

export interface ValidDeal {
  creator: Address
  arbiter: Address
  labels: string[]
  amounts: bigint[]
  dueBys: bigint[]
  total: bigint
}

export interface DraftErrors {
  creator?: string
  arbiter?: string
  title?: string
  briefURI?: string
  milestones: Array<{ label?: string; amount?: string; due?: string }>
  general?: string
}

const ZERO = '0x0000000000000000000000000000000000000000'

export function validateDraft(d: DealDraft, brand: string | undefined, nowSec: number): { errors: DraftErrors; valid: ValidDeal | null } {
  const errors: DraftErrors = { milestones: d.milestones.map(() => ({})) }
  let ok = true
  const fail = () => {
    ok = false
  }

  const creator = d.creator.trim()
  if (!creator) {
    errors.creator = 'Enter the creator wallet address'
    fail()
  } else if (!isAddress(creator) || creator.toLowerCase() === ZERO) {
    errors.creator = 'Not a valid wallet address'
    fail()
  } else if (brand && creator.toLowerCase() === brand.toLowerCase()) {
    errors.creator = "The creator can't be your own wallet"
    fail()
  }

  const arbiter = d.arbiter.trim()
  if (arbiter) {
    if (!isAddress(arbiter) || arbiter.toLowerCase() === ZERO) {
      errors.arbiter = 'Not a valid wallet address'
      fail()
    } else if (brand && arbiter.toLowerCase() === brand.toLowerCase()) {
      errors.arbiter = "The arbiter can't be you"
      fail()
    } else if (creator && arbiter.toLowerCase() === creator.toLowerCase()) {
      errors.arbiter = "The arbiter can't be the creator"
      fail()
    }
  }

  const titleBytes = byteLength(d.title.trim())
  if (titleBytes < 1 || titleBytes > 80) {
    errors.title = titleBytes === 0 ? 'Add a title' : 'Title must be 80 bytes or fewer'
    fail()
  }
  if (byteLength(d.briefURI.trim()) > 256) {
    errors.briefURI = 'Brief link must be 256 bytes or fewer'
    fail()
  }

  if (d.milestones.length < 1 || d.milestones.length > MAX_MILESTONES) {
    errors.general = `Add between 1 and ${MAX_MILESTONES} milestones`
    fail()
  }

  const labels: string[] = []
  const amounts: bigint[] = []
  const dueBys: bigint[] = []
  d.milestones.forEach((m, i) => {
    const label = m.label.trim()
    const lb = byteLength(label)
    if (lb < 1 || lb > 64) {
      errors.milestones[i].label = lb === 0 ? 'Add a label' : 'Label must be 64 bytes or fewer'
      fail()
    }
    const raw = parseUsdcInput(m.amount)
    if (raw === null || raw < MIN_MILESTONE_RAW) {
      errors.milestones[i].amount = 'Minimum 0.01 USDC (up to 6 decimals)'
      fail()
    }
    const dueMs = m.due ? new Date(m.due).getTime() : NaN
    const dueSec = Math.floor(dueMs / 1000)
    if (!Number.isFinite(dueSec) || dueSec <= nowSec + DUE_MARGIN) {
      errors.milestones[i].due = 'Pick a due date in the future'
      fail()
    }
    labels.push(label)
    amounts.push(raw ?? 0n)
    dueBys.push(BigInt(Number.isFinite(dueSec) ? dueSec : 0))
  })

  if (!ok) return { errors, valid: null }
  return {
    errors,
    valid: {
      creator: creator as Address,
      arbiter: (arbiter || ZERO) as Address,
      labels,
      amounts,
      dueBys,
      total: amounts.reduce((a, b) => a + b, 0n),
    },
  }
}

/** Mirror of the contract's release math: fee rounds down per milestone. */
export function creatorReceives(amounts: bigint[], feeBps: number): { fee: bigint; net: bigint } {
  let fee = 0n
  let net = 0n
  for (const a of amounts) {
    const f = (a * BigInt(feeBps)) / 10_000n
    fee += f
    net += a - f
  }
  return { fee, net }
}
