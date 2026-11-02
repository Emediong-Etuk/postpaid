import { Link } from 'react-router-dom'
import { EmptyState } from '@/components/ui'

export function NotFound() {
  return (
    <EmptyState
      title="Page not found"
      body="That link doesn't lead anywhere in PostPaid."
      action={
        <Link to="/" className="font-semibold text-accent-hover underline">
          Back to the start
        </Link>
      }
    />
  )
}
