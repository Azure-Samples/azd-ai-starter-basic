targetScope = 'resourceGroup'

@description('AI Services account name')
param aiServicesAccountName string

@description('AI project name')
param aiProjectName string

// Connection configuration type definition
type ConnectionConfig = {
  @description('Name of the connection')
  name: string

  @description('Category of the connection (e.g., ContainerRegistry, AzureStorageAccount, CognitiveSearch, AzureOpenAI)')
  category: string

  @description('Target endpoint or URL for the connection')
  target: string

  @description('Authentication type')
  authType: 'AAD' | 'AccessKey' | 'AccountKey' | 'ApiKey' | 'CustomKeys' | 'ManagedIdentity' | 'None' | 'OAuth2' | 'PAT' | 'SAS' | 'ServicePrincipal' | 'UsernamePassword'

  @description('Whether the connection is shared to all users (optional, defaults to true)')
  isSharedToAll: bool?

  @description('Additional metadata for the connection (optional)')
  metadata: object?

  @description('Error message if the connection fails (optional)')
  error: string?

  @description('Expiry time for the connection (optional)')
  expiryTime: string?

  @description('Private endpoint requirement: Required, NotRequired, or NotApplicable (optional)')
  peRequirement: ('NotApplicable' | 'NotRequired' | 'Required')?

  @description('Private endpoint status: Active, Inactive, or NotApplicable (optional)')
  peStatus: ('Active' | 'Inactive' | 'NotApplicable')?

  @description('List of users to share the connection with (optional, alternative to isSharedToAll)')
  sharedUserList: string[]?

  @description('Whether to use workspace managed identity (optional)')
  useWorkspaceManagedIdentity: bool?
}

@description('Connection configuration')
param connectionConfig ConnectionConfig

@secure()
@description('Credentials for the connection. Kept as a separate @secure parameter to prevent secrets from appearing in deployment logs. Shape depends on authType — e.g. { key: "..." } for ApiKey, { clientId: "...", clientSecret: "..." } for OAuth2/ServicePrincipal.')
param credentials object = {}


// Get reference to the AI Services account and project
resource aiAccount 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesAccountName

  resource project 'projects' existing = {
    name: aiProjectName
  }
}

// Create the connection
resource connection 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: aiAccount::project
  name: connectionConfig.name
  properties: {
    category: connectionConfig.category
    target: connectionConfig.target
    authType: connectionConfig.authType
    isSharedToAll: connectionConfig.?isSharedToAll ?? true
    credentials: !empty(credentials) ? credentials : null
    metadata: connectionConfig.?metadata
    error: connectionConfig.?error
    expiryTime: connectionConfig.?expiryTime
    peRequirement: connectionConfig.?peRequirement
    peStatus: connectionConfig.?peStatus
    sharedUserList: connectionConfig.?sharedUserList
    useWorkspaceManagedIdentity: connectionConfig.?useWorkspaceManagedIdentity
  }
}

// Outputs
output connectionName string = connection.name
output connectionId string = connection.id
