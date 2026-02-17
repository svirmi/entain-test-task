package main

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"

	"github.com/svirmi/entain-test-task/internal/helpers"
	"github.com/svirmi/entain-test-task/internal/model"
	"github.com/svirmi/entain-test-task/internal/repository"
)

// createTransaction() POST /user/{userId}/transaction
func (app *application) createTransaction(w http.ResponseWriter, r *http.Request) {
	userID, err := helpers.ParseUserID(r)
	if err != nil {
		helpers.WriteError(w, http.StatusBadRequest, "invalid user id")
		return
	}

	sourceType := r.Header.Get("Source-Type")
	if sourceType == "" {
		helpers.WriteError(w, http.StatusBadRequest, "Source-Type header is required")
		return
	}

	validSourceTypes := helpers.ValidSourceTypes()
	if !validSourceTypes[sourceType] {
		helpers.WriteError(w, http.StatusBadRequest, "invalid Source-Type")
		return
	}

	body, err := io.ReadAll(r.Body)
	if err != nil {
		helpers.WriteError(w, http.StatusBadRequest, "failed to read request body")
		return
	}
	defer r.Body.Close()

	var req model.TransactionRequest
	if err := json.Unmarshal(body, &req); err != nil {
		helpers.WriteError(w, http.StatusBadRequest, "invalid JSON")
		return
	}
	if req.State != "win" && req.State != "lose" {
		helpers.WriteError(w, http.StatusBadRequest, "state must be 'win' or 'lose'")
		return
	}
	if req.Amount == "" {
		helpers.WriteError(w, http.StatusBadRequest, "amount is required")
		return
	}
	if req.TransactionID == "" {
		helpers.WriteError(w, http.StatusBadRequest, "transactionId is required")
		return
	}

	err = app.txService.ProcessTransaction(userID, &req, sourceType)
	if err != nil {
		switch {
		case errors.Is(err, repository.ErrUserNotFound):
			helpers.WriteError(w, http.StatusNotFound, "user not found")
		case errors.Is(err, repository.ErrInsufficientBalance):
			helpers.WriteError(w, http.StatusBadRequest, "insufficient balance")
		case errors.Is(err, repository.ErrDuplicateTransaction):
			helpers.WriteJSON(w, http.StatusOK, map[string]string{"message": "transaction already processed"})
		default:
			app.logger.Error("processTransaction failed", "userID", userID, "error", err)
			helpers.WriteError(w, http.StatusInternalServerError, "internal server error")
		}
		return
	}

	helpers.WriteJSON(w, http.StatusOK, map[string]string{"message": "transaction processed successfully"})
}

// getUserBalance() handles GET  /user/{userId}/balance
func (app *application) getUserBalance(w http.ResponseWriter, r *http.Request) {
	userID, err := helpers.ParseUserID(r)
	if err != nil {
		helpers.WriteError(w, http.StatusBadRequest, "invalid user id")
		return
	}

	balance, err := app.userService.GetBalance(userID)
	if err != nil {
		if errors.Is(err, repository.ErrUserNotFound) {
			helpers.WriteError(w, http.StatusNotFound, "user not found")
			return
		}
		app.logger.Error("getBalance failed", "userID", userID, "error", err)
		helpers.WriteError(w, http.StatusInternalServerError, "internal server error")
		return
	}

	helpers.WriteJSON(w, http.StatusOK, balance)
}

func (app *application) healthCheck(w http.ResponseWriter, r *http.Request) {
	helpers.WriteJSON(w, http.StatusOK, map[string]string{
		"status": "ok",
		"env":    app.config.env,
	})
}
