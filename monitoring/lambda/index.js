/**
 * Cloud Security Demo - Security Monitoring Lambda Function
 * 
 * This Lambda function monitors and reports on the security state of the infrastructure.
 * It checks:
 * - Security group configurations
 * - S3 bucket policies
 * - IAM roles and policies
 * - EKS security settings
 * - Resource tags
 * - Encryption status
 */

const AWS = require('aws-sdk');
const config = require('./config');

// AWS service clients
const ec2 = new AWS.EC2();
const s3 = new AWS.S3();
const iam = new AWS.IAM();
const eks = new AWS.EKS();
const cloudwatch = new AWS.CloudWatch();
const sns = new AWS.SNS();

// Security check statuses
const STATUS = {
  PASS: 'PASS',
  FAIL: 'FAIL',
  ERROR: 'ERROR'
};

/**
 * Main handler function
 */
exports.handler = async (event) => {
  console.log('Starting security check run');
  
  try {
    // Get all resources with project tag
    const resources = await getTaggedResources();
    
    // Run security checks
    const results = await runSecurityChecks(resources);
    
    // Process results
    await processResults(results);
    
    return {
      statusCode: 200,
      body: JSON.stringify(results)
    };
  } catch (error) {
    console.error('Error in security check:', error);
    await sendAlert({
      title: 'Security Check Error',
      message: error.message,
      severity: 'CRITICAL'
    });
    throw error;
  }
};

/**
 * Get all resources tagged with project tag
 */
async function getTaggedResources() {
  const resources = {
    securityGroups: [],
    s3Buckets: [],
    iamRoles: [],
    eksClusters: []
  };

  try {
    // Get security groups
    const sgResponse = await ec2.describeSecurityGroups({
      Filters: [{
        Name: 'tag:Project',
        Values: [config.PROJECT_TAG]
      }]
    }).promise();
    resources.securityGroups = sgResponse.SecurityGroups;

    // Get S3 buckets
    const buckets = await s3.listBuckets().promise();
    resources.s3Buckets = buckets.Buckets.filter(async bucket => {
      const tags = await s3.getBucketTagging({ Bucket: bucket.Name }).promise();
      return tags.TagSet.some(tag => 
        tag.Key === 'Project' && tag.Value === config.PROJECT_TAG
      );
    });

    // Get IAM roles
    const roles = await iam.listRoles().promise();
    resources.iamRoles = roles.Roles.filter(role => 
      role.RoleName.includes(config.PROJECT_NAME)
    );

    // Get EKS clusters
    const clusters = await eks.listClusters().promise();
    resources.eksClusters = clusters.clusters.filter(cluster =>
      cluster.includes(config.PROJECT_NAME)
    );

    return resources;
  } catch (error) {
    console.error('Error getting resources:', error);
    throw error;
  }
}

/**
 * Run all security checks
 */
async function runSecurityChecks(resources) {
  const results = {
    timestamp: new Date().toISOString(),
    environment: process.env.ENVIRONMENT,
    checks: []
  };

  // Security Group Checks
  for (const sg of resources.securityGroups) {
    results.checks.push(await checkSecurityGroup(sg));
  }

  // S3 Bucket Checks
  for (const bucket of resources.s3Buckets) {
    results.checks.push(await checkS3Bucket(bucket));
  }

  // IAM Role Checks
  for (const role of resources.iamRoles) {
    results.checks.push(await checkIAMRole(role));
  }

  // EKS Cluster Checks
  for (const cluster of resources.eksClusters) {
    results.checks.push(await checkEKSCluster(cluster));
  }

  return results;
}

/**
 * Check security group configuration
 */
async function checkSecurityGroup(sg) {
  const check = {
    resourceType: 'SecurityGroup',
    resourceId: sg.GroupId,
    checks: []
  };

  // Check for open ports
  const hasOpenPorts = sg.IpPermissions.some(perm =>
    perm.IpRanges.some(range => range.CidrIp === '0.0.0.0/0')
  );

  check.checks.push({
    name: 'open-ports',
    status: hasOpenPorts ? STATUS.FAIL : STATUS.PASS,
    details: hasOpenPorts ? 'Security group has ports open to 0.0.0.0/0' : null
  });

  return check;
}

/**
 * Check S3 bucket configuration
 */
async function checkS3Bucket(bucket) {
  const check = {
    resourceType: 'S3Bucket',
    resourceId: bucket.Name,
    checks: []
  };

  try {
    // Check public access
    const publicAccess = await s3.getBucketPublicAccessBlock({
      Bucket: bucket.Name
    }).promise();

    check.checks.push({
      name: 'public-access',
      status: publicAccess.PublicAccessBlockConfiguration.BlockPublicAcls ? 
        STATUS.PASS : STATUS.FAIL,
      details: 'Public access block configuration'
    });

    // Check encryption
    const encryption = await s3.getBucketEncryption({
      Bucket: bucket.Name
    }).promise();

    check.checks.push({
      name: 'encryption',
      status: encryption.ServerSideEncryptionConfiguration ? 
        STATUS.PASS : STATUS.FAIL,
      details: 'Default encryption configuration'
    });
  } catch (error) {
    console.error(`Error checking bucket ${bucket.Name}:`, error);
    check.checks.push({
      name: 'bucket-check',
      status: STATUS.ERROR,
      details: error.message
    });
  }

  return check;
}

/**
 * Check IAM role configuration
 */
async function checkIAMRole(role) {
  const check = {
    resourceType: 'IAMRole',
    resourceId: role.RoleName,
    checks: []
  };

  try {
    // Get attached policies
    const policies = await iam.listRolePolicies({
      RoleName: role.RoleName
    }).promise();

    // Check for overly permissive policies
    for (const policyName of policies.PolicyNames) {
      const policy = await iam.getRolePolicy({
        RoleName: role.RoleName,
        PolicyName: policyName
      }).promise();

      const hasWildcardPermissions = JSON.stringify(policy.PolicyDocument)
        .includes('"Action": "*"');

      check.checks.push({
        name: `policy-${policyName}`,
        status: hasWildcardPermissions ? STATUS.FAIL : STATUS.PASS,
        details: hasWildcardPermissions ? 
          'Policy contains wildcard permissions' : null
      });
    }
  } catch (error) {
    console.error(`Error checking role ${role.RoleName}:`, error);
    check.checks.push({
      name: 'role-check',
      status: STATUS.ERROR,
      details: error.message
    });
  }

  return check;
}

/**
 * Check EKS cluster configuration
 */
async function checkEKSCluster(clusterName) {
  const check = {
    resourceType: 'EKSCluster',
    resourceId: clusterName,
    checks: []
  };

  try {
    const cluster = await eks.describeCluster({
      name: clusterName
    }).promise();

    // Check endpoint access
    check.checks.push({
      name: 'private-endpoint',
      status: cluster.cluster.resourcesVpcConfig.endpointPrivateAccess ? 
        STATUS.PASS : STATUS.FAIL,
      details: 'Private endpoint access configuration'
    });

    // Check encryption
    check.checks.push({
      name: 'encryption',
      status: cluster.cluster.encryptionConfig ? 
        STATUS.PASS : STATUS.FAIL,
      details: 'Encryption configuration'
    });

    // Check logging
    check.checks.push({
      name: 'logging',
      status: cluster.cluster.logging.clusterLogging.some(l => l.enabled) ? 
        STATUS.PASS : STATUS.FAIL,
      details: 'Control plane logging configuration'
    });
  } catch (error) {
    console.error(`Error checking cluster ${clusterName}:`, error);
    check.checks.push({
      name: 'cluster-check',
      status: STATUS.ERROR,
      details: error.message
    });
  }

  return check;
}

/**
 * Process check results
 */
async function processResults(results) {
  // Count failures
  const failures = results.checks.reduce((count, check) => 
    count + check.checks.filter(c => c.status === STATUS.FAIL).length, 0
  );

  // Put metrics
  await cloudwatch.putMetricData({
    Namespace: 'CloudSecDemo',
    MetricData: [
      {
        MetricName: 'SecurityCheckFailures',
        Value: failures,
        Unit: 'Count',
        Dimensions: [
          {
            Name: 'Environment',
            Value: process.env.ENVIRONMENT
          }
        ]
      }
    ]
  }).promise();

  // Send alert if there are failures
  if (failures > 0) {
    await sendAlert({
      title: 'Security Check Failures',
      message: `Found ${failures} security check failures`,
      severity: 'HIGH',
      details: results
    });
  }
}

/**
 * Send alert via SNS
 */
async function sendAlert({ title, message, severity, details }) {
  try {
    await sns.publish({
      TopicArn: process.env.SNS_TOPIC_ARN,
      Subject: `[${severity}] ${title}`,
      Message: JSON.stringify({
        message,
        severity,
        timestamp: new Date().toISOString(),
        details
      }, null, 2)
    }).promise();
  } catch (error) {
    console.error('Error sending alert:', error);
    throw error;
  }
}
