package service

import (
	"github.com/svirmi/entain-test-task/internal/model"
	"github.com/svirmi/entain-test-task/internal/repository"
)

type TransactionService struct {
	repo *repository.TransactionRepository
}

func NewTransactionService(repo *repository.TransactionRepository) *TransactionService {
	return &TransactionService{repo: repo}
}

func (s *TransactionService) ProcessTransaction(userID uint64, req *model.TransactionRequest, sourceType string) error {
	return s.repo.ProcessTransaction(userID, req, sourceType)
}
