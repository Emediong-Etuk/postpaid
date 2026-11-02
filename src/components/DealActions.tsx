import { useState } from 'react'
import { fmtDuration, NO_ADDRESS } from '@/lib/format'
import type { Deal, Milestone, Role } from '@/lib/types'
import { MilestoneStatus } from '@/postpaid'
import { Button } from './ui'
import { Modal } from './Modal'
import type { RunTx } from './MilestoneCard'

function Terms({ deal }: { deal: Deal }) {
  const hasArbiter = deal.arbiter !== NO_ADDRESS
  const shortReview = deal.reviewPeriod < 3600
  return (
    <div className="space-y-3">
      <dl className="grid grid-cols-2 gap-3 text-sm">
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="eyebrow">Review period</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">{fmtDuration(deal.reviewPeriod)}</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="eyebrow">Max revisions</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">{deal.maxRevisions} per milestone</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="eyebrow">Protocol fee</dt>
          <dd className="mt-0.5 font-semibold tabular-nums">{(deal.feeBps / 100).toFixed(2)}% of each payout</dd>
        </div>
        <div className="rounded-xl bg-white/70 p-3">
          <dt className="eyebrow">Arbiter</dt>
          <dd className="mt-0.5 font-semibold">{hasArbiter ? 'Yes' : 'None'}</dd>
        </div>
      </dl>
      <p className="text-sm text-muted">If the brand does not respond within the review period after you submit, you can claim the payment yourself.</p>
      {shortReview && (
        <p className="rounded-xl bg-[#fdf1dc] p-3 text-sm text-warn" role="note">
          Short review period: after a revision request you get at least one review period ({fmtDuration(deal.reviewPeriod)}) to resubmit. Be ready to respond quickly.
        </p>
      )}
      {hasArbiter && (
        <p className="rounded-xl bg-[#fdf1dc] p-3 text-sm text-warn" role="note">
          The arbiter can decide any split of a disputed milestone. Only accept if you trust them.
        </p>
      )}
    </div>
  )
}

export function DealActions({ deal, milestones, role, busy, run }: { deal: Deal; milestones: Milestone[]; role: Role; busy: boolean; run: RunTx }) {
  const [confirm, setConfirm] = useState<'cancel' | 'exit' | null>(null)
  const isOpen = deal.status === 0
  const isActive = deal.status === 1
  const hasPending = milestones.some((m) => m.status === MilestoneStatus.Pending)

  if (isOpen && role === 'creator') {
    return (
      <section className="card space-y-4 p-5">
        <h2 className="display text-xl font-semibold">Review the terms</h2>
        <Terms deal={deal} />
        <Button className="w-full" loading={busy} onClick={() => void run('Accept deal', 'acceptDeal', [deal.id])}>
          Accept deal
        </Button>
      </section>
    )
  }
  if (isOpen && role === 'brand') {
    return (
      <section className="card space-y-3 p-5">
        <h2 className="display text-xl font-semibold">Waiting for the creator</h2>
        <p className="text-sm text-muted">Your USDC is locked. Share the link so the creator can accept. You can cancel for a full refund until they do.</p>
        <Button variant="danger" onClick={() => setConfirm('cancel')}>Cancel & refund</Button>
        {confirm === 'cancel' && (
          <Modal title="Cancel this deal?" onClose={() => setConfirm(null)}>
            <p className="mb-4 text-sm text-muted">The full escrowed amount is credited back to you. Withdraw it from your dashboard afterwards.</p>
            <Button variant="danger" className="w-full" loading={busy} onClick={() => void run('Cancel deal', 'cancelDeal', [deal.id]).then((ok) => ok && setConfirm(null))}>
              Cancel & refund
            </Button>
          </Modal>
        )}
      </section>
    )
  }
  if (isOpen) {
    return (
      <section className="card space-y-3 p-5">
        <h2 className="display text-xl font-semibold">Open deal</h2>
        <Terms deal={deal} />
      </section>
    )
  }
  if (isActive && role === 'creator' && hasPending) {
    return (
      <section className="card flex flex-col gap-2 p-4 sm:flex-row sm:items-center sm:justify-between">
        <p className="text-sm text-muted">Need to step away? Exiting refunds every milestone you have not submitted yet to the brand.</p>
        <Button variant="danger" size="sm" onClick={() => setConfirm('exit')}>Exit deal</Button>
        {confirm === 'exit' && (
          <Modal title="Exit this deal?" onClose={() => setConfirm(null)}>
            <p className="mb-4 text-sm text-muted">Milestones that are still pending are refunded to the brand. Submitted work can still be approved and paid.</p>
            <Button variant="danger" className="w-full" loading={busy} onClick={() => void run('Exit deal', 'creatorExit', [deal.id]).then((ok) => ok && setConfirm(null))}>
              Exit deal
            </Button>
          </Modal>
        )}
      </section>
    )
  }
  return null
}
