import { useQuery } from '@tanstack/react-query'
import { erc20Abi, type Address } from 'viem'
import { useAccount, usePublicClient } from 'wagmi'
import { ACTIVE_CHAIN, ESCROW_ADDRESS, USDC_ADDRESS, postPaidAbi } from '@/postpaid'
import type { Actions, Deal, DealView, Milestone, Role } from '@/lib/types'

export function useClient() {
  const client = usePublicClient({ chainId: ACTIVE_CHAIN.id })
  if (!client) throw new Error('No public client for the configured chain')
  return client
}

export function useProtocol() {
  const client = useClient()
  return useQuery({
    queryKey: ['protocol'],
    refetchInterval: 20_000,
    queryFn: async () => {
      const read = { address: ESCROW_ADDRESS, abi: postPaidAbi } as const
      const [nextDealId, totalEscrowed, protocolFeeBps, paused] = await Promise.all([
        client.readContract({ ...read, functionName: 'nextDealId' }),
        client.readContract({ ...read, functionName: 'totalEscrowed' }),
        client.readContract({ ...read, functionName: 'protocolFeeBps' }),
        client.readContract({ ...read, functionName: 'paused' }),
      ])
      return { nextDealId, totalEscrowed, protocolFeeBps, paused, totalDeals: nextDealId - 1n }
    },
  })
}

export function useWithdrawable(account?: Address) {
  const client = useClient()
  return useQuery({
    queryKey: ['withdrawable', account],
    enabled: !!account,
    refetchInterval: 20_000,
    queryFn: () =>
      client.readContract({ address: ESCROW_ADDRESS, abi: postPaidAbi, functionName: 'withdrawable', args: [account!] }),
  })
}

export function useUsdc(account?: Address) {
  const client = useClient()
  return useQuery({
    queryKey: ['usdc', account],
    enabled: !!account,
    refetchInterval: 20_000,
    queryFn: async () => {
      const [balance, allowance] = await Promise.all([
        client.readContract({ address: USDC_ADDRESS, abi: erc20Abi, functionName: 'balanceOf', args: [account!] }),
        client.readContract({
          address: USDC_ADDRESS,
          abi: erc20Abi,
          functionName: 'allowance',
          args: [account!, ESCROW_ADDRESS],
        }),
      ])
      return { balance, allowance }
    },
  })
}

function toDeal(id: bigint, d: {
  brand: Address; creator: Address; arbiter: Address; createdAt: bigint; reviewPeriod: number; feeBps: number
  maxRevisions: number; status: number; totalAmount: bigint; escrowed: bigint; title: string; briefURI: string
}): Deal {
  return { id, ...d }
}

export function toMilestone(m: Milestone): Milestone {
  return { ...m }
}

export async function fetchDealView(client: ReturnType<typeof useClient>, id: bigint, withActions = true): Promise<DealView> {
  const read = { address: ESCROW_ADDRESS, abi: postPaidAbi } as const
  const [rawDeal, rawMilestones] = await Promise.all([
    client.readContract({ ...read, functionName: 'getDeal', args: [id] }),
    client.readContract({ ...read, functionName: 'getMilestones', args: [id] }),
  ])
  const milestones: Milestone[] = rawMilestones.map((m) => toMilestone({ ...m }))
  const actions: Actions[] = withActions
    ? await Promise.all(
        milestones.map(async (_, i) => {
          const r = await client.readContract({ ...read, functionName: 'milestoneActions', args: [id, BigInt(i)] })
          return {
            canSubmit: r[0],
            canApprove: r[1],
            canRequestRevision: r[2],
            canDispute: r[3],
            canClaimTimeout: r[4],
            canRefund: r[5],
            canResolveStale: r[6],
            reviewEndsAt: r[7],
          }
        }),
      )
    : []
  return { deal: toDeal(id, rawDeal), milestones, actions }
}

export function useDealView(id: bigint | null) {
  const client = useClient()
  return useQuery({
    queryKey: ['deal', id?.toString()],
    enabled: id !== null,
    refetchInterval: 15_000,
    retry: 1,
    queryFn: () => fetchDealView(client, id!),
  })
}

export function roleOf(deal: Deal | undefined, account?: Address): Role {
  if (!deal || !account) return 'viewer'
  const a = account.toLowerCase()
  if (deal.brand.toLowerCase() === a) return 'brand'
  if (deal.creator.toLowerCase() === a) return 'creator'
  if (deal.arbiter.toLowerCase() === a) return 'arbiter'
  return 'viewer'
}

export function useMyRole(deal: Deal | undefined): Role {
  const { address } = useAccount()
  return roleOf(deal, address)
}

const ROLE_FN = { brand: 'dealsOfBrand', creator: 'dealsOfCreator', arbiter: 'dealsOfArbiter' } as const
export type DashRole = keyof typeof ROLE_FN
const DASHBOARD_LIMIT = 40

/** Latest deals for an account in one role, with their milestones (no action flags needed for summaries). */
export function useRoleDeals(role: DashRole, account?: Address) {
  const client = useClient()
  return useQuery({
    queryKey: ['roleDeals', role, account],
    enabled: !!account,
    refetchInterval: 20_000,
    queryFn: async () => {
      const ids = await client.readContract({
        address: ESCROW_ADDRESS,
        abi: postPaidAbi,
        functionName: ROLE_FN[role],
        args: [account!],
      })
      const latest = [...ids].reverse().slice(0, DASHBOARD_LIMIT)
      const views = await Promise.all(latest.map((id) => fetchDealView(client, id, false)))
      return { total: ids.length, views }
    },
  })
}
