import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.*

version = "2026.1"

project { buildType(AspireIntegrationTests) }

object AspireIntegrationTests : BuildType({
    id("AspireIntegrationTests")
    name = "Aspire SQL Server and Kafka"
    vcs { root(DslContext.settingsRoot) }
    steps {
        dotnetTest {
            id = "run_integration_tests"
            name = "Run Aspire integration tests in SDK container"
            projects = "samples/aspire/Sample.slnx"
            configuration = "Release"
            dockerImage = "mcr.microsoft.com/dotnet/sdk:10.0"
            dockerRunParameters = """
                -v /run/user/1000/podman/podman.sock:/var/run/docker.sock
                -e DOCKER_HOST=unix:///var/run/docker.sock
                -e ASPIRE_CONTAINER_RUNTIME=podman
            """.trimIndent().replace("\n", " ")
        }
    }
    requirements {
        exists("podman.version")
        contains("teamcity.agent.jvm.os.name", "Linux")
    }
})
