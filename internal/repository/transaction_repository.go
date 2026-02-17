package repository

import (
	"database/sql"
	"fmt"
	"math/big"

	"github.com/svirmi/entain-test-task/internal/helpers"
	"github.com/svirmi/entain-test-task/internal/model"

	"github.com/lib/pq"
)

type TransactionRepository struct {
	db *sql.DB
}

func NewTransactionRepository(db *sql.DB) *TransactionRepository {
	return &TransactionRepository{db: db}
}

// ProcessTransaction opens a DB transaction, locks the user row, updates the
// balance, and inserts an atomic transaction record to prevent data race
func (r *TransactionRepository) ProcessTransaction(userID uint64, req *model.TransactionRequest, sourceType string) error {
	tx, err := r.db.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Parse and validate amount.
	amount, ok := new(big.Rat).SetString(req.Amount)
	if !ok {
		return fmt.Errorf("invalid amount format")
	}
	if amount.Sign() <= 0 {
		return fmt.Errorf("amount must be positive")
	}

	var currentBalanceStr string
	err = tx.QueryRow(
		`SELECT balance FROM users WHERE id = $1 FOR UPDATE`,
		userID,
	).Scan(&currentBalanceStr)
	if err == sql.ErrNoRows {
		return ErrUserNotFound
	}
	if err != nil {
		return fmt.Errorf("failed to lock user: %w", err)
	}

	// Calculate new balance.
	currentBalance, ok := new(big.Rat).SetString(currentBalanceStr)
	if !ok {
		return fmt.Errorf("invalid current balance in database")
	}

	var newBalance *big.Rat
	if req.State == "win" {
		newBalance = new(big.Rat).Add(currentBalance, amount)
	} else {
		newBalance = new(big.Rat).Sub(currentBalance, amount)
	}

	if newBalance.Sign() < 0 {
		return ErrInsufficientBalance
	}

	_, err = tx.Exec(
		`UPDATE users SET balance = $1, updated_at = NOW() WHERE id = $2`,
		helpers.RatToDecimal(newBalance), userID,
	)
	if err != nil {
		return fmt.Errorf("failed to update balance: %w", err)
	}

	_, err = tx.Exec(
		`INSERT INTO transactions (user_id, transaction_id, source_type, state, amount, processed_at)
		 VALUES ($1, $2, $3, $4, $5, NOW())`,
		userID, req.TransactionID, sourceType, req.State, req.Amount,
	)
	if err != nil {
		if pqErr, ok := err.(*pq.Error); ok && pqErr.Code == "23505" {
			return ErrDuplicateTransaction
		}
		return fmt.Errorf("failed to insert transaction: %w", err)
	}

	if err = tx.Commit(); err != nil {
		return fmt.Errorf("failed to commit transaction: %w", err)
	}
	return nil
}
