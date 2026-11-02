import { ExternalLink, ShieldAlert } from 'lucide-react'
import { fmtUsdc, isHttpUrl, NO_ADDRESS } from '@/lib/format'
import type { Deal, Role } from '@/lib/types'
import { AddressChip, DealStatusPill, Pill } from './ui'
import { ShareButtons } from './ShareButtons'

const ROLE_LABEL: Record<Role, string> = { brand: 'You are the brand', creator: 'You are the creator', arbiter: 'You are the arbiter', viewer: '' }

export function DealHeader({ deal, role, justCreated }: { deal: Deal; role: Role; justCreated: boolean }) {
  return (
    <section className="card space-y-4 p-5 sm:p-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="eyebrow">Deal #{deal.id.toString()}</p>
          <h1 className="display text-balance break-words text-3xl font-bold">{deal.title}</h1>
        </div>
        <div className="flex flex-wrap items-center gap-2">
          {role !== 'viewer' && <Pill tone="info">{ROLE_LABEL[role]}</Pill>}
          <DealStatusPill status={deal.status} />
        </div>
      </div>

      <div className="grid grid-cols-2 gap-3">
        <div className="rounded-2xl bg-white/70 p-4">
          <p className="eyebrow">Total</p>
          <p className="display text-2xl font-bold tabular-nums">{fmtUsdc(deal.totalAmount)} <span className="text-sm text-muted">USDC</span></p>
        </div>
        <div className="rounded-2xl bg-white/70 p-4">
          <p className="eyebrow">Still in escrow</p>
          <p className="display text-2xl font-bold tabular-nums">{fmtUsdc(deal.escrowed)} <span className="text-sm text-muted">USDC</span></p>
        </div>
      </div>

      <div className="flex flex-col gap-1.5">
        <AddressChip address={deal.brand} label="Brand" />
        <AddressChip address={deal.creator} label="Creator" />
        {deal.arbiter !== NO_ADDRESS ? <AddressChip address={deal.arbiter} label="Arbiter" /> : <p className="text-sm text-subtle"><span className="eyebrow mr-1.5">Arbiter</span>None. Disputes are disabled</p>}
      </div>

      {deal.briefURI &&
        (isHttpUrl(deal.briefURI) ? (
          <a href={deal.briefURI} target="_blank" rel="noopener noreferrer nofollow" className="inline-flex items-center gap-1.5 text-sm font-semibold text-accent-hover underline">
            Read the brief <ExternalLink className="h-3.5 w-3.5" aria-hidden />
          </a>
        ) : (
          <p className="break-all text-sm text-muted">Brief: {deal.briefURI}</p>
        ))}

      {justCreated && (
        <div className="rounded-2xl bg-[#e4f4ea] p-4">
          <p className="text-sm font-semibold text-success">Deal created. Send this link to the creator so they can accept.</p>
          <div className="mt-3">
            <ShareButtons dealId={deal.id} title={deal.title} />
          </div>
        </div>
      )}
      {!justCreated && (
        <div>
          <p className="eyebrow mb-2">Share</p>
          <ShareButtons dealId={deal.id} title={deal.title} />
        </div>
      )}
      <p className="flex items-center gap-1.5 text-xs text-subtle">
        <ShieldAlert className="h-3.5 w-3.5" aria-hidden /> Not audited — use small amounts.
      </p>
    </section>
  )
}
