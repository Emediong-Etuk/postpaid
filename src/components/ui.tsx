import { useState, type ButtonHTMLAttributes, type ReactNode } from 'react'
import { Check, Copy, ExternalLink, Loader2 } from 'lucide-react'
import clsx from 'clsx'
import { addressUrl } from '@/postpaid'
import { shortAddress } from '@/lib/format'
import { DEAL_STATUS_LABEL, MILESTONE_STATUS_LABEL } from '@/postpaid'

type Variant = 'primary' | 'secondary' | 'ghost' | 'danger'

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: Variant
  loading?: boolean
  size?: 'md' | 'sm'
}

const VARIANTS: Record<Variant, string> = {
  primary: 'bg-accent text-white hover:bg-accent-hover',
  secondary: 'bg-white/80 text-ink border border-line hover:bg-white',
  ghost: 'bg-transparent text-ink-2 hover:bg-black/5',
  danger: 'bg-white text-danger border border-danger/40 hover:bg-danger/5',
}

export function Button({ variant = 'primary', loading, size = 'md', className, children, disabled, ...rest }: ButtonProps) {
  return (
    <button
      {...rest}
      disabled={disabled || loading}
      className={clsx(
        'inline-flex items-center justify-center gap-2 rounded-xl font-semibold transition-colors active:scale-[0.99]',
        'disabled:cursor-not-allowed disabled:opacity-50',
        size === 'md' ? 'min-h-[44px] px-4 text-[15px]' : 'min-h-[44px] px-3 text-sm sm:min-h-[36px]',
        VARIANTS[variant],
        className,
      )}
    >
      {loading && <Loader2 className="h-4 w-4 animate-spin" aria-hidden />}
      {children}
    </button>
  )
}

export function Skeleton({ className }: { className?: string }) {
  return <div className={clsx('skeleton', className)} aria-hidden />
}

export function CopyButton({ value, label }: { value: string; label: string }) {
  const [done, setDone] = useState(false)
  return (
    <button
      type="button"
      aria-label={label}
      onClick={() => {
        void navigator.clipboard?.writeText(value).then(() => {
          setDone(true)
          setTimeout(() => setDone(false), 1500)
        })
      }}
      className="inline-flex h-8 w-8 items-center justify-center rounded-lg text-subtle hover:bg-black/5 hover:text-ink"
    >
      {done ? <Check className="h-4 w-4 text-success" /> : <Copy className="h-4 w-4" />}
    </button>
  )
}

export function AddressChip({ address, label }: { address: string; label?: string }) {
  return (
    <span className="inline-flex items-center gap-0.5">
      {label && <span className="eyebrow mr-1.5">{label}</span>}
      <a
        href={addressUrl(address)}
        target="_blank"
        rel="noopener noreferrer"
        className="mono inline-flex items-center gap-1 text-[13px] text-ink-2 hover:underline"
        title={address}
      >
        {shortAddress(address)}
        <ExternalLink className="h-3 w-3 text-subtle" aria-hidden />
      </a>
      <CopyButton value={address} label={`Copy ${label ?? 'address'}`} />
    </span>
  )
}

const TONES = {
  neutral: 'bg-black/5 text-ink-2',
  info: 'bg-[#e6f0fc] text-[#1061a6]',
  success: 'bg-[#e4f4ea] text-success',
  warn: 'bg-[#fdf1dc] text-warn',
  danger: 'bg-[#fbe8ed] text-danger',
} as const

export function Pill({ tone = 'neutral', children }: { tone?: keyof typeof TONES; children: ReactNode }) {
  return (
    <span className={clsx('inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold', TONES[tone])}>
      {children}
    </span>
  )
}

const DEAL_TONE = ['info', 'warn', 'neutral', 'success'] as const
export function DealStatusPill({ status }: { status: number }) {
  return <Pill tone={DEAL_TONE[status] ?? 'neutral'}>{DEAL_STATUS_LABEL[status] ?? 'Unknown'}</Pill>
}

const MS_TONE = ['neutral', 'info', 'danger', 'success', 'neutral', 'warn'] as const
export function MilestoneStatusPill({ status }: { status: number }) {
  return <Pill tone={MS_TONE[status] ?? 'neutral'}>{MILESTONE_STATUS_LABEL[status] ?? 'Unknown'}</Pill>
}

export function EmptyState({ title, body, action }: { title: string; body: string; action?: ReactNode }) {
  return (
    <div className="card flex flex-col items-center gap-2 px-6 py-10 text-center">
      <p className="display text-lg font-semibold">{title}</p>
      <p className="max-w-sm text-pretty text-sm text-muted">{body}</p>
      {action && <div className="mt-3">{action}</div>}
    </div>
  )
}

export function ErrorState({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="card flex flex-col items-center gap-2 px-6 py-8 text-center" role="alert">
      <p className="text-sm text-danger">{message}</p>
      {onRetry && (
        <Button variant="secondary" size="sm" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  )
}

export function Field({ label, hint, error, children }: { label: string; hint?: string; error?: string | null; children: ReactNode }) {
  return (
    <label className="block">
      <span className="mb-1.5 block text-sm font-semibold text-ink-2">{label}</span>
      {children}
      {error ? (
        <span className="mt-1 block text-xs text-danger">{error}</span>
      ) : hint ? (
        <span className="mt-1 block text-xs text-subtle">{hint}</span>
      ) : null}
    </label>
  )
}
