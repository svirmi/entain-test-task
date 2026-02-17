package repository

import (
	"database/sql"
	"errors"
)

var (
	ErrUserNotFound         = errors.New("user not found")
	ErrInsufficientBalance  = errors.New("insufficient balance")
	ErrDuplicateTransaction = errors.New("transaction already processed")
	ErrNegativeBalance      = errors.New("balance cannot be negative")
)

type UserRepository struct {
	db *sql.DB
}

func NewUserRepository(db *sql.DB) *UserRepository {
	return &UserRepository{db: db}
}
