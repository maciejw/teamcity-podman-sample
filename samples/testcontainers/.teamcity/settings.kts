import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.*

version = "2026.1"

project {
    buildType(MssqlTestcontainers)
}

object MssqlTestcontainers : BuildType({
    id("MssqlTestcontainers")
    name = "MSSQL and Kafka Testcontainers"

    vcs {
        root(DslContext.settingsRoot)
    }

    steps {
        dockerCompose {
            id = "start_network_anchor"
            name = "Start build network anchor"
            file = "samples/testcontainers/compose.yaml"
        }

        dotnetTest {
            id = "run_integration_tests"
            name = "Run .NET tests in isolated SDK container"
            projects = "samples/testcontainers/Sample.slnx"
            configuration = "Release"
            dockerImage = "mcr.microsoft.com/dotnet/sdk:10.0"
            dockerRunParameters = """
                -v /run/user/1000/podman/podman.sock:/var/run/docker.sock
                -e DOCKER_HOST=unix:///var/run/docker.sock
                -e TESTCONTAINERS_HOST_OVERRIDE=host.containers.internal
                -e TEAMCITY_DOCKER_NETWORK
            """.trimIndent().replace("\n", " ")
        }
    }

    requirements {
        exists("podman.version")
        exists("podmanCompose.version")
        contains("teamcity.agent.jvm.os.name", "Linux")
    }
})
