package model

import "time"

type User struct {
	ID        uint64    `json:"id"`
	Balance   string    `json:"balance"`
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Transaction struct {
	ID            uint64    `json:"id"`
	UserID        uint64    `json:"user_id"`
	TransactionID string    `json:"transaction_id"`
	SourceType    string    `json:"source_type"`
	State         string    `json:"state"`
	Amount        string    `json:"amount"`
	ProcessedAt   time.Time `json:"processed_at"`
}

type TransactionRequest struct {
	State         string `json:"state"`
	Amount        string `json:"amount"`
	TransactionID string `json:"transactionId"`
}

type BalanceResponse struct {
	UserID  uint64 `json:"userId"`
	Balance string `json:"balance"`
}

type ErrorResponse struct {
	Error string `json:"error"`
}
