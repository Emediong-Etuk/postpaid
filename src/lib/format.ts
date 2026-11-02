import { formatUsdc, parseUsdc } from '@/onchain-money'

/** USDC (6 decimals) as a plain string with at least two decimals, e.g. "0.30" or "297.123456". */
export function fmtUsdc(raw: bigint): string {
  const exact = formatUsdc(raw)
  const [whole, frac = ''] = exact.split('.')
  const grouped = whole.replace(/\B(?=(\d{3})+(?!\d))/g, ',')
  return `${grouped}.${frac.padEnd(2, '0')}`
}

export function parseUsdcInput(value: string): bigint | null {
  try {
    const raw = parseUsdc(value)
    return raw >= 0n ? raw : null
  } catch {
    return null
  }
}

export const shortAddress = (addr: string) => `${addr.slice(0, 6)}...${addr.slice(-4)}`

export const byteLength = (s: string) => new TextEncoder().encode(s).length

export const NO_ADDRESS = '0x0000000000000000000000000000000000000000'

export function fmtDuration(totalSeconds: number): string {
  const s = Math.max(0, Math.floor(totalSeconds))
  const d = Math.floor(s / 86400)
  const h = Math.floor((s % 86400) / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  if (d > 0) return `${d}d ${h}h`
  if (h > 0) return `${h}h ${m}m`
  if (m > 0) return `${m}m ${sec}s`
  return `${sec}s`
}

export function fmtDateTime(unixSeconds: number): string {
  return new Date(unixSeconds * 1000).toLocaleString(undefined, {
    month: 'short',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

/** Value for <input type="datetime-local"> in local time. */
export function toLocalInputValue(unixSeconds: number): string {
  const d = new Date(unixSeconds * 1000)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`
}

export function isHttpUrl(value: string): boolean {
  try {
    const u = new URL(value)
    return u.protocol === 'https:' || u.protocol === 'http:'
  } catch {
    return false
  }
}

export function isXUrl(value: string): boolean {
  try {
    const host = new URL(value).hostname.replace(/^www\./, '')
    return host === 'x.com' || host === 'twitter.com' || host === 'mobile.twitter.com'
  } catch {
    return false
  }
}
