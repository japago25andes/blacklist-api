{
  "webhook": {
    "name": "${WEBHOOK_NAME}",
    "targetPipeline": "pipeline-${REPO_NAME}",
    "targetAction": "GitHub_Source",
    "filters": [
      {
        "jsonPath": "$.ref",
        "matchEquals": "refs/heads/${BRANCH}"
      }
    ],
    "authentication": "GITHUB_HMAC",
    "authenticationConfiguration": {
      "SecretToken": "${GITHUB_WEBHOOK_SECRET}"
    }
  }
}