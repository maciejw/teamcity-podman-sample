using Microsoft.Data.SqlClient;

namespace Sample.Data;

public sealed class WidgetRepository(string connectionString)
{
    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        const string sql = """
            IF OBJECT_ID(N'dbo.Widgets', N'U') IS NULL
            BEGIN
                CREATE TABLE dbo.Widgets
                (
                    Id INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
                    Name NVARCHAR(200) NOT NULL
                );
            END;
            """;

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        await command.ExecuteNonQueryAsync(cancellationToken);
    }

    public async Task<int> AddAsync(string name, CancellationToken cancellationToken = default)
    {
        const string sql = """
            INSERT INTO dbo.Widgets (Name)
            OUTPUT INSERTED.Id
            VALUES (@name);
            """;

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.AddWithValue("@name", name);
        return Convert.ToInt32(await command.ExecuteScalarAsync(cancellationToken));
    }

    public async Task<Widget?> FindAsync(int id, CancellationToken cancellationToken = default)
    {
        const string sql = "SELECT Id, Name FROM dbo.Widgets WHERE Id = @id;";

        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellationToken);
        await using var command = new SqlCommand(sql, connection);
        command.Parameters.AddWithValue("@id", id);
        await using var reader = await command.ExecuteReaderAsync(cancellationToken);
        return await reader.ReadAsync(cancellationToken)
            ? new Widget(reader.GetInt32(0), reader.GetString(1))
            : null;
    }
}
