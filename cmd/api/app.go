package main

import (
	"database/sql"
	"log/slog"
)

type config struct {
	port int
	env  string
}

type application struct {
	config config
	logger *slog.Logger

	db *sql.DB
}

func newApplication() *application {
	return &application{}
}
