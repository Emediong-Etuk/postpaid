import { useEffect, useState } from 'react'
import { Link2, MessageCircle, Share2 } from 'lucide-react'
import { toast } from 'sonner'
import { shareLinkFor, whatsappIntent, xIntent } from '@/lib/share-actions'
import { Button } from './ui'

/** Resolves the share-safe link once on mount; controls stay disabled until it is ready. */
export function ShareButtons({ dealId, title }: { dealId: bigint; title: string }) {
  const [link, setLink] = useState<string | null>(null)
  useEffect(() => {
    let alive = true
    void shareLinkFor(dealId).then((l) => alive && setLink(l))
    return () => {
      alive = false
    }
  }, [dealId])

  const copy = async () => {
    if (!link) return
    try {
      await navigator.clipboard.writeText(link)
      toast.success('Link copied')
    } catch {
      toast.error('Could not copy. Select the link and copy it manually')
    }
  }
  const nativeShare = async () => {
    if (!link) return
    try {
      await navigator.share({ title, url: link })
    } catch {
      // Cancelled or unsupported: fall back to copying.
      await copy()
    }
  }
  const linkClass =
    'inline-flex min-h-[44px] items-center justify-center gap-2 rounded-xl border border-line bg-white/80 px-4 text-sm font-semibold text-ink hover:bg-white aria-disabled:pointer-events-none aria-disabled:opacity-50'
  return (
    <div className="flex flex-wrap gap-2">
      <Button variant="secondary" size="sm" disabled={!link} onClick={() => void copy()}>
        <Link2 className="h-4 w-4" /> Copy link
      </Button>
      <a className={linkClass} aria-disabled={!link} href={link ? xIntent(link, title) : undefined} target="_blank" rel="noopener noreferrer">
        Share to X
      </a>
      <a className={linkClass} aria-disabled={!link} href={link ? whatsappIntent(link, title) : undefined} target="_blank" rel="noopener noreferrer">
        <MessageCircle className="h-4 w-4" /> WhatsApp
      </a>
      {typeof navigator !== 'undefined' && 'share' in navigator && (
        <Button variant="ghost" size="sm" disabled={!link} onClick={() => void nativeShare()}>
          <Share2 className="h-4 w-4" /> More
        </Button>
      )}
    </div>
  )
}
