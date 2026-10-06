const required = (name: keyof ImportMetaEnv): string => {
  const value = import.meta.env[name]
  if (!value) {
    throw new Error(`${name} is not set. Run ui/scripts/write-config.sh.`)
  }
  return value
}

export const config = {
  agentUrl: required('VITE_AGENT_URL'),
  authorizeUrl: required('VITE_AUTHORIZE_URL'),
  logoutUrl: required('VITE_LOGOUT_URL'),
  clientId: required('VITE_CLIENT_ID'),
  redirectUri: `${window.location.origin}/callback`,
  // openid lets the agent identify the user; the rest are the Developer Portal permissions.
  scopes: 'openid apim:subscribe apim:app_manage apim:sub_manage',
}
