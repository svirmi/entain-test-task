package service

import (
	"github.com/svirmi/entain-test-task/internal/model"
	"github.com/svirmi/entain-test-task/internal/repository"
)

// UserService handles queries about user state.
type UserService struct {
	repo *repository.UserRepository
}

func NewUserService(repo *repository.UserRepository) *UserService {
	return &UserService{repo: repo}
}

// GetBalance returns the formatted balance for the given user.
func (s *UserService) GetBalance(userID uint64) (*model.BalanceResponse, error) {
	balance, err := s.repo.GetBalance(userID)
	if err != nil {
		return nil, err
	}
	return &model.BalanceResponse{
		UserID:  userID,
		Balance: balance,
	}, nil
}
