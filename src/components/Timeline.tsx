import { ExternalLink } from 'lucide-react'
import { txUrl } from '@/postpaid'
import { useDealTimeline, type TimelineEntry } from '@/hooks/useTimeline'
import { fmtDateTime, fmtUsdc, shortAddress } from '@/lib/format'
import { ErrorState, Skeleton } from './ui'

const bigint = (v: unknown) => (typeof v === 'bigint' ? v : 0n)
const str = (v: unknown) => (typeof v === 'string' ? v : '')
const num = (v: unknown) => (typeof v === 'bigint' ? Number(v) : typeof v === 'number' ? v : 0)

function describe(e: TimelineEntry): string {
  const a = e.args
  const ms = a.index !== undefined ? `Milestone ${num(a.index) + 1}` : ''
  switch (e.name) {
    case 'DealCreated':
      return `Deal created and ${fmtUsdc(bigint(a.totalAmount))} USDC locked`
    case 'DealAccepted':
      return `Creator ${shortAddress(str(a.creator))} accepted the deal`
    case 'DealCancelled':
      return `Brand cancelled the deal. ${fmtUsdc(bigint(a.refunded))} USDC refunded`
    case 'DealClosed':
      return 'Deal closed. Every milestone is settled'
    case 'CreatorExited':
      return `Creator exited. ${fmtUsdc(bigint(a.refunded))} USDC refunded to the brand`
    case 'MilestoneSubmitted':
      return `${ms}: proof submitted`
    case 'RevisionRequested':
      return `${ms}: revision requested${str(a.note) ? ` ("${str(a.note)}")` : ''}`
    case 'DisputeOpened':
      return `${ms}: dispute opened${str(a.reason) ? ` ("${str(a.reason)}")` : ''}`
    case 'DisputeResolved':
      return `${ms}: dispute resolved. Creator ${fmtUsdc(bigint(a.creatorNet))}, brand ${fmtUsdc(bigint(a.brandPart))} USDC`
    case 'MilestoneReleased':
      return `${ms}: ${num(a.reason) === 1 ? 'auto-released after the review window' : 'approved'}. Creator received ${fmtUsdc(bigint(a.creatorNet))} USDC`
    case 'MilestoneRefunded':
      return `${ms}: ${fmtUsdc(bigint(a.amount))} USDC refunded to the brand`
    default:
      return e.name
  }
}

export function Timeline({ dealId }: { dealId: bigint }) {
  const { data, isLoading, isError, refetch } = useDealTimeline(dealId)
  return (
    <section className="space-y-3" aria-labelledby="timeline">
      <h2 id="timeline" className="display text-2xl font-bold">
        Timeline
      </h2>
      {isLoading && (
        <div className="card space-y-3 p-5">
          <Skeleton className="h-5 w-3/4" />
          <Skeleton className="h-5 w-2/3" />
        </div>
      )}
      {isError && <ErrorState message="Could not load the timeline." onRetry={() => void refetch()} />}
      {data && data.length === 0 && <p className="text-sm text-muted">No events yet.</p>}
      {data && data.length > 0 && (
        <ol className="card divide-y divide-line">
          {data.map((e) => (
            <li key={e.key} className="flex items-start justify-between gap-3 p-4">
              <div className="min-w-0">
                <p className="text-sm font-semibold text-ink-2">{describe(e)}</p>
                <p className="mt-0.5 text-xs text-subtle tabular-nums">
                  {e.timestamp ? fmtDateTime(e.timestamp) : `Block ${e.blockNumber.toString()}`}
                </p>
              </div>
              <a
                href={txUrl(e.txHash)}
                target="_blank"
                rel="noopener noreferrer"
                aria-label="View transaction on the explorer"
                className="grid h-10 w-10 shrink-0 place-items-center rounded-lg text-subtle hover:bg-black/5"
              >
                <ExternalLink className="h-4 w-4" />
              </a>
            </li>
          ))}
        </ol>
      )}
    </section>
  )
}
