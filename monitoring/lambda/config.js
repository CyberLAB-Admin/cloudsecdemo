/**
 * Cloud Security Demo - Lambda Configuration
 */

module.exports = {
  // Project identification
  PROJECT_NAME: process.env.PROJECT_NAME || 'cloudsecdemo',
  PROJECT_TAG: process.env.PROJECT_TAG || 'cloudsecdemo',

  // Security check thresholds
  THRESHOLDS: {
    MAX_OPEN_PORTS: 0,
    MAX_PUBLIC_BUCKETS: 0,
    MAX_WILDCARD_PERMISSIONS: 0,
  },

  // Resource patterns to monitor
  RESOURCE_PATTERNS: {
    SECURITY_GROUPS: /-sg$/,
    S3_BUCKETS: /^cloudsecdemo-/,
    IAM_ROLES: /^cloudsecdemo-/,
    EKS_CLUSTERS: /^cloudsecdemo-/
  },

  // Security check configurations
  CHECKS: {
    SECURITY_GROUPS: {
      enabled: true,
      checkOpenPorts: true,
      checkIngressRules: true,
      checkEgressRules: true
    },
    S3: {
      enabled: true,
      checkPublicAccess: true,
      checkEncryption: true,
      checkVersioning: true,
      checkLogging: true
    },
    IAM: {
      enabled: true,
      checkWildcardPermissions: true,
      checkPolicySize: true,
      checkRoleTrust: true
    },
    EKS: {
      enabled: true,
      checkPrivateEndpoint: true,
      checkEncryption: true,
      checkLogging: true,
      checkNetworkPolicies: true
    }
  },

  // Alert configurations
  ALERTS: {
    enabled: true,
    severityLevels: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL'],
    thresholds: {
      CRITICAL: 1,
      HIGH: 3,
      MEDIUM: 5,
      LOW: 10
    }
  },

  // Monitoring intervals (in minutes)
  INTERVALS: {
    securityCheck: 5,
    metricPublication: 1,
    alertAggregation: 15
  }
};
