import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { ConnectKitButton } from 'connectkit'
import { erc20Abi } from 'viem'
import { useAccount } from 'wagmi'
import { Plus, Trash2 } from 'lucide-react'
import { toast } from 'sonner'
import { ESCROW_ADDRESS, MAX_MILESTONES, USDC_ADDRESS, postPaidAbi } from '@/postpaid'
import { useClient, useProtocol, useUsdc } from '@/hooks/useEscrow'
import { useSendTx } from '@/hooks/useSendTx'
import { useNow } from '@/hooks/useNow'
import { fmtUsdc, toLocalInputValue } from '@/lib/format'
import {
  DEFAULT_REVIEW,
  REVIEW_PRESETS,
  creatorReceives,
  validateDraft,
  type DealDraft,
  type MilestoneDraft,
} from '@/lib/dealForm'
import { Button, Field } from '@/components/ui'

let nextRowId = 1
const newRow = (offsetSec: number, label = ''): MilestoneDraft => ({
  id: nextRowId++,
  label,
  amount: '',
  due: toLocalInputValue(Math.floor(Date.now() / 1000) + offsetSec),
})

export function NewDeal() {
  const navigate = useNavigate()
  const client = useClient()
  const { address, isConnected } = useAccount()
  const now = useNow()
  const protocol = useProtocol()
  const usdc = useUsdc(address)
  const { send, busy } = useSendTx()
  const [showErrors, setShowErrors] = useState(false)
  const [step, setStep] = useState<'idle' | 'approving' | 'creating'>('idle')
  const [draft, setDraft] = useState<DealDraft>(() => ({
    creator: '',
    arbiter: '',
    title: '',
    briefURI: '',
    milestones: [newRow(86_400)],
    reviewPeriod: DEFAULT_REVIEW,
    maxRevisions: 1,
  }))

  const { errors, valid } = useMemo(() => validateDraft(draft, address, now), [draft, address, now])
  const feeBps = protocol.data?.protocolFeeBps ?? null
  const paused = protocol.data?.paused ?? false

  const total = useMemo(() => {
    let sum = 0n
    for (const m of draft.milestones) {
      try {
        const [w, f = ''] = m.amount.trim().split('.')
        if (/^\d*$/.test(w) && /^\d*$/.test(f) && f.length <= 6 && (w || f)) {
          sum += BigInt(w || '0') * 1_000_000n + BigInt(f.padEnd(6, '0') || '0')
        }
      } catch {
        // Ignore partial input while typing.
      }
    }
    return sum
  }, [draft.milestones])

  const split = feeBps !== null && valid ? creatorReceives(valid.amounts, feeBps) : null
  const balance = usdc.data?.balance
  const allowance = usdc.data?.allowance ?? 0n
  const needsApproval = valid ? allowance < valid.total : true
  const insufficient = valid && balance !== undefined ? balance < valid.total : false

  const update = (patch: Partial<DealDraft>) => setDraft((d) => ({ ...d, ...patch }))
  const updateRow = (id: number, patch: Partial<MilestoneDraft>) =>
    setDraft((d) => ({ ...d, milestones: d.milestones.map((m) => (m.id === id ? { ...m, ...patch } : m)) }))

  async function submit() {
    setShowErrors(true)
    if (!valid || !address) return
    if (insufficient) {
      toast.error(`You need ${fmtUsdc(valid.total)} USDC plus a little for network fees`)
      return
    }
    if (needsApproval) {
      setStep('approving')
      const approved = await send('Approve USDC', {
        address: USDC_ADDRESS,
        abi: erc20Abi,
        functionName: 'approve',
        args: [ESCROW_ADDRESS, valid.total],
      })
      if (!approved) return setStep('idle')
    }
    setStep('creating')
    const created = await send('Create deal', {
      address: ESCROW_ADDRESS,
      abi: postPaidAbi,
      functionName: 'createDeal',
      args: [
        valid.creator,
        valid.arbiter,
        draft.title.trim(),
        draft.briefURI.trim(),
        valid.labels,
        valid.amounts,
        valid.dueBys,
        draft.reviewPeriod,
        draft.maxRevisions,
      ],
    })
    setStep('idle')
    if (!created) return
    const ids = await client.readContract({
      address: ESCROW_ADDRESS,
      abi: postPaidAbi,
      functionName: 'dealsOfBrand',
      args: [address],
    })
    const id = ids[ids.length - 1]
    void navigate(id ? `/deal/${id.toString()}?new=1` : '/dashboard')
  }

  if (!isConnected) {
    return (
      <div className="card mx-auto max-w-md space-y-4 p-8 text-center">
        <h1 className="display text-2xl font-bold">Create a deal</h1>
        <p className="text-pretty text-sm text-muted">Connect the brand wallet that will lock the USDC.</p>
        <ConnectKitButton />
      </div>
    )
  }

  const err = (cond: string | undefined) => (showErrors ? cond : undefined)

  return (
    <div className="mx-auto grid max-w-5xl gap-6 lg:grid-cols-[1fr_320px]">
      <div className="space-y-5">
        <h1 className="display text-3xl font-bold">Create a deal</h1>
        {paused && (
          <p className="rounded-xl bg-[#fdf1dc] p-3 text-sm text-warn" role="alert">
            New deals are paused right now.
          </p>
        )}
        <section className="card space-y-4 p-5">
          <Field label="Creator wallet" error={err(errors.creator)} hint="The address that will accept the deal and get paid.">
            <input className="field mono" placeholder="0x..." value={draft.creator} onChange={(e) => update({ creator: e.target.value })} autoComplete="off" spellCheck={false} />
          </Field>
          <Field label="Title" error={err(errors.title)}>
            <input className="field" placeholder="Spring launch campaign" value={draft.title} onChange={(e) => update({ title: e.target.value })} />
          </Field>
          <Field label="Brief link (optional)" error={err(errors.briefURI)} hint="A Notion, Google Doc or X post describing the work.">
            <input className="field" placeholder="https://..." value={draft.briefURI} onChange={(e) => update({ briefURI: e.target.value })} />
          </Field>
        </section>

        <section className="card space-y-4 p-5">
          <div className="flex items-center justify-between">
            <h2 className="display text-xl font-semibold">Milestones</h2>
            <span className="text-xs text-subtle tabular-nums">
              {draft.milestones.length} / {MAX_MILESTONES}
            </span>
          </div>
          {showErrors && errors.general && <p className="text-sm text-danger">{errors.general}</p>}
          {draft.milestones.map((m, i) => (
            <div key={m.id} className="space-y-3 rounded-2xl border border-line bg-white/60 p-4">
              <div className="flex items-center justify-between">
                <span className="eyebrow">Milestone {i + 1}</span>
                {draft.milestones.length > 1 && (
                  <button
                    type="button"
                    aria-label={`Remove milestone ${i + 1}`}
                    onClick={() => update({ milestones: draft.milestones.filter((x) => x.id !== m.id) })}
                    className="grid h-11 w-11 place-items-center rounded-lg text-subtle hover:bg-black/5 hover:text-danger sm:h-9 sm:w-9"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                )}
              </div>
              <Field label="Label" error={err(errors.milestones[i]?.label)}>
                <input className="field" placeholder="Launch thread" value={m.label} onChange={(e) => updateRow(m.id, { label: e.target.value })} />
              </Field>
              <div className="grid gap-3 sm:grid-cols-2">
                <Field label="Amount (USDC)" error={err(errors.milestones[i]?.amount)}>
                  <input className="field tabular-nums" inputMode="decimal" placeholder="0.00" value={m.amount} onChange={(e) => updateRow(m.id, { amount: e.target.value })} />
                </Field>
                <Field label="Due" error={err(errors.milestones[i]?.due)} hint="Your local time">
                  <input className="field" type="datetime-local" value={m.due} onChange={(e) => updateRow(m.id, { due: e.target.value })} />
                </Field>
              </div>
            </div>
          ))}
          {draft.milestones.length < MAX_MILESTONES && (
            <Button variant="secondary" onClick={() => update({ milestones: [...draft.milestones, newRow(86_400)] })}>
              <Plus className="h-4 w-4" /> Add milestone
            </Button>
          )}
        </section>

        <section className="card space-y-4 p-5">
          <h2 className="display text-xl font-semibold">Review rules</h2>
          <Field label="Review period" hint="After the creator submits, you have this long to approve, ask for a revision or dispute. If you stay silent, the creator can claim payment.">
            <select className="field" value={draft.reviewPeriod} onChange={(e) => update({ reviewPeriod: Number(e.target.value) })}>
              {REVIEW_PRESETS.map((p) => (
                <option key={p.seconds} value={p.seconds}>
                  {p.label}
                </option>
              ))}
            </select>
          </Field>
          <Field label="Max revisions per milestone" hint="0 to 3. Each revision gives the creator at least one review period to resubmit.">
            <select className="field" value={draft.maxRevisions} onChange={(e) => update({ maxRevisions: Number(e.target.value) })}>
              {[0, 1, 2, 3].map((n) => (
                <option key={n} value={n}>
                  {n}
                </option>
              ))}
            </select>
          </Field>
          <Field
            label="Arbiter (optional)"
            error={err(errors.arbiter)}
            hint="A neutral wallet that can settle a disputed milestone with any split. Without one, disputes are disabled. If an arbiter goes silent, a disputed milestone splits 50/50 after 14 days."
          >
            <input className="field mono" placeholder="0x... (leave empty for none)" value={draft.arbiter} onChange={(e) => update({ arbiter: e.target.value })} autoComplete="off" spellCheck={false} />
          </Field>
        </section>
      </div>

      <aside className="lg:sticky lg:top-24 lg:self-start">
        <div className="card space-y-4 p-5">
          <p className="eyebrow">Summary</p>
          <div>
            <p className="text-sm text-muted">You lock</p>
            <p className="display text-4xl font-bold tabular-nums">{fmtUsdc(valid?.total ?? total)} <span className="text-lg text-muted">USDC</span></p>
          </div>
          <dl className="space-y-2 text-sm">
            <div className="flex justify-between">
              <dt className="text-muted">Protocol fee{feeBps !== null ? ` (${(feeBps / 100).toFixed(2)}%)` : ''}</dt>
              <dd className="font-semibold tabular-nums">{split ? fmtUsdc(split.fee) : '-'} USDC</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted">Creator receives</dt>
              <dd className="font-semibold tabular-nums">{split ? fmtUsdc(split.net) : '-'} USDC</dd>
            </div>
            <div className="flex justify-between">
              <dt className="text-muted">Your USDC balance</dt>
              <dd className="font-semibold tabular-nums">{balance !== undefined ? fmtUsdc(balance) : '...'}</dd>
            </div>
          </dl>
          <p className="text-xs text-subtle">The fee is only taken when a milestone is paid to the creator. Refunds carry no fee. Network fees are paid in USDC.</p>
          <p className="rounded-xl bg-black/5 p-3 text-sm text-ink-2">
            {needsApproval ? "You'll sign 2 transactions: Approve USDC → Create deal" : 'Allowance is already enough. You will sign 1 transaction: Create deal'}
          </p>
          {insufficient && <p className="text-sm text-danger">Your USDC balance is lower than the total.</p>}
          <Button className="w-full" onClick={() => void submit()} loading={busy || step !== 'idle'} disabled={paused}>
            {step === 'approving' ? 'Approving USDC...' : step === 'creating' ? 'Creating deal...' : 'Lock USDC & create deal'}
          </Button>
        </div>
      </aside>
    </div>
  )
}
