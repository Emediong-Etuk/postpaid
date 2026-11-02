import { useState } from 'react'
import { ExternalLink } from 'lucide-react'
import { DISPUTE_TIMEOUT_SECONDS, MilestoneStatus } from '@/postpaid'
import { fmtDateTime, fmtDuration, fmtUsdc, isXUrl } from '@/lib/format'
import type { Actions, Deal, Milestone, Role } from '@/lib/types'
import { Button, MilestoneStatusPill } from './ui'
import { ResolveModal, SubmitProofModal, TextPromptModal } from './ActionModals'

export type RunTx = (label: string, functionName: string, args: readonly unknown[]) => Promise<boolean>

interface Props {
  deal: Deal
  m: Milestone
  index: number
  a: Actions
  role: Role
  now: number
  busy: boolean
  run: RunTx
}

function ProofLink({ url }: { url: string }) {
  if (!url) return null
  let handle = ''
  if (isXUrl(url)) {
    try {
      handle = new URL(url).pathname.split('/').filter(Boolean)[0] ?? ''
    } catch {
      handle = ''
    }
  }
  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer nofollow"
      className="flex items-center justify-between gap-2 rounded-xl border border-line bg-white/70 p-3 text-sm hover:bg-white"
    >
      <span className="min-w-0">
        <span className="eyebrow block">{handle ? 'Post on X' : 'Proof'}</span>
        <span className="block truncate font-semibold text-ink-2">{handle ? `@${handle}` : url}</span>
      </span>
      <ExternalLink className="h-4 w-4 shrink-0 text-subtle" aria-hidden />
    </a>
  )
}

function Reason({ children }: { children: string }) {
  return <p className="text-xs text-subtle">{children}</p>
}

type ModalKind = null | 'submit' | 'revise' | 'dispute' | 'resolve'

export function MilestoneCard({ deal, m, index, a, role, now, busy, run }: Props) {
  const [modal, setModal] = useState<ModalKind>(null)
  const i = BigInt(index)
  const id = deal.id
  const close = () => setModal(null)
  const exec = async (label: string, fn: string, args: readonly unknown[]) => {
    const ok = await run(label, fn, args)
    if (ok) close()
  }

  const due = Number(m.dueBy)
  const reviewEnds = Number(a.reviewEndsAt)
  const disputeStaleAt = Number(m.disputedAt) + DISPUTE_TIMEOUT_SECONDS
  const isBrand = role === 'brand'
  const isCreator = role === 'creator'
  const isArbiter = role === 'arbiter'
  const hasArbiter = deal.arbiter !== '0x0000000000000000000000000000000000000000'
  const isPending = m.status === MilestoneStatus.Pending
  const isSubmitted = m.status === MilestoneStatus.Submitted
  const isDisputed = m.status === MilestoneStatus.Disputed
  const dealActive = deal.status === 1

  const buttons: React.ReactNode[] = []
  const reasons: string[] = []

  if (isPending && dealActive) {
    if (isCreator && a.canSubmit) buttons.push(<Button key="s" onClick={() => setModal('submit')}>Submit proof</Button>)
    if (isCreator && !a.canSubmit && !a.canRefund) reasons.push('The due date has passed. Anyone can refund this to the brand.')
    if (a.canRefund) {
      buttons.push(
        <Button key="r" variant="secondary" loading={busy} onClick={() => void exec('Refund milestone', 'refundMilestone', [id, i])}>
          Refund to brand
        </Button>,
      )
    } else if (isBrand && now <= due) {
      buttons.push(<Button key="rd" variant="secondary" disabled>Refund to brand</Button>)
      reasons.push(`Refund available after the due date (${fmtDateTime(due)})`)
    }
  }

  if (isSubmitted) {
    const open = now < reviewEnds
    if (isBrand) {
      buttons.push(
        <Button key="ap" disabled={!a.canApprove} loading={busy} onClick={() => void exec('Approve milestone', 'approveMilestone', [id, i])}>
          Approve & pay
        </Button>,
      )
      buttons.push(
        <Button key="rv" variant="secondary" disabled={!a.canRequestRevision} onClick={() => setModal('revise')}>
          Request revision
        </Button>,
      )
      if (hasArbiter) {
        buttons.push(
          <Button key="dp" variant="danger" disabled={!a.canDispute} onClick={() => setModal('dispute')}>
            Open dispute
          </Button>,
        )
      }
      if (!a.canRequestRevision) {
        reasons.push(open ? 'No revisions left for this milestone' : 'The review window has closed. You can still approve.')
      }
    }
    if (a.canClaimTimeout) {
      buttons.push(
        <Button key="cl" variant={isBrand ? 'secondary' : 'primary'} loading={busy} onClick={() => void exec('Claim payment', 'claimAfterTimeout', [id, i])}>
          Release to creator
        </Button>,
      )
    } else if (open) {
      reasons.push(`Review window open — auto-release in ${fmtDuration(reviewEnds - now)}`)
    }
  }

  if (isDisputed) {
    if (isArbiter) buttons.push(<Button key="res" onClick={() => setModal('resolve')}>Resolve dispute</Button>)
    if (a.canResolveStale) {
      buttons.push(
        <Button key="st" variant="secondary" loading={busy} onClick={() => void exec('Split 50/50', 'resolveStaleDispute', [id, i])}>
          Split 50/50 (arbiter timed out)
        </Button>,
      )
    } else {
      reasons.push(`The arbiter has until ${fmtDateTime(disputeStaleAt)} to decide, then anyone can split it 50/50`)
    }
  }

  return (
    <article className="card space-y-3 p-4 sm:p-5">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="eyebrow">Milestone {index + 1}</p>
          <h3 className="display truncate text-lg font-semibold">{m.label}</h3>
        </div>
        <div className="shrink-0 text-right">
          <p className="display text-xl font-bold tabular-nums">{fmtUsdc(m.amount)}</p>
          <p className="text-xs text-subtle">USDC</p>
        </div>
      </div>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1.5 text-sm text-muted">
        <MilestoneStatusPill status={m.status} />
        {m.revisionsUsed > 0 && (
          <span className="tabular-nums">Revisions {m.revisionsUsed}/{deal.maxRevisions}</span>
        )}
        {isPending && (
          <span className="tabular-nums">
            {now <= due ? `Due in ${fmtDuration(due - now)}` : `Overdue since ${fmtDateTime(due)}`}
          </span>
        )}
        {isSubmitted && (
          <span className="tabular-nums">
            {now < reviewEnds ? `Review ends in ${fmtDuration(reviewEnds - now)}` : 'Review window ended'}
          </span>
        )}
      </div>
      <ProofLink url={m.proofURI} />
      {buttons.length > 0 && <div className="flex flex-col gap-2 sm:flex-row sm:flex-wrap">{buttons}</div>}
      {reasons.map((r) => (
        <Reason key={r}>{r}</Reason>
      ))}

      {modal === 'submit' && (
        <SubmitProofModal busy={busy} onClose={close} onSubmit={(url) => void exec('Submit proof', 'submitMilestone', [id, i, url])} />
      )}
      {modal === 'revise' && (
        <TextPromptModal
          title="Request a revision"
          label="What should change?"
          hint="The creator gets at least one review period to resubmit."
          cta="Send revision request"
          optional
          busy={busy}
          onClose={close}
          onSubmit={(note) => void exec('Request revision', 'requestRevision', [id, i, note])}
        />
      )}
      {modal === 'dispute' && (
        <TextPromptModal
          title="Open a dispute"
          label="Reason"
          hint="The arbiter will decide how this milestone is split."
          cta="Open dispute"
          optional
          busy={busy}
          onClose={close}
          onSubmit={(reason) => void exec('Open dispute', 'openDispute', [id, i, reason])}
        />
      )}
      {modal === 'resolve' && (
        <ResolveModal
          amount={m.amount}
          feeBps={deal.feeBps}
          busy={busy}
          onClose={close}
          onSubmit={(bps) => void exec('Resolve dispute', 'resolveDispute', [id, i, bps])}
        />
      )}
    </article>
  )
}
