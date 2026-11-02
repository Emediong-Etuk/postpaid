import { useState } from 'react'
import { useAccount, useConnect, useDisconnect, type Connector } from 'wagmi'
import { Check, Copy, LogOut, Wallet } from 'lucide-react'
import { toast } from 'sonner'
import { ACTIVE_CHAIN } from '@/postpaid'
import { shortAddress } from '@/lib/format'
import { Button } from './ui'
import { Modal } from './Modal'

/**
 * Wallet connect built on wagmi only. It deliberately avoids ConnectKit's button and profile views,
 * which look up ENS names and avatars on Ethereum mainnet.
 */
export function ConnectButton({ size = 'sm', className }: { size?: 'md' | 'sm'; className?: string }) {
  const { address, isConnected, isConnecting } = useAccount()
  const { connectors, connectAsync, isPending } = useConnect()
  const { disconnect } = useDisconnect()
  const [picker, setPicker] = useState(false)
  const [menu, setMenu] = useState(false)
  const [copied, setCopied] = useState(false)

  const options = connectors.filter((c) => c.id !== 'injected' || connectors.length === 1)

  async function connectWith(connector: Connector) {
    try {
      await connectAsync({ connector, chainId: ACTIVE_CHAIN.id })
      setPicker(false)
    } catch (e) {
      const text = e instanceof Error ? e.message.toLowerCase() : ''
      if (text.includes('provider not found') || text.includes('not found')) {
        toast.error('No browser wallet found. Install MetaMask or Rabby and reload.')
      } else if (!text.includes('rejected') && !text.includes('denied')) {
        toast.error('Could not connect your wallet. Please try again.')
      }
    }
  }

  if (isConnected && address) {
    return (
      <div className="relative">
        <Button variant="secondary" size={size} className={className} onClick={() => setMenu((m) => !m)} aria-expanded={menu}>
          <span className="mono text-[13px]">{shortAddress(address)}</span>
        </Button>
        {menu && (
          <>
            <button type="button" aria-label="Close menu" className="fixed inset-0 z-40 cursor-default" onClick={() => setMenu(false)} />
            <div className="absolute right-0 z-50 mt-2 w-52 rounded-2xl border border-line bg-white p-1.5 shadow-xl">
              <button
                type="button"
                className="flex min-h-[44px] w-full items-center gap-2 rounded-xl px-3 text-sm font-semibold hover:bg-black/5"
                onClick={() => {
                  void navigator.clipboard?.writeText(address).then(() => {
                    setCopied(true)
                    setTimeout(() => setCopied(false), 1500)
                  })
                }}
              >
                {copied ? <Check className="h-4 w-4 text-success" /> : <Copy className="h-4 w-4" />} {copied ? 'Copied' : 'Copy address'}
              </button>
              <button
                type="button"
                className="flex min-h-[44px] w-full items-center gap-2 rounded-xl px-3 text-sm font-semibold hover:bg-black/5"
                onClick={() => {
                  disconnect()
                  setMenu(false)
                }}
              >
                <LogOut className="h-4 w-4" /> Disconnect
              </button>
            </div>
          </>
        )}
      </div>
    )
  }

  return (
    <>
      <Button
        size={size}
        className={className}
        loading={isConnecting || isPending}
        onClick={() => {
          if (options.length === 1) void connectWith(options[0])
          else setPicker(true)
        }}
      >
        Connect wallet
      </Button>
      {picker && (
        <Modal title="Connect a wallet" onClose={() => setPicker(false)}>
          {options.length === 0 ? (
            <p className="text-sm text-muted">No browser wallet found. Install MetaMask or Rabby, then reload this page.</p>
          ) : (
            <ul className="space-y-2">
              {options.map((c) => (
                <li key={c.uid}>
                  <button
                    type="button"
                    onClick={() => void connectWith(c)}
                    className="flex min-h-[48px] w-full items-center gap-3 rounded-xl border border-line px-3 text-left text-[15px] font-semibold hover:bg-black/5"
                  >
                    {c.icon ? <img src={c.icon} alt="" className="h-7 w-7 rounded-md" /> : <Wallet className="h-5 w-5" aria-hidden />}
                    {c.name}
                  </button>
                </li>
              ))}
            </ul>
          )}
        </Modal>
      )}
    </>
  )
}
