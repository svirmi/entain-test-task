package service

import (
	"github.com/svirmi/entain-test-task/internal/repository"
)

type TransactionService struct {
	repo *repository.UserRepository
}
