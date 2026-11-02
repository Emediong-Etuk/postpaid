import { Link } from 'react-router-dom'
import { FileCheck2, Lock, Wallet } from 'lucide-react'
import { TokenUSDC } from '@web3icons/react'
import { useProtocol } from '@/hooks/useEscrow'
import { fmtUsdc } from '@/lib/format'
import { Skeleton } from '@/components/ui'

const STEPS = [
  {
    icon: Lock,
    title: 'Lock',
    body: 'The brand locks the full campaign budget in USDC up front, split into milestones.',
  },
  {
    icon: FileCheck2,
    title: 'Deliver',
    body: 'The creator posts and submits proof for each milestone before its due date.',
  },
  {
    icon: Wallet,
    title: 'Get paid',
    body: 'The brand approves, or silence counts as approval once the review window ends. Funds are paid out instantly.',
  },
]

function Stat({ label, value, loading }: { label: string; value: string; loading: boolean }) {
  return (
    <div className="rounded-2xl bg-white/70 p-4">
      <p className="eyebrow">{label}</p>
      {loading ? <Skeleton className="mt-2 h-8 w-24" /> : <p className="display mt-1 text-3xl font-bold tabular-nums">{value}</p>}
    </div>
  )
}

export function Landing() {
  const { data, isLoading, isError } = useProtocol()
  return (
    <div className="space-y-10">
      <section className="card p-6 sm:p-10">
        <p className="eyebrow">USDC milestone escrow for creator campaigns</p>
        <h1 className="display mt-3 max-w-2xl text-balance text-4xl font-bold leading-tight sm:text-6xl">
          Get paid for every post. Guaranteed.
        </h1>
        <p className="mt-4 max-w-xl text-pretty text-lg text-muted">
          Brands lock USDC before work starts. Creators are paid per milestone. If the brand goes quiet, the payment
          releases automatically after the review window.
        </p>
        <div className="mt-7 flex flex-col gap-3 sm:flex-row">
          <Link
            to="/new"
            className="inline-flex min-h-[48px] items-center justify-center rounded-xl bg-accent px-6 text-[15px] font-semibold text-white hover:bg-accent-hover"
          >
            Create a deal
          </Link>
          <Link
            to="/dashboard"
            className="inline-flex min-h-[48px] items-center justify-center rounded-xl border border-line bg-white/80 px-6 text-[15px] font-semibold text-ink hover:bg-white"
          >
            I'm a creator — view my deals
          </Link>
        </div>
        <div className="mt-8 grid grid-cols-1 gap-3 sm:grid-cols-3">
          <Stat label="Total deals" value={data ? data.totalDeals.toString() : '-'} loading={isLoading} />
          <Stat
            label="USDC in escrow"
            value={data ? fmtUsdc(data.totalEscrowed) : '-'}
            loading={isLoading}
          />
          <Stat
            label="Protocol fee"
            value={data ? `${(data.protocolFeeBps / 100).toFixed(2)}%` : '-'}
            loading={isLoading}
          />
        </div>
        {isError && <p className="mt-3 text-sm text-danger">Live stats are unavailable right now.</p>}
        <p className="mt-4 flex items-center gap-1.5 text-xs text-subtle">
          <TokenUSDC variant="branded" size={14} /> Amounts are in USDC. Stats are read live from the contract.
        </p>
      </section>

      <section aria-labelledby="how">
        <h2 id="how" className="display text-2xl font-bold">
          How it works
        </h2>
        <ol className="mt-4 grid gap-3 sm:grid-cols-3">
          {STEPS.map((s, i) => (
            <li key={s.title} className="card p-5">
              <div className="flex items-center gap-3">
                <span className="grid h-10 w-10 place-items-center rounded-xl bg-accent text-white">
                  <s.icon className="h-5 w-5" aria-hidden />
                </span>
                <span className="eyebrow">Step {i + 1}</span>
              </div>
              <h3 className="display mt-3 text-xl font-semibold">{s.title}</h3>
              <p className="mt-1 text-pretty text-sm text-muted">{s.body}</p>
            </li>
          ))}
        </ol>
      </section>
    </div>
  )
}
