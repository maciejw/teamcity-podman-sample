using Aspire.Hosting;

var builder = DistributedApplication.CreateBuilder(args);
var sqlPassword = builder.AddParameter("sql-password", secret: true);

builder.AddSqlServer("sql", password: sqlPassword);
builder.AddKafka("kafka");

builder.Build().Run();
