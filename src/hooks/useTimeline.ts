import { useQuery } from '@tanstack/react-query'
import { decodeEventLog, numberToHex, type Hash } from 'viem'
import { DEPLOY_BLOCK, ESCROW_ADDRESS, postPaidAbi } from '@/postpaid'
import { useClient } from './useEscrow'

const CHUNK = 10_000n
const PARALLEL = 4

export interface TimelineEntry {
  key: string
  name: string
  args: Record<string, unknown>
  blockNumber: bigint
  txHash: Hash
  logIndex: number
  timestamp?: number
}

/**
 * PostPaid's own events for one deal, read from the deploy block in chunks of at most 10,000 blocks.
 * Every deal event has dealId as its first indexed topic, so the node filters by it; USDC Transfer logs are never requested.
 */
export function useDealTimeline(dealId: bigint | null) {
  const client = useClient()
  return useQuery({
    queryKey: ['timeline', dealId?.toString()],
    enabled: dealId !== null,
    refetchInterval: 30_000,
    queryFn: async (): Promise<TimelineEntry[]> => {
      const head = await client.getBlockNumber()
      const ranges: Array<[bigint, bigint]> = []
      for (let from = DEPLOY_BLOCK; from <= head; from += CHUNK) {
        const to = from + CHUNK - 1n > head ? head : from + CHUNK - 1n
        ranges.push([from, to])
      }
      const topic = numberToHex(dealId!, { size: 32 })
      const entries: TimelineEntry[] = []
      for (let i = 0; i < ranges.length; i += PARALLEL) {
        const batch = await Promise.all(
          ranges.slice(i, i + PARALLEL).map(([from, to]) =>
            client.request({
              method: 'eth_getLogs',
              params: [
                {
                  address: ESCROW_ADDRESS,
                  fromBlock: numberToHex(from),
                  toBlock: numberToHex(to),
                  topics: [null, topic],
                },
              ],
            }),
          ),
        )
        for (const logs of batch) {
          for (const log of logs) {
            if (!log.transactionHash || log.blockNumber === null || log.logIndex === null) continue
            try {
              const decoded = decodeEventLog({ abi: postPaidAbi, data: log.data, topics: log.topics })
              entries.push({
                key: `${log.transactionHash}-${log.logIndex}`,
                name: decoded.eventName,
                args: (decoded.args ?? {}),
                blockNumber: BigInt(log.blockNumber),
                txHash: log.transactionHash,
                logIndex: Number(BigInt(log.logIndex)),
              })
            } catch {
              // Not one of PostPaid's events; ignore.
            }
          }
        }
      }
      const blocks = [...new Set(entries.map((e) => e.blockNumber))]
      const times = new Map<bigint, number>()
      await Promise.all(
        blocks.map(async (n) => {
          try {
            const b = await client.getBlock({ blockNumber: n })
            times.set(n, Number(b.timestamp))
          } catch {
            // Timestamp is optional.
          }
        }),
      )
      return entries
        .map((e) => ({ ...e, timestamp: times.get(e.blockNumber) }))
        .sort((a, b) => (a.blockNumber === b.blockNumber ? a.logIndex - b.logIndex : a.blockNumber < b.blockNumber ? -1 : 1))
    },
  })
}
