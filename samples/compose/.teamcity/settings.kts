import jetbrains.buildServer.configs.kotlin.*
import jetbrains.buildServer.configs.kotlin.buildSteps.*

version = "2026.1"

project {
    buildType(MssqlKafkaCompose)
}

object MssqlKafkaCompose : BuildType({
    id("MssqlKafkaCompose")
    name = "MSSQL and Kafka Compose"

    vcs {
        root(DslContext.settingsRoot)
    }

    params {
        param("env.COMPOSE_PROJECT_NAME", "teamcity-%teamcity.agent.name%-%system.teamcity.buildType.id%")
    }

    steps {
        dockerCompose {
            id = "start_compose_services"
            name = "Start SQL Server and Kafka"
            file = "samples/compose/compose.yaml"
        }

        dotnetTest {
            id = "run_integration_tests"
            name = "Run .NET tests on the Compose network"
            projects = "samples/compose/Sample.slnx"
            configuration = "Release"
            dockerImage = "mcr.microsoft.com/dotnet/sdk:10.0"
        }
    }

    requirements {
        exists("podman.version")
        exists("podmanCompose.version")
        contains("teamcity.agent.jvm.os.name", "Linux")
    }
})
