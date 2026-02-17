package main

import (
	"database/sql"
	"log/slog"
	"os"

	"github.com/svirmi/entain-test-task/internal/helpers"
)

type config struct {
	port            string
	env             string
	shutdownTimeout string
	db              struct {
		host     string
		port     string
		user     string
		password string
		name     string
	}
}

type application struct {
	config config
	logger *slog.Logger
	db     *sql.DB
}

func newApplication() *application {
	cfg := config{}

	cfg.port = helpers.GetEnvAsStr("PORT", "8080")
	cfg.env = helpers.GetEnvAsStr("ENV", "development")
	cfg.shutdownTimeout = helpers.GetEnvAsStr("SHUTDOWN_TIMEOUT", "30s")
	cfg.db.host = helpers.GetEnvAsStr("DB_HOST", "postgres")
	cfg.db.port = helpers.GetEnvAsStr("DB_PORT", "5432")
	cfg.db.user = helpers.GetEnvAsStr("DB_USER", "postgres")
	cfg.db.password = helpers.GetEnvAsStr("DB_PASSWORD", "postgres")
	cfg.db.name = helpers.GetEnvAsStr("DB_NAME", "transactions")

	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	return &application{
		config: cfg,
		logger: logger,
	}
}
