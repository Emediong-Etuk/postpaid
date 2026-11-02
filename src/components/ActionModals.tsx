import { useState } from 'react'
import { byteLength, fmtUsdc, isHttpUrl, isXUrl } from '@/lib/format'
import { Button, Field } from './ui'
import { Modal } from './Modal'

export function SubmitProofModal({ onClose, onSubmit, busy }: { onClose: () => void; onSubmit: (url: string) => void; busy: boolean }) {
  const [url, setUrl] = useState('')
  const value = url.trim()
  const bytes = byteLength(value)
  const error = !value ? null : !isHttpUrl(value) ? 'That does not look like a link (start with https://)' : bytes > 280 ? 'Link must be 280 bytes or fewer' : null
  const warn = value && !error && !isXUrl(value) ? 'This is not an x.com or twitter.com link. You can still submit it.' : null
  return (
    <Modal title="Submit proof" onClose={onClose}>
      <div className="space-y-4">
        <Field label="Link to your post or deliverable" error={error} hint="Paste the link to the live post. The brand reviews it from here.">
          <input className="field" inputMode="url" placeholder="https://x.com/you/status/..." value={url} onChange={(e) => setUrl(e.target.value)} autoFocus />
        </Field>
        {warn && <p className="rounded-xl bg-[#fdf1dc] p-3 text-sm text-warn">{warn}</p>}
        <Button className="w-full" disabled={!value || !!error} loading={busy} onClick={() => onSubmit(value)}>
          Submit proof
        </Button>
      </div>
    </Modal>
  )
}

export function TextPromptModal(props: {
  title: string
  label: string
  hint: string
  cta: string
  optional?: boolean
  busy: boolean
  onClose: () => void
  onSubmit: (text: string) => void
}) {
  const [text, setText] = useState('')
  const tooLong = byteLength(text) > 280
  return (
    <Modal title={props.title} onClose={props.onClose}>
      <div className="space-y-4">
        <Field label={props.label} hint={props.hint} error={tooLong ? 'Keep it to 280 bytes or fewer' : null}>
          <textarea className="field min-h-[96px]" value={text} onChange={(e) => setText(e.target.value)} autoFocus />
        </Field>
        <Button className="w-full" disabled={tooLong || (!props.optional && !text.trim())} loading={props.busy} onClick={() => props.onSubmit(text.trim())}>
          {props.cta}
        </Button>
      </div>
    </Modal>
  )
}

export function ResolveModal(props: { amount: bigint; feeBps: number; busy: boolean; onClose: () => void; onSubmit: (bps: number) => void }) {
  const [pct, setPct] = useState(50)
  const bps = pct * 100
  const gross = (props.amount * BigInt(bps)) / 10_000n
  const fee = (gross * BigInt(props.feeBps)) / 10_000n
  const brandPart = props.amount - gross
  return (
    <Modal title="Resolve dispute" onClose={props.onClose}>
      <div className="space-y-4">
        <label className="block">
          <span className="mb-1.5 block text-sm font-semibold text-ink-2">Share for the creator: {pct}%</span>
          <input type="range" min={0} max={100} step={1} value={pct} onChange={(e) => setPct(Number(e.target.value))} className="h-11 w-full accent-[#122d45]" />
        </label>
        <dl className="space-y-2 rounded-xl bg-black/5 p-3 text-sm">
          <div className="flex justify-between"><dt>Creator receives</dt><dd className="font-semibold tabular-nums">{fmtUsdc(gross - fee)} USDC</dd></div>
          <div className="flex justify-between"><dt>Brand refunded</dt><dd className="font-semibold tabular-nums">{fmtUsdc(brandPart)} USDC</dd></div>
          <div className="flex justify-between"><dt>Protocol fee</dt><dd className="font-semibold tabular-nums">{fmtUsdc(fee)} USDC</dd></div>
        </dl>
        <p className="text-xs text-subtle">This decision is final.</p>
        <Button className="w-full" loading={props.busy} onClick={() => props.onSubmit(bps)}>
          Confirm resolution
        </Button>
      </div>
    </Modal>
  )
}
