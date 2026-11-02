import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { ConnectKitButton } from 'connectkit'
import { useAccount } from 'wagmi'
import { ChevronRight } from 'lucide-react'
import clsx from 'clsx'
import { ESCROW_ADDRESS, MilestoneStatus, postPaidAbi } from '@/postpaid'
import { useRoleDeals, useWithdrawable, type DashRole } from '@/hooks/useEscrow'
import { useSendTx } from '@/hooks/useSendTx'
import { useNow } from '@/hooks/useNow'
import { fmtUsdc } from '@/lib/format'
import type { DealView } from '@/lib/types'
import { Button, DealStatusPill, EmptyState, ErrorState, Skeleton } from '@/components/ui'

const TABS: Array<{ key: DashRole; label: string }> = [
  { key: 'brand', label: 'As brand' },
  { key: 'creator', label: 'As creator' },
  { key: 'arbiter', label: 'As arbiter' },
]
const FILTERS = ['All', 'Active', 'Open', 'Closed', 'Cancelled'] as const
type Filter = (typeof FILTERS)[number]
const FILTER_STATUS: Record<Exclude<Filter, 'All'>, number> = { Open: 0, Active: 1, Cancelled: 2, Closed: 3 }

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

function nextAction(v: DealView, role: DashRole, now: number): string {
  const count = (status: number) => v.milestones.filter((m) => m.status === status).length
  const { deal } = v
  if (role === 'brand') {
    if (deal.status === 0) return 'Waiting for the creator to accept'
    const submitted = count(MilestoneStatus.Submitted)
    if (submitted) return `${plural(submitted, 'milestone awaits', 'milestones await')} your review`
    const overdue = v.milestones.filter((m) => m.status === 0 && Number(m.dueBy) < now).length
    if (deal.status === 1 && overdue) return `${plural(overdue, 'overdue milestone', 'overdue milestones')} can be refunded`
  }
  if (role === 'creator') {
    if (deal.status === 0) return 'Review and accept this deal'
    const todo = v.milestones.filter((m) => m.status === 0 && Number(m.dueBy) >= now).length
    if (deal.status === 1 && todo) return `${plural(todo, 'milestone', 'milestones')} to deliver`
    const waiting = count(MilestoneStatus.Submitted)
    if (waiting) return `${plural(waiting, 'milestone', 'milestones')} awaiting the brand`
  }
  if (role === 'arbiter') {
    const disputed = count(MilestoneStatus.Disputed)
    if (disputed) return `${plural(disputed, 'dispute', 'disputes')} to resolve`
  }
  return deal.status === 3 ? 'All milestones settled' : 'Nothing needs you right now'
}

function WithdrawCard({ account }: { account: `0x${string}` }) {
  const { data, isLoading } = useWithdrawable(account)
  const { send, busy } = useSendTx()
  const amount = data ?? 0n
  return (
    <section className="card flex flex-col gap-4 p-5 sm:flex-row sm:items-center sm:justify-between sm:p-6">
      <div>
        <p className="eyebrow">Available to withdraw</p>
        {isLoading ? (
          <Skeleton className="mt-2 h-10 w-40" />
        ) : (
          <p className="display text-4xl font-bold tabular-nums">{fmtUsdc(amount)} <span className="text-lg text-muted">USDC</span></p>
        )}
        <p className="mt-1 text-xs text-subtle">Payouts and refunds from all your deals collect here.</p>
      </div>
      <Button
        className="sm:min-w-[160px]"
        disabled={amount === 0n}
        loading={busy}
        onClick={() => void send('Withdraw', { address: ESCROW_ADDRESS, abi: postPaidAbi, functionName: 'withdraw' })}
      >
        Withdraw
      </Button>
    </section>
  )
}

export function Dashboard() {
  const { address, isConnected } = useAccount()
  const now = useNow()
  const [tab, setTab] = useState<DashRole>('creator')
  const [filter, setFilter] = useState<Filter>('All')
  const { data, isLoading, isError, refetch } = useRoleDeals(tab, address)

  const shown = useMemo(() => {
    const views = data?.views ?? []
    return filter === 'All' ? views : views.filter((v) => v.deal.status === FILTER_STATUS[filter])
  }, [data, filter])

  if (!isConnected || !address) {
    return (
      <div className="card mx-auto max-w-md space-y-4 p-8 text-center">
        <h1 className="display text-2xl font-bold">Your dashboard</h1>
        <p className="text-pretty text-sm text-muted">Connect your wallet to see your deals and withdraw your USDC.</p>
        <ConnectKitButton />
      </div>
    )
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="display text-3xl font-bold">Dashboard</h1>
      <WithdrawCard account={address} />

      <div role="tablist" aria-label="Your role" className="flex gap-1 rounded-2xl bg-black/5 p-1">
        {TABS.map((t) => (
          <button
            key={t.key}
            role="tab"
            aria-selected={tab === t.key}
            onClick={() => setTab(t.key)}
            className={clsx('min-h-[44px] flex-1 rounded-xl px-3 text-sm font-semibold transition-colors', tab === t.key ? 'bg-white text-ink shadow-sm' : 'text-muted hover:text-ink')}
          >
            {t.label}
          </button>
        ))}
      </div>

      <div className="flex flex-wrap gap-2" role="group" aria-label="Filter by status">
        {FILTERS.map((f) => (
          <button
            key={f}
            aria-pressed={filter === f}
            onClick={() => setFilter(f)}
            className={clsx('min-h-[40px] rounded-full border px-4 text-sm font-semibold', filter === f ? 'border-accent bg-accent text-white' : 'border-line bg-white/70 text-ink-2 hover:bg-white')}
          >
            {f}
          </button>
        ))}
      </div>

      {isLoading && (
        <div className="space-y-3">
          <Skeleton className="h-24 w-full" />
          <Skeleton className="h-24 w-full" />
        </div>
      )}
      {isError && <ErrorState message="Could not load your deals." onRetry={() => void refetch()} />}
      {data && shown.length === 0 && (
        <EmptyState
          title={data.total === 0 ? `No deals ${tab === 'brand' ? 'created' : tab === 'creator' ? 'offered to you' : 'assigned to you'} yet` : 'No deals match this filter'}
          body={data.total === 0 ? (tab === 'brand' ? 'Lock USDC for a creator to get started.' : 'When a brand creates a deal for your wallet, it shows up here.') : 'Try a different status filter.'}
          action={tab === 'brand' && data.total === 0 ? <Link to="/new" className="font-semibold underline">Create a deal</Link> : undefined}
        />
      )}
      <ul className="space-y-3">
        {shown.map((v) => (
          <li key={v.deal.id.toString()}>
            <Link to={`/deal/${v.deal.id.toString()}`} className="card flex items-center justify-between gap-3 p-4 hover:bg-white sm:p-5">
              <div className="min-w-0 space-y-1.5">
                <div className="flex items-center gap-2">
                  <span className="eyebrow">#{v.deal.id.toString()}</span>
                  <DealStatusPill status={v.deal.status} />
                </div>
                <p className="display truncate text-lg font-semibold">{v.deal.title}</p>
                <p className="text-sm text-muted">{nextAction(v, tab, now)}</p>
              </div>
              <div className="flex shrink-0 items-center gap-2">
                <p className="display text-lg font-bold tabular-nums">{fmtUsdc(v.deal.totalAmount)}</p>
                <ChevronRight className="h-5 w-5 text-subtle" aria-hidden />
              </div>
            </Link>
          </li>
        ))}
      </ul>
      {data && data.total > data.views.length && <p className="text-center text-xs text-subtle">Showing your latest {data.views.length} of {data.total} deals.</p>}
    </div>
  )
}
