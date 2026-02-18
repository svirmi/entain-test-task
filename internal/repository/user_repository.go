package repository

import (
	"database/sql"
	"fmt"

	"github.com/svirmi/entain-test-task/internal/helpers"
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}

// GetBalance returns the current balance for userID, formatted to 2 decimal places.
func (r *UserRepository) GetBalance(userID uint64) (string, error) {
	var raw string
	err := r.db.QueryRow(`SELECT balance FROM users WHERE id = $1`, userID).Scan(&raw)
	if err == sql.ErrNoRows {
		return "", ErrUserNotFound
	}
	if err != nil {
		return "", fmt.Errorf("failed to get balance: %w", err)
	}

	// Normalise to exactly 2 decimal places.
	formatted, err := helpers.ParseAndFormat(raw)
	if err != nil {
		return "", fmt.Errorf("failed to format balance: %w", err)
	}
	return formatted, nil
}
