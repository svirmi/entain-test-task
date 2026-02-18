package helpers

import (
	"database/sql"
	"fmt"
	"log/slog"
	"time"

	_ "github.com/lib/pq"
)

const DB_CONNECTIONS_ATTEMPTS = 5

type DBConfig struct {
	Host     string
	Port     string
	User     string
	Password string
	Name     string
	Env      string
}

// OpenDB opens the database connection and handles migrations.
// If the environment variable "ENV" is set to "test", it will run MigrateDown followed by MigrateUp.
func OpenDB(cfg DBConfig, logger *slog.Logger) (*sql.DB, error) {
	dsn := fmt.Sprintf(
		"host=%s port=%s user=%s password=%s dbname=%s sslmode=disable",
		cfg.Host, cfg.Port, cfg.User, cfg.Password, cfg.Name,
	)

	fmt.Println(dsn)

	var db *sql.DB
	var err error

	for i := 0; i < DB_CONNECTIONS_ATTEMPTS; i++ {
		db, err = sql.Open("postgres", dsn)
		if err == nil {
			if err = db.Ping(); err == nil {
				break
			}
		}
		logger.Info("waiting for database", "attempt", i+1, "of", DB_CONNECTIONS_ATTEMPTS)
		time.Sleep(2 * time.Second)
	}

	if err != nil {
		return nil, fmt.Errorf("could not reach database after %d attempts: %w", DB_CONNECTIONS_ATTEMPTS, err)
	}

	db.SetMaxOpenConns(25)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(5 * time.Minute)
	logger.Info("database connection established")

	// Check if we should reset the DB (test env only)
	if cfg.Env == "test" {
		if err := MigrateDown(db, logger); err != nil {
			return nil, err
		}
		logger.Info("Tables dropped...")
	}

	if err := MigrateUp(db, logger); err != nil {
		return nil, err
	}

	return db, nil
}

// MigrateUp creates tables, indexes, and seeds data.
func MigrateUp(db *sql.DB, logger *slog.Logger) error {
	stmts := []string{
		// 1. Create Users Table
		`CREATE TABLE IF NOT EXISTS users (
            id         BIGSERIAL PRIMARY KEY,
            balance    NUMERIC(20,2) NOT NULL DEFAULT 0 CHECK (balance >= 0),
            created_at TIMESTAMP    NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMP    NOT NULL DEFAULT NOW()
        )`,

		// 2. Create Transactions Table (References users)
		`CREATE TABLE IF NOT EXISTS transactions (
            id             BIGSERIAL     PRIMARY KEY,
            user_id        BIGINT        NOT NULL REFERENCES users(id),
            transaction_id VARCHAR(255)  NOT NULL UNIQUE,
            source_type    VARCHAR(50)   NOT NULL,
            state          VARCHAR(10)   NOT NULL,
            amount         NUMERIC(20,2) NOT NULL,
            processed_at   TIMESTAMP     NOT NULL DEFAULT NOW()
        )`,

		// 3. Create Indexes
		`CREATE INDEX IF NOT EXISTS idx_transactions_user_id
            ON transactions(user_id)`,
		`CREATE INDEX IF NOT EXISTS idx_transactions_transaction_id
            ON transactions(transaction_id)`,

		// 4. Seed Data
		`INSERT INTO users (id, balance) VALUES (1, 100.00), (2, 50.00), (3, 75.00)
            ON CONFLICT (id) DO NOTHING`,
	}

	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return fmt.Errorf("migration UP failed: %w", err)
		}
	}
	logger.Info("migrations UP completed")
	return nil
}

// MigrateDown drops the tables created in MigrateUp.
// Note: We drop 'transactions' first because it has a Foreign Key to 'users'.
func MigrateDown(db *sql.DB, logger *slog.Logger) error {
	stmts := []string{
		`DROP TABLE IF EXISTS transactions`,
		`DROP TABLE IF EXISTS users`,
	}

	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return fmt.Errorf("migration DOWN failed: %w", err)
		}
	}
	logger.Info("migrations DOWN completed")
	return nil
}
