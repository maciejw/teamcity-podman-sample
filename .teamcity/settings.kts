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

    params {
        param("build.network.name", "tc-%teamcity.agent.name%-%teamcity.buildType.id%")
    }

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        script {
            id = "prepare_build_network"
            name = "Ensure persistent build network"
            scriptContent = """
                #!/bin/sh
                set -eu

                owner="teamcity-mssql-sample"
                network="%build.network.name%"

                if ! docker network inspect "${'$'}network" >/dev/null 2>&1; then
                  docker network create \
                    --label "tc.owner=${'$'}owner" \
                    --label "tc.agent.name=%teamcity.agent.name%" \
                    --label "tc.buildType.id=%teamcity.buildType.id%" \
                    "${'$'}network"
                fi
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
                --network %build.network.name%
                --label tc.owner=teamcity-mssql-sample
                --label tc.agent.name=%teamcity.agent.name%
                --label tc.buildType.id=%teamcity.buildType.id%
                --label tc.build.id=%teamcity.build.id%
                -v /run/user/1000/podman/podman.sock:/var/run/docker.sock
                -e DOCKER_HOST=unix:///var/run/docker.sock
                -e TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE=/var/run/docker.sock
                -e TESTCONTAINERS_HOST_OVERRIDE=host.containers.internal
                -e TC_BUILD_NETWORK=%build.network.name%
                -e TC_BUILD_ID=%teamcity.build.id%
                -e TC_AGENT_NAME=%teamcity.agent.name%
                -e TC_BUILD_TYPE_ID=%teamcity.buildType.id%
                -e TC_RESOURCE_OWNER=teamcity-mssql-sample
            """.trimIndent().replace("\n", " ")
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
