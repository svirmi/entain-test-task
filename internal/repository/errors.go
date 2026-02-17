package repository

import "errors"

var (
	ErrUserNotFound         = errors.New("user not found")
	ErrInsufficientBalance  = errors.New("insufficient balance")
	ErrDuplicateTransaction = errors.New("transaction already processed")
)
