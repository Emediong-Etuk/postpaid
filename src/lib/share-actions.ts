import { buildShareLink } from '@/lib/share'

export function dealPath(id: bigint | string) {
  return `/deal/${id.toString()}`
}

export const shareLinkFor = (id: bigint | string) => buildShareLink(dealPath(id))

export const xIntent = (link: string, title: string) =>
  `https://x.com/intent/post?text=${encodeURIComponent(`${title} on PostPaid`)}&url=${encodeURIComponent(link)}`

export const whatsappIntent = (link: string, title: string) =>
  `https://wa.me/?text=${encodeURIComponent(`${title} on PostPaid: ${link}`)}`
