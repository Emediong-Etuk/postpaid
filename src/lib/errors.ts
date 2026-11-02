import { BaseError, ContractFunctionRevertedError, decodeErrorResult } from 'viem'
import { postPaidAbi } from '@/postpaid'

const CUSTOM_MESSAGES: Record<string, string> = {
  NotBrand: 'Only the brand can do this',
  NotCreator: 'Only the creator can do this',
  NotArbiter: 'Only the arbiter can do this',
  InvalidParams: 'Some inputs are invalid (check addresses, amounts, dates and text lengths)',
  InvalidDealStatus: "The deal isn't in the right state for this",
  InvalidMilestoneStatus: "This milestone isn't in the right state for this",
  PastDue: 'The due date has passed',
  NotYetDue: 'You can refund after the due date passes',
  ReviewWindowClosed: 'The review window has closed',
  ReviewWindowOpen: 'You can claim after the review window ends',
  NoRevisionsLeft: 'No revisions left for this milestone',
  NoArbiter: 'This deal has no arbiter',
  DisputeNotStale: 'The arbiter still has time to decide (14 days)',
  AmountMismatch: "The USDC amount received didn't match",
  NothingToWithdraw: 'Nothing to withdraw yet',
  FeeTooHigh: 'Fee too high',
  EnforcedPause: 'New deals are paused right now',
  ExpectedPause: 'New deals are not paused',
  OwnableUnauthorizedAccount: 'Only the contract owner can do this',
  ReentrancyGuardReentrantCall: 'Please wait for the previous transaction to finish',
  ERC20InsufficientBalance: 'Not enough USDC in your wallet',
  ERC20InsufficientAllowance: 'USDC allowance is too low. Approve the amount first',
}

export function isUserRejection(error: unknown): boolean {
  let current: unknown = error
  for (let i = 0; i < 6 && current; i++) {
    const e = current as { code?: number; name?: string; message?: string; cause?: unknown }
    if (e.code === 4001 || e.name === 'UserRejectedRequestError') return true
    if (typeof e.message === 'string' && /user (rejected|denied)|rejected the request/i.test(e.message)) return true
    current = e.cause
  }
  return false
}

function customErrorName(error: unknown): string | undefined {
  if (error instanceof BaseError) {
    const reverted = error.walk((e) => e instanceof ContractFunctionRevertedError)
    if (reverted instanceof ContractFunctionRevertedError) {
      if (reverted.data?.errorName) return reverted.data.errorName
      if (reverted.signature) {
        try {
          return decodeErrorResult({ abi: postPaidAbi, data: reverted.raw ?? reverted.signature }).errorName
        } catch {
          return undefined
        }
      }
    }
  }
  return undefined
}

/** Plain-English message for any error a PostPaid read or write can throw. Empty string means "user cancelled, stay quiet". */
export function describeError(error: unknown): string {
  if (isUserRejection(error)) return ''
  const name = customErrorName(error)
  if (name && CUSTOM_MESSAGES[name]) return CUSTOM_MESSAGES[name]
  const text = error instanceof Error ? `${error.message} ${(error as { shortMessage?: string }).shortMessage ?? ''}` : String(error)
  const lower = text.toLowerCase()
  if (lower.includes('insufficient funds') || lower.includes('exceeds balance')) {
    return 'Not enough USDC to cover this and the network fee (gas is paid in USDC)'
  }
  if (lower.includes('allowance')) return 'USDC allowance is too low. Approve the amount first'
  if (lower.includes('chain') && lower.includes('mismatch')) return 'Switch your wallet to the Arc network and try again'
  if (lower.includes('network') || lower.includes('timeout') || lower.includes('fetch')) {
    return 'Network issue. Check your connection and try again'
  }
  if (lower.includes('revert')) return 'The transaction would fail. Refresh the page and try again'
  return 'Something went wrong. Please try again'
}
