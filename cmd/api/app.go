// file cmd/api/app.go

package main

import (
	"database/sql"
	"log/slog"
	"os"
	"sync"

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
	wg     sync.WaitGroup // tracks in-flight requests for graceful shutdown
}

func newApplication() (*application, error) {

	logger := slog.New(slog.NewJSONHandler(os.Stdout, nil))

	cfg := config{}

	cfg.port = helpers.GetEnvAsStr("PORT", "8000")
	cfg.env = helpers.GetEnvAsStr("ENV", "development")
	cfg.shutdownTimeout = helpers.GetEnvAsStr("SHUTDOWN_TIMEOUT", "30s")
	cfg.db.host = helpers.GetEnvAsStr("DB_HOST", "postgres")
	cfg.db.port = helpers.GetEnvAsStr("DB_PORT", "5432")
	cfg.db.user = helpers.GetEnvAsStr("DB_USER", "postgres")
	cfg.db.password = helpers.GetEnvAsStr("DB_PASSWORD", "postgres")
	cfg.db.name = helpers.GetEnvAsStr("DB_NAME", "transactions")

	db, err := helpers.OpenDB(helpers.DBConfig{
		Host:     cfg.db.host,
		Port:     cfg.db.port,
		User:     cfg.db.user,
		Password: cfg.db.password,
		Name:     cfg.db.name,
	}, logger)

	if err != nil {
		return nil, err
	}

	return &application{
		config: cfg,
		logger: logger,
		db:     db,
	}, nil
}
