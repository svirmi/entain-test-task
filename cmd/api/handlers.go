package main

import (
	"encoding/json"
	"net/http"

	"github.com/svirmi/entain-test-task/internal/helpers"
	"github.com/svirmi/entain-test-task/internal/model"
)

func (app *application) createTransaction(w http.ResponseWriter, r *http.Request) {

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
}

func (app *application) getUserBalance(w http.ResponseWriter, r *http.Request) {

	balance := model.BalanceResponse{
		UserID:  1234,
		Balance: "100",
	}

	helpers.WriteJSON(w, http.StatusOK, balance)
}

func (app *application) healthCheck(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}
