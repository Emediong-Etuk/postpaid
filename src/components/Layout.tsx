import { Link, NavLink, Outlet } from 'react-router-dom'
import { ConnectKitButton } from 'connectkit'
import { useAccount, useSwitchChain } from 'wagmi'
import { TokenUSDC } from '@web3icons/react'
import { toast } from 'sonner'
import { ACTIVE_CHAIN } from '@/postpaid'
import { useUsdc } from '@/hooks/useEscrow'
import { fmtUsdc } from '@/lib/format'
import { describeError } from '@/lib/errors'
import { Button } from './ui'

function Logo() {
  return (
    <Link to="/" className="display flex items-center gap-2 text-xl font-bold text-ink">
      <span className="grid h-8 w-8 place-items-center rounded-lg bg-accent text-sm text-white" aria-hidden>
        P
      </span>
      PostPaid
    </Link>
  )
}

function UsdcBalance() {
  const { address } = useAccount()
  const { data } = useUsdc(address)
  if (!address) return null
  return (
    <span
      className="hidden items-center gap-1.5 rounded-full border border-line bg-white/70 px-3 py-1.5 text-sm font-semibold tabular-nums sm:inline-flex"
      title="Your USDC balance. Network fees are also paid in USDC."
    >
      <TokenUSDC variant="branded" size={16} />
      {data ? fmtUsdc(data.balance) : '...'}
    </span>
  )
}

function WrongNetworkBanner() {
  const { isConnected, chainId } = useAccount()
  const { switchChainAsync, isPending } = useSwitchChain()
  if (!isConnected || chainId === ACTIVE_CHAIN.id) return null
  return (
    <div className="border-b border-warn/30 bg-[#fdf1dc]" role="alert">
      <div className="mx-auto flex max-w-5xl flex-wrap items-center justify-between gap-2 px-4 py-2.5 text-sm text-warn">
        <span>Your wallet is on a different network. PostPaid runs on {ACTIVE_CHAIN.name}.</span>
        <Button
          size="sm"
          variant="secondary"
          loading={isPending}
          onClick={() => {
            switchChainAsync({ chainId: ACTIVE_CHAIN.id }).catch((e: unknown) => {
              const m = describeError(e)
              if (m) toast.error(m)
            })
          }}
        >
          Switch to {ACTIVE_CHAIN.name}
        </Button>
      </div>
    </div>
  )
}

const navClass = ({ isActive }: { isActive: boolean }) =>
  `rounded-lg px-3 py-2 text-sm font-semibold ${isActive ? 'bg-black/5 text-ink' : 'text-muted hover:text-ink'}`

export function Layout() {
  return (
    <div className="flex min-h-dvh flex-col">
      <header className="sticky top-0 z-30 border-b border-line bg-white/80 backdrop-blur">
        <div className="mx-auto flex max-w-5xl items-center justify-between gap-3 px-4 py-3">
          <div className="flex items-center gap-4">
            <Logo />
            <nav className="hidden items-center gap-1 sm:flex" aria-label="Main">
              <NavLink to="/new" className={navClass}>
                New deal
              </NavLink>
              <NavLink to="/dashboard" className={navClass}>
                Dashboard
              </NavLink>
            </nav>
          </div>
          <div className="flex items-center gap-2">
            <UsdcBalance />
            <ConnectKitButton.Custom>
              {({ isConnected, show, truncatedAddress, isConnecting }) => (
                <Button variant={isConnected ? 'secondary' : 'primary'} size="sm" onClick={show} loading={isConnecting}>
                  {isConnected ? truncatedAddress : 'Connect wallet'}
                </Button>
              )}
            </ConnectKitButton.Custom>
          </div>
        </div>
        <nav className="flex border-t border-line px-2 sm:hidden" aria-label="Main mobile">
          <NavLink to="/new" className={navClass}>
            New deal
          </NavLink>
          <NavLink to="/dashboard" className={navClass}>
            Dashboard
          </NavLink>
        </nav>
        <WrongNetworkBanner />
      </header>
      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6 sm:py-10">
        <Outlet />
      </main>
      <footer className="border-t border-line px-4 pb-20 pt-6 text-center text-sm text-muted">
        <p className="font-semibold text-ink-2">Not audited — use small amounts.</p>
        <p className="mt-1 text-xs">Network fees on Arc are paid in USDC. Escrowed funds can never be moved by the contract owner.</p>
      </footer>
    </div>
  )
}
