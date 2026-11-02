import { useCallback, useEffect } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { useAccount } from 'wagmi'
import { ESCROW_ADDRESS, postPaidAbi } from '@/postpaid'
import { useDealView, useMyRole } from '@/hooks/useEscrow'
import { useSendTx } from '@/hooks/useSendTx'
import { useNow } from '@/hooks/useNow'
import { DISPUTE_TIMEOUT_SECONDS } from '@/postpaid'
import { DealHeader } from '@/components/DealHeader'
import { DealActions } from '@/components/DealActions'
import { MilestoneCard } from '@/components/MilestoneCard'
import { Timeline } from '@/components/Timeline'
import { EmptyState, ErrorState, Skeleton } from '@/components/ui'
import type { DealView } from '@/lib/types'

function parseId(raw: string | undefined): bigint | null {
  return raw && /^\d+$/.test(raw) && raw.length < 16 && BigInt(raw) > 0n ? BigInt(raw) : null
}

/** Next unix time at which a time-based flag from milestoneActions may flip. */
function nextBoundary(view: DealView, now: number): number | null {
  const times: number[] = []
  view.milestones.forEach((m, i) => {
    if (m.status === 0) times.push(Number(m.dueBy) + 1)
    if (m.status === 1) times.push(Number(view.actions[i]?.reviewEndsAt ?? 0n))
    if (m.status === 2) times.push(Number(m.disputedAt) + DISPUTE_TIMEOUT_SECONDS)
  })
  const future = times.filter((t) => t > now)
  return future.length ? Math.min(...future) : null
}

export function DealPage() {
  const params = useParams()
  const [search] = useSearchParams()
  const id = parseId(params.id)
  const { isConnected } = useAccount()
  const now = useNow()
  const queryClient = useQueryClient()
  const { data, isLoading, isError, refetch } = useDealView(id)
  const role = useMyRole(data?.deal)
  const { send, busy } = useSendTx()

  const run = useCallback(
    (label: string, functionName: string, args: readonly unknown[]) =>
      send(label, { address: ESCROW_ADDRESS, abi: postPaidAbi, functionName, args }),
    [send],
  )

  // Refetch the state-only action flags the moment a due date or review window passes.
  const boundary = data ? nextBoundary(data, now) : null
  useEffect(() => {
    if (boundary === null) return
    const wait = Math.max(0, boundary - Math.floor(Date.now() / 1000)) * 1000 + 3000
    const t = setTimeout(() => void queryClient.invalidateQueries({ queryKey: ['deal'] }), wait)
    return () => clearTimeout(t)
  }, [boundary, queryClient])

  if (id === null) return <EmptyState title="Deal not found" body="That deal link is not valid." action={<Link to="/" className="font-semibold underline">Back to the start</Link>} />
  if (isLoading) {
    return (
      <div className="space-y-4">
        <Skeleton className="h-64 w-full" />
        <Skeleton className="h-32 w-full" />
        <Skeleton className="h-32 w-full" />
      </div>
    )
  }
  if (isError || !data) {
    return (
      <div className="space-y-4">
        <ErrorState message="This deal could not be loaded. It may not exist on this network." onRetry={() => void refetch()} />
        <p className="text-center text-sm text-muted">Deal #{id.toString()}</p>
      </div>
    )
  }

  const { deal, milestones, actions } = data
  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <DealHeader deal={deal} role={role} justCreated={search.get('new') === '1'} />
      {!isConnected && <p className="rounded-xl bg-black/5 p-3 text-center text-sm text-muted">Connect your wallet to take actions on this deal.</p>}
      <DealActions deal={deal} milestones={milestones} role={role} busy={busy} run={run} />
      <section className="space-y-3" aria-labelledby="milestones">
        <h2 id="milestones" className="display text-2xl font-bold">Milestones</h2>
        {milestones.map((m, i) => (
          <MilestoneCard key={i} deal={deal} m={m} index={i} a={actions[i]} role={role} now={now} busy={busy} run={run} />
        ))}
      </section>
      <Timeline dealId={deal.id} />
    </div>
  )
}
