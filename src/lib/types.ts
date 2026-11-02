import type { Address } from 'viem'

export interface Deal {
  id: bigint
  brand: Address
  creator: Address
  arbiter: Address
  createdAt: bigint
  reviewPeriod: number
  feeBps: number
  maxRevisions: number
  status: number
  totalAmount: bigint
  escrowed: bigint
  title: string
  briefURI: string
}

export interface Milestone {
  label: string
  amount: bigint
  dueBy: bigint
  submittedAt: bigint
  disputedAt: bigint
  revisionsUsed: number
  status: number
  proofURI: string
}

/** State-only flags from milestoneActions(): they ignore who is calling. */
export interface Actions {
  canSubmit: boolean
  canApprove: boolean
  canRequestRevision: boolean
  canDispute: boolean
  canClaimTimeout: boolean
  canRefund: boolean
  canResolveStale: boolean
  reviewEndsAt: bigint
}

export interface DealView {
  deal: Deal
  milestones: Milestone[]
  actions: Actions[]
}

export type Role = 'brand' | 'creator' | 'arbiter' | 'viewer'
