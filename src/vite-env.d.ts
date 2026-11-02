/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_CHAIN?: string
  readonly VITE_ESCROW_ADDRESS?: string
  readonly VITE_DEPLOY_BLOCK?: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
