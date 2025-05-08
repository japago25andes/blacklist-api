{
  "pipeline": {
    "name": "pipeline-blacklist-api",
    "roleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/codepipeline-blacklist-role",
    "artifactStore": {
      "type": "S3",
      "location": "blacklist-pipeline-artifacts-${AWS_ACCOUNT_ID}"
    },
    "stages": [
      {
        "name": "Source",
        "actions": [
          {
            "name": "GitHub_Source",
            "actionTypeId": {
              "category": "Source",
              "owner": "ThirdParty",
              "provider": "GitHub",
              "version": "1"
            },
            "outputArtifacts": [{ "name": "SourceOutput" }],
            "configuration": {
              "Owner": "${REPO_OWNER}",
              "Repo": "${REPO_NAME}",
              "Branch": "${BRANCH}",
              "OAuthToken": "${GITHUB_PAT}",
              "PollForSourceChanges": "true"
            },
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Test",
        "actions": [
          {
            "name": "Run_Tests",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "inputArtifacts": [{ "name": "SourceOutput" }],
            "configuration": {
              "ProjectName": "test-${REPO_NAME}"
            },
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Build",
        "actions": [
          {
            "name": "Build_Docker",
            "actionTypeId": {
              "category": "Build",
              "owner": "AWS",
              "provider": "CodeBuild",
              "version": "1"
            },
            "inputArtifacts": [{ "name": "SourceOutput" }],
            "outputArtifacts": [{ "name": "BuildOutput" }],
            "configuration": {
              "ProjectName": "build-${REPO_NAME}"
            },
            "runOrder": 1
          }
        ]
      },
      {
        "name": "Deploy",
        "actions": [
          {
            "name": "CodeDeploy_DeployToECS",
            "actionTypeId": {
              "category": "Deploy",
              "owner": "AWS",
              "provider": "CodeDeploy",
              "version": "1"
            },
            "inputArtifacts": [{ "name": "BuildOutput" }],
            "configuration": {
              "ApplicationName": "${CD_APP_NAME}",
              "DeploymentGroupName": "${CD_DG_NAME}"
            },
            "runOrder": 1
          }
        ]
      }
    ]
  }
}