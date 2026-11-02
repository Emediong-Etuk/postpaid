import { useCallback, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'
import { useAccount, usePublicClient, useSwitchChain, useWriteContract } from 'wagmi'
import type { Abi, Address } from 'viem'
import {
  ACTIVE_CHAIN,
  MIN_MAX_FEE_PER_GAS,
  MIN_PRIORITY_FEE_PER_GAS,
  txUrl,
} from '@/postpaid'
import { describeError } from '@/lib/errors'

export interface TxCall {
  address: Address
  abi: Abi
  functionName: string
  args?: readonly unknown[]
}

/** Price every write at or above Arc's mempool floor (20 gwei); we use 25 gwei / 1 gwei minimums. */
export function clampFees(est?: { maxFeePerGas?: bigint; maxPriorityFeePerGas?: bigint }) {
  const maxPriorityFeePerGas =
    est?.maxPriorityFeePerGas && est.maxPriorityFeePerGas > MIN_PRIORITY_FEE_PER_GAS
      ? est.maxPriorityFeePerGas
      : MIN_PRIORITY_FEE_PER_GAS
  let maxFeePerGas = est?.maxFeePerGas && est.maxFeePerGas > MIN_MAX_FEE_PER_GAS ? est.maxFeePerGas : MIN_MAX_FEE_PER_GAS
  if (maxFeePerGas < maxPriorityFeePerGas) maxFeePerGas = maxPriorityFeePerGas
  return { maxFeePerGas, maxPriorityFeePerGas }
}

/**
 * Sends one contract write: switches to Arc if needed, simulates (so reverts are decoded before the wallet opens),
 * clamps fees, shows pending then confirmed toasts, and refetches all reads on confirmation.
 * Resolves true only when the transaction was mined successfully.
 */
export function useSendTx() {
  const { address, chainId } = useAccount()
  const { switchChainAsync } = useSwitchChain()
  const { writeContractAsync } = useWriteContract()
  const client = usePublicClient({ chainId: ACTIVE_CHAIN.id })
  const queryClient = useQueryClient()
  const [busy, setBusy] = useState(false)

  const send = useCallback(
    async (label: string, call: TxCall): Promise<boolean> => {
      if (!address || !client) {
        toast.error('Connect your wallet to continue')
        return false
      }
      const toastId = toast.loading(`${label}: confirm in your wallet`)
      setBusy(true)
      try {
        if (chainId !== ACTIVE_CHAIN.id) await switchChainAsync({ chainId: ACTIVE_CHAIN.id })
        await client.simulateContract({ ...call, account: address })
        const fees = clampFees(await client.estimateFeesPerGas().catch(() => undefined))
        const hash = await writeContractAsync({ ...call, account: address, chainId: ACTIVE_CHAIN.id, ...fees })
        toast.loading(`${label}: confirming`, { id: toastId })
        const receipt = await client.waitForTransactionReceipt({ hash })
        if (receipt.status !== 'success') {
          toast.error(`${label} failed onchain`, {
            id: toastId,
            action: { label: 'View', onClick: () => window.open(txUrl(hash), '_blank', 'noopener,noreferrer') },
          })
          return false
        }
        toast.success(`${label}: confirmed`, {
          id: toastId,
          action: { label: 'View transaction', onClick: () => window.open(txUrl(hash), '_blank', 'noopener,noreferrer') },
        })
        await queryClient.invalidateQueries()
        return true
      } catch (error) {
        const message = describeError(error)
        if (message) toast.error(message, { id: toastId })
        else toast.dismiss(toastId)
        return false
      } finally {
        setBusy(false)
      }
    },
    [address, chainId, client, queryClient, switchChainAsync, writeContractAsync],
  )

  return { send, busy }
}
