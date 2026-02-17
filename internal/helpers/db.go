// file internal/helpers/db.go

package helpers

import (
	"database/sql"
	"fmt"
	"log/slog"
	"time"
)

type DBConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	Name     string
}

func OpenDB(cfg DBConfig, logger *slog.Logger) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.Name,
	)

	var db *sql.DB
	var err error
	for i := 0; i < 5; i++ {
		db, err = sql.Open("postgres", dsn)
		if err == nil {
			if err = db.Ping(); err == nil {
				break
			}
		}
		logger.Info("waiting for database", "attempt", i+1, "of", 5)
		time.Sleep(2 * time.Second)
	}
	if err != nil {
		return nil, fmt.Errorf("could not reach database after 30 attempts: %w", err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	logger.Info("database connection established")

	if err := RunMigrations(db, logger); err != nil {
		return nil, err
	}
	return db, nil
}

// RunMigrations creates tables, indexes, and seed rows idempotently.
func RunMigrations(db *sql.DB, logger *slog.Logger) error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS users (
			id         BIGSERIAL PRIMARY KEY,
			balance    NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
			created_at TIMESTAMP    NOT NULL DEFAULT NOW(),
			updated_at TIMESTAMP    NOT NULL DEFAULT NOW()
		)`,
		`CREATE TABLE IF NOT EXISTS transactions (
			id             BIGSERIAL     PRIMARY KEY,
			user_id        BIGINT        NOT NULL REFERENCES users(id),
			transaction_id VARCHAR(255)  NOT NULL UNIQUE,
			source_type    VARCHAR(50)   NOT NULL,
			state          VARCHAR(10)   NOT NULL,
			amount         NUMERIC(20,2) NOT NULL,
			processed_at   TIMESTAMP     NOT NULL DEFAULT NOW()
		)`,
		`CREATE INDEX IF NOT EXISTS idx_transactions_user_id
			ON transactions(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_transactions_transaction_id
			ON transactions(transaction_id)`,
		`INSERT INTO users (id, balance) VALUES (1, 100.00), (2, 50.00), (3, 75.00)
			ON CONFLICT (id) DO NOTHING`,
	}
	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return fmt.Errorf("migration failed: %w", err)
		}
	}
	logger.Info("migrations completed")
	return nil
}
