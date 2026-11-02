/**
 * wagmi configuration
 * Built with Arc Studio — https://studio.arc.io
 */

import { http, createConfig } from 'wagmi'
import { arc, arcTestnet } from 'viem/chains'
import { ACTIVE_CHAIN } from './postpaid'
import { injected } from 'wagmi/connectors'
import { registerChain } from './tracing'

// Pre-register chain RPC URLs so trace events show correct chain names immediately
registerChain(ACTIVE_CHAIN.id, ACTIVE_CHAIN.rpcUrls.default.http[0])

export const config = createConfig({
  chains: [ACTIVE_CHAIN, ACTIVE_CHAIN.id === arc.id ? arcTestnet : arc], // Arc only: no Ethereum mainnet, no ENS lookups
  connectors: [injected()],
  transports: {
    [arc.id]: http(),
    [arcTestnet.id]: http(),
  },
})
