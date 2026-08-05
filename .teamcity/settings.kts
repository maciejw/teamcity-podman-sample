import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.*
import jetbrains.buildServer.configs.kotlin.triggers.vcs

version = "2026.1"

project {
    buildType(MssqlTestcontainers)
}

object MssqlTestcontainers : BuildType({
    id("MssqlTestcontainers")
    name = "MSSQL Testcontainers"

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        script {
            id = "prepare_build_network"
            name = "Prepare isolated build network"
            scriptContent = """
                #!/bin/sh
                set -eu

                owner="teamcity-mssql-sample"
                network="tc-build-%teamcity.build.id%"

                docker ps -aq \
                  --filter "label=tc.owner=${'$'}owner" \
                  --filter "label=tc.build.id=%teamcity.build.id%" | xargs -r docker rm -f
                docker network ls -q \
                  --filter "label=tc.owner=${'$'}owner" \
                  --filter "label=tc.build.id=%teamcity.build.id%" | xargs -r docker network rm
                docker network create \
                  --label "tc.owner=${'$'}owner" \
                  --label "tc.build.id=%teamcity.build.id%" \
                  "${'$'}network"
            """.trimIndent()
        }

        dotnetTest {
            id = "run_integration_tests"
            name = "Run .NET tests in isolated SDK container"
            projects = "Sample.sln"
            configuration = "Release"
            dockerImage = "mcr.microsoft.com/dotnet/sdk:10.0"
            dockerPull = true
            dockerRunParameters = """
                --network tc-build-%teamcity.build.id%
                --label tc.owner=teamcity-mssql-sample
                --label tc.build.id=%teamcity.build.id%
                -v /run/user/1000/podman/podman.sock:/var/run/docker.sock
                -e DOCKER_HOST=unix:///var/run/docker.sock
                -e TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
                -e TESTCONTAINERS_RYUK_DISABLED=true
                -e TESTCONTAINERS_HOST_OVERRIDE=host.containers.internal
                -e TC_BUILD_NETWORK=tc-build-%teamcity.build.id%
                -e TC_BUILD_ID=%teamcity.build.id%
                -e TC_RESOURCE_OWNER=teamcity-mssql-sample
            """.trimIndent().replace("\n", " ")
        }

        script {
            id = "cleanup_build_resources"
            name = "Clean isolated build resources"
            executionMode = BuildStep.ExecutionMode.ALWAYS
            scriptContent = """
                #!/bin/sh
                set -eu

                docker ps -aq \
                  --filter "label=tc.owner=teamcity-mssql-sample" \
                  --filter "label=tc.build.id=%teamcity.build.id%" | xargs -r docker rm -f
                docker network rm "tc-build-%teamcity.build.id%" 2>/dev/null || true
            """.trimIndent()
        }
    }

    triggers {
        vcs { }
    }

    requirements {
        exists("docker.server.version")
        contains("teamcity.agent.jvm.os.name", "Linux")
    }
})
